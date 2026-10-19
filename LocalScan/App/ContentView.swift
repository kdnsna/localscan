import SwiftUI

/// M0 占位界面。M1 会替换成相机预览 + 实时找边。
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 56))
            Text("LocalScan")
                .font(.title.bold())
            Text("本地优先的文档扫描（开发中）")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
