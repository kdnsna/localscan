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
    @Published private(set) var isCapturing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastCapturedData: Data?
    @Published private(set) var overlayQuad: Quad?
    @Published private(set) var detectedFrameSize: CGSize = .zero
    @Published private(set) var isInterrupted = false
    @Published private(set) var interruptionHint: String?
    @Published var isAutoCaptureEnabled = true {
        didSet {
            guard isAutoCaptureEnabled != oldValue else { return }
            // 切换自动拍摄属于手动操作：重新开始累计，关闭时门控也绝不喂帧。
            autoCaptureGate.isEnabled = isAutoCaptureEnabled
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
    /// 仅在主线程访问（检测回调、开关和会话状态发布都在主线程）。
    private var autoCaptureGate = AutoCaptureGate()
    /// 最近一帧原始检测框（预览帧像素坐标，仅主线程读写），手动拍摄后用作锁存基准。
    private var lastDetectedQuad: Quad?
    private var isConfigured = false
    private var isRequestingAuthorization = false
    private var isCaptureInFlight = false
    private var captureCompletion: ((Data?) -> Void)?
    /// 仅在 videoQueue 上读写，避免视频帧回调和会话队列之间的数据竞争。
    private var lastDetectionTime: CFTimeInterval?
    private var notificationTokens: [NSObjectProtocol] = []

    override init() {
        super.init()
        observeSessionNotifications()
    }

    deinit {
        let center = NotificationCenter.default
        for token in notificationTokens {
            center.removeObserver(token)
        }
    }

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
                self.isInterrupted = false
                self.interruptionHint = nil
                self.overlayQuad = nil
                self.smoother = QuadSmoother()
                self.autoCaptureGate.reset()
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
            self.startSessionIfNeeded()
            // 配置提交并启动后才能拿到照片输出连接，竖屏旋转放在这里设置。
            if let connection = self.photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            let isRunning = self.session.isRunning
            DispatchQueue.main.async {
                self.isRunning = isRunning
                if isRunning {
                    self.isInterrupted = false
                    self.interruptionHint = nil
                }
            }
        }
    }

    /// 仅在 sessionQueue 上调用。
    private func startSessionIfNeeded() {
        guard !session.isRunning else { return }
        // lastDetectionTime 只属于 videoQueue，重置任务排在启动帧之前。
        videoQueue.async { [weak self] in
            self?.lastDetectionTime = CACurrentMediaTime()
        }
        session.startRunning()
    }

    /// 中断结束或媒体服务重置后恢复会话；仅在 sessionQueue 上调用。
    private func restartSessionAfterInterruption() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured else { return }
            self.startSessionIfNeeded()
            let isRunning = self.session.isRunning
            DispatchQueue.main.async {
                self.isRunning = isRunning
                if isRunning {
                    self.isInterrupted = false
                    self.interruptionHint = nil
                }
            }
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

    /// 手动拍摄一张照片；HEIC 可用时输出 HEIC 数据。completion 在主线程回调。
    /// 手动拍摄成功后，以当前检测框为基准锁存自动拍摄：手机不动时不会再自动拍同一页，
    /// 只有出现不稳定或换页后才重新计数。
    func capturePhoto(completion: ((Data?) -> Void)? = nil) {
        requestCapture { [weak self] data in
            if let self {
                self.autoCaptureGate.handleManualCaptureResult(
                    succeeded: data != nil,
                    reference: self.lastDetectedQuad)
            }
            completion?(data)
        }
    }

    private func requestCapture(completion: ((Data?) -> Void)? = nil) {
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
        DispatchQueue.main.async { self.isCapturing = true }
        return true
    }

    @discardableResult
    private func finishCapture() -> ((Data?) -> Void)? {
        captureLock.lock()
        defer { captureLock.unlock() }
        isCaptureInFlight = false
        let completion = captureCompletion
        captureCompletion = nil
        DispatchQueue.main.async { self.isCapturing = false }
        return completion
    }

    // MARK: - Detection

    /// 主线程调用：平滑检测框用于叠加层，并把原始检测喂给稳定判定。
    private func handleDetection(_ quad: Quad?, dt: Double, frameSize: CGSize) {
        if detectedFrameSize != frameSize { detectedFrameSize = frameSize }
        // 叠加层使用 Vision 的归一化坐标；稳定判定与拍摄快照统一用帧像素坐标。
        overlayQuad = smoother.update(quad, dt: dt)
        let pixelQuad = quad?.scaled(by: frameSize.width, frameSize.height)
        lastDetectedQuad = pixelQuad

        if autoCaptureGate.feed(pixelQuad, frameSize: frameSize) {
            // 触发后由 StabilityDetector 保持锁存，不能在这里 reset，否则会重复拍摄。
            requestCapture()
        }
    }

    // MARK: - Session Notifications

    private func observeSessionNotifications() {
        let center = NotificationCenter.default
        let session = self.session
        notificationTokens = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                               object: session,
                               queue: nil) { [weak self] notification in
                self?.handleSessionWasInterrupted(notification)
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
                               object: session,
                               queue: nil) { [weak self] _ in
                self?.handleSessionInterruptionEnded()
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                               object: session,
                               queue: nil) { [weak self] notification in
                self?.handleSessionRuntimeError(notification)
            }
        ]
    }

    private func handleSessionWasInterrupted(_ notification: Notification) {
        let rawReason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey]
            as? NSNumber)?.intValue
        let reason = rawReason.flatMap {
            AVCaptureSession.InterruptionReason(rawValue: $0)
        }
        publishInterruption(hint: Self.hint(for: reason))
    }

    private func handleSessionInterruptionEnded() {
        DispatchQueue.main.async { [weak self] in
            // 中断结束后同样锁存：手机没动时不重复拍同一页；没有基准框时解锁重新计数。
            guard let self else { return }
            self.autoCaptureGate.handleInterruptionEnded(
                lastDetectedQuad: self.lastDetectedQuad)
        }
        restartSessionAfterInterruption()
    }

    private func handleSessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        let shouldRestart = error?.code == .mediaServicesWereReset
        let hint = shouldRestart
            ? "相机媒体服务已重置，正在尝试恢复。"
            : "相机被系统中断（来电、分屏或相机被占用）。"
        publishInterruption(hint: hint)
        if shouldRestart {
            restartSessionAfterInterruption()
        }
    }

    private func publishInterruption(hint: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isInterrupted = true
            self.interruptionHint = hint
            self.isRunning = self.session.isRunning
            // 中断期间没有新帧，清除旧的稳定锁存，恢复后重新累计。
            self.autoCaptureGate.reset()
        }
    }

    private static func hint(for reason: AVCaptureSession.InterruptionReason?) -> String {
        guard let reason else {
            return "相机被系统中断（如来电）。"
        }
        switch reason {
        case .videoDeviceInUseByAnotherClient:
            return "相机被其他 App 占用。"
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            return "分屏或悬浮窗口下相机不可用。"
        case .videoDeviceNotAvailableInBackground:
            return "相机在后台不可用。"
        case .audioDeviceInUseByAnotherClient:
            return "麦克风被其他 App 占用。"
        case .videoDeviceNotAvailableDueToSystemPressure:
            return "系统资源紧张，相机暂时不可用。"
        @unknown default:
            return "相机被系统中断（如来电、分屏或相机被占用）。"
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
        let dt: Double
        if let lastDetectionTime {
            dt = max(0, now - lastDetectionTime)
        } else {
            dt = 0
        }

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
