import Foundation
import SwiftUI

/// M1 拍摄流：相机 + 实时找边 + 页面条；拍摄结果只进入内存会话，不落盘、不上传。
@MainActor
struct ContentView: View {
    @StateObject private var camera = CameraController()
    @StateObject private var session = ScanSession()
    @State private var selectedPageID: UUID?

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraView(controller: camera,
                       bottomInset: session.pageCount == 0 ? 0 : 96)

            if session.pendingRetakePageID != nil {
                HStack(spacing: 12) {
                    Text("重拍模式：下一张将替换所选页面")
                        .font(.footnote.weight(.semibold))
                    Button("取消") { session.cancelRetake() }
                        .font(.footnote.weight(.semibold))
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 88)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .accessibilityElement(children: .contain)
            }

            if session.pageCount > 0 {
                PageStrip(session: session) { selectedPageID = $0 }
            }
        }
        .onChange(of: camera.lastCapturedData) { _, data in
            guard let data else { return }
            session.ingest(capturedData: data)
        }
        .sheet(isPresented: detailPresented) {
            if let id = selectedPageID {
                PageDetailView(session: session, pageID: id)
            }
        }
        .alert("处理失败", isPresented: errorPresented) {
            Button("好") { session.clearError() }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private var detailPresented: Binding<Bool> {
        Binding(get: { selectedPageID != nil },
                set: { if !$0 { selectedPageID = nil } })
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { session.errorMessage != nil },
                set: { if !$0 { session.clearError() } })
    }
}

#Preview {
    ContentView()
}
