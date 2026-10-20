import AVFoundation
import SwiftUI
import UIKit

/// aspect-fill 下把归一化坐标（左上原点）映射到预览视图坐标。纯函数，单测覆盖。
enum CameraPreviewGeometry {
    static func viewPoint(fromNormalized point: CGPoint,
                          frameSize: CGSize,
                          viewSize: CGSize) -> CGPoint {
        guard frameSize.width > 0, frameSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let scale = max(viewSize.width / frameSize.width,
                        viewSize.height / frameSize.height)
        let rendered = CGSize(width: frameSize.width * scale,
                              height: frameSize.height * scale)
        return CGPoint(
            x: (viewSize.width - rendered.width) / 2 + point.x * rendered.width,
            y: (viewSize.height - rendered.height) / 2 + point.y * rendered.height
        )
    }

    static func viewQuad(from quad: Quad,
                         frameSize: CGSize,
                         viewSize: CGSize) -> Quad {
        func map(_ point: CGPoint) -> CGPoint {
            viewPoint(fromNormalized: point, frameSize: frameSize, viewSize: viewSize)
        }
        return Quad(topLeft: map(quad.topLeft), topRight: map(quad.topRight),
                    bottomRight: map(quad.bottomRight), bottomLeft: map(quad.bottomLeft))
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyOrientation()
    }

    func applyOrientation() {
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(90) else { return }
        connection.videoRotationAngle = 90
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        view.applyOrientation()
        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
        view.applyOrientation()
    }
}

struct QuadOverlay: Shape {
    var quad: Quad?
    var frameSize: CGSize

    func path(in rect: CGRect) -> Path {
        guard let quad, frameSize.width > 0, frameSize.height > 0 else { return Path() }
        let mapped = CameraPreviewGeometry.viewQuad(from: quad,
                                                    frameSize: frameSize,
                                                    viewSize: rect.size)
        var path = Path()
        path.move(to: mapped.topLeft)
        path.addLine(to: mapped.topRight)
        path.addLine(to: mapped.bottomRight)
        path.addLine(to: mapped.bottomLeft)
        path.closeSubpath()
        return path
    }
}

struct CameraView: View {
    @ObservedObject var controller: CameraController
    /// 页面条出现时抬高底部控制区，避免遮住快门。
    var bottomInset: CGFloat = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                ZStack {
                    CameraPreview(session: controller.session)
                    QuadOverlay(quad: controller.overlayQuad,
                                frameSize: controller.detectedFrameSize)
                        .stroke(Color.green,
                                style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                        .shadow(color: .green.opacity(0.6), radius: 4)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()

            VStack(spacing: 16) {
                hint
                Spacer()
                controls
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16 + bottomInset)

            if let message = permissionMessage {
                permissionOverlay(message)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.start() }
            if phase == .background { controller.stop() }
        }
    }

    private var hint: some View {
        Text(controller.overlayQuad == nil ? "对准文档" : "保持稳定")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.black.opacity(0.45), in: Capsule())
    }

    private var controls: some View {
        HStack {
            Toggle(isOn: $controller.isAutoCaptureEnabled) {
                Text("自动")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .tint(.green)
            .frame(width: 104)

            Spacer()

            Button {
                controller.capturePhoto()
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4)
                    Circle().fill(.white).padding(7)
                }
                .frame(width: 74, height: 74)
            }
            .buttonStyle(.plain)
            .disabled(!canCapture)
            .opacity(canCapture ? 1 : 0.4)
            .accessibilityLabel("快门")

            Spacer()
            Color.clear.frame(width: 104, height: 1)
        }
    }

    private var canCapture: Bool {
        controller.authorizationState == .authorized && controller.isRunning
    }

    private var permissionMessage: String? {
        switch controller.authorizationState {
        case .denied:
            return "相机权限被拒绝，请在设置中允许 LocalScan 使用相机。"
        case .restricted:
            return "相机受系统限制，无法使用。"
        case .unavailable:
            return controller.errorMessage ?? "当前设备没有可用的相机。"
        case .unknown, .authorized:
            return nil
        }
    }

    private func permissionOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 42))
            Text(message)
                .multilineTextAlignment(.center)
            if controller.authorizationState == .denied {
                Button("打开设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
    }
}
