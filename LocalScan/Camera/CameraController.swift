import AVFoundation
import Combine
import CoreGraphics
import Foundation
import QuartzCore

/// 相机：后置广角、照片预设、照片输出 + 视频帧输出（串行队列）。
/// 拍摄结果只发布到内存，不落盘、不上传。
final class CameraController: NSObject, ObservableObject {
    enum AuthorizationState: Equatable {
        case unknown, authorized, denied, restricted, unavailable
    }

    @Published private(set) var authorizationState: AuthorizationState = .unknown
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastCapturedData: Data?
    @Published private(set) var overlayQuad: Quad?
    @Published private(set) var detectedFrameSize: CGSize = .zero
    @Published var isAutoCaptureEnabled = true {
        didSet {
            guard !isAutoCaptureEnabled else { return }
            stability.reset()
        }
    }

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.kdnsna.localscan.camera.session")
    private let videoQueue = DispatchQueue(label: "com.kdnsna.localscan.camera.video",
                                          qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let detector = DocumentDetector()
    private let captureLock = NSLock()

    private var smoother = QuadSmoother()
    private var stability = StabilityDetector()
    private var isConfigured = false
    private var isRequestingAuthorization = false
    private var isCaptureInFlight = false
    private var captureCompletion: ((Data?) -> Void)?
    private var lastDetectionTime = CACurrentMediaTime()

    // MARK: - Lifecycle

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            publish(.authorized)
            configureAndStart()
        case .notDetermined:
            guard !isRequestingAuthorization else { return }
            isRequestingAuthorization = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isRequestingAuthorization = false
                    if granted {
                        self.publish(.authorized)
                        self.configureAndStart()
                    } else {
                        self.publish(.denied, error: "相机权限被拒绝，请在设置中允许 LocalScan 使用相机。")
                    }
                }
            }
        case .denied:
            stop()
            publish(.denied, error: "相机权限被拒绝，请在设置中允许 LocalScan 使用相机。")
        case .restricted:
            stop()
            publish(.restricted, error: "相机受系统限制，无法使用。")
        @unknown default:
            publish(.denied, error: "无法获取相机权限。")
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.isRunning = false
                self.overlayQuad = nil
                self.smoother = QuadSmoother()
                self.stability.reset()
            }
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                guard self.configureSession() else { return }
                self.isConfigured = true
            }
            if !self.session.isRunning {
                self.lastDetectionTime = CACurrentMediaTime()
                self.session.startRunning()
            }
            // 配置提交并启动后才能拿到照片输出连接，竖屏旋转放在这里设置。
            if let connection = self.photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            DispatchQueue.main.async { self.isRunning = self.session.isRunning }
        }
    }

    private func configureSession() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                  for: .video,
                                                  position: .back) else {
            publish(.unavailable, error: "当前设备没有可用的后置相机（模拟器不支持）。")
            return false
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            publish(.unavailable, error: "无法打开后置相机。")
            return false
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard session.canAddInput(input) else {
            publish(.unavailable, error: "无法添加相机输入。")
            return false
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            publish(.unavailable, error: "无法添加照片输出。")
            return false
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else {
            publish(.unavailable, error: "无法添加视频输出。")
            return false
        }
        session.addOutput(videoOutput)
        return true
    }

    // MARK: - Capture

    /// 拍摄一张照片；HEIC 可用时输出 HEIC 数据。completion 在主线程回调。
    func capturePhoto(completion: ((Data?) -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.isConfigured, self.session.isRunning,
                  self.beginCapture(completion: completion) else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.flashMode = .off
            settings.photoQualityPrioritization = .quality
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func beginCapture(completion: ((Data?) -> Void)?) -> Bool {
        captureLock.lock()
        defer { captureLock.unlock() }
        guard !isCaptureInFlight else { return false }
        isCaptureInFlight = true
        captureCompletion = completion
        return true
    }

    @discardableResult
    private func finishCapture() -> ((Data?) -> Void)? {
        captureLock.lock()
        defer { captureLock.unlock() }
        isCaptureInFlight = false
        let completion = captureCompletion
        captureCompletion = nil
        return completion
    }

    // MARK: - Detection

    /// 主线程调用：平滑检测框用于叠加层，并把原始检测喂给稳定判定。
    private func handleDetection(_ quad: Quad?, dt: Double, frameSize: CGSize) {
        if detectedFrameSize != frameSize { detectedFrameSize = frameSize }
        overlayQuad = smoother.update(quad, dt: dt)

        guard isAutoCaptureEnabled else { return }
        if stability.feed(quad, frameSize: frameSize) {
            stability.reset()
            capturePhoto()
        }
    }

    private func publish(_ state: AuthorizationState, error: String? = nil) {
        DispatchQueue.main.async {
            self.authorizationState = state
            self.errorMessage = error
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = CACurrentMediaTime()
        let dt = max(0, now - lastDetectionTime)

        // 传感器 buffer 是横向的；Vision 以 .right 旋转后，角点对应竖向画面。
        let frameSize = CGSize(width: CGFloat(CVPixelBufferGetHeight(pixelBuffer)),
                               height: CGFloat(CVPixelBufferGetWidth(pixelBuffer)))
        let accepted = detector.detect(in: pixelBuffer, orientation: .right) { [weak self] quad in
            self?.handleDetection(quad, dt: dt, frameSize: frameSize)
        }
        if accepted { lastDetectionTime = now }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let completion = finishCapture()
        guard error == nil, let data = photo.fileDataRepresentation() else {
            let message = error?.localizedDescription ?? "无法读取拍摄结果。"
            DispatchQueue.main.async {
                self.errorMessage = "拍摄失败：\(message)"
                completion?(nil)
            }
            return
        }
        DispatchQueue.main.async {
            self.lastCapturedData = data
            self.errorMessage = nil
            self.stability.reset()
            completion?(data)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        let completion = finishCapture()
        guard error != nil || completion != nil else { return }
        DispatchQueue.main.async {
            if let error {
                self.errorMessage = "拍摄失败：\(error.localizedDescription)"
            }
            completion?(nil)
        }
    }
}
