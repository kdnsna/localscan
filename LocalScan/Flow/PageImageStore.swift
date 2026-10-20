import CoreGraphics
import Foundation

/// App 层按页 id 保存工作图；原图以压缩 Data 保存在 `ScanPage` 里。
/// 重新裁剪时才解码全分辨率原图，避免每页常驻一张 12 MP 位图。
@MainActor
final class PageImageStore {
    private var workings: [UUID: CGImage] = [:]

    func store(working: CGImage, for id: UUID) {
        workings[id] = working
    }

    func remove(_ id: UUID) {
        workings[id] = nil
    }

    func workingImage(for id: UUID) -> CGImage? {
        workings[id]
    }
}
