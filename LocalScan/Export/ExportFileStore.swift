import Foundation

/// 导出临时文件统一放在 tmp/LocalScanExports/ 下，便于整目录清理。
/// - 分享面板结束（完成或取消）时删除本次导出的文件；
/// - 启动时和每次导出前清掉上次残留的文件（例如分享中途被杀进程）。
enum ExportFileStore {
    static var directory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalScanExports", isDirectory: true)
    }

    static func url(named name: String) -> URL {
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }

    /// 只删除位于导出目录内的文件，避免误删其他位置。
    static func remove(_ urls: [URL]) {
        let root = directory.standardizedFileURL.path
        for url in urls where url.standardizedFileURL.deletingLastPathComponent().path == root {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func removeAll() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directory,
                                                         includingPropertiesForKeys: nil)
        else { return }
        for url in contents {
            try? fm.removeItem(at: url)
        }
    }
}
