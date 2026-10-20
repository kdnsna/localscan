import SwiftUI
import UIKit

/// M1：相机预览 + 实时找边 + 自动/手动拍摄；右上角显示最近一次拍摄缩略图。
struct ContentView: View {
    @StateObject private var camera = CameraController()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CameraView(controller: camera)

            if let data = camera.lastCapturedData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white, lineWidth: 2)
                    }
                    .shadow(radius: 4)
                    .padding(.top, 56)
                    .padding(.trailing, 16)
                    .accessibilityLabel("最近一次拍摄")
            }
        }
    }
}

#Preview {
    ContentView()
}
