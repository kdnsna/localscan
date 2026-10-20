import SwiftUI

@main
struct LocalScanApp: App {
    init() {
        // 清理上次运行残留的导出临时文件。
        ExportFileStore.removeAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
