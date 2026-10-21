import CoreGraphics
import Foundation

enum PageFilter: String, CaseIterable, Identifiable {
    /// 保真：只做几何，不改变任何像素。
    case original
    /// 经典增强：光照归一化 + 温和对比度 + 轻锐化（确定性，不生成内容）。
    case enhance
    case grayscale
    /// 灰度 + 固定阈值。
    case blackWhite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "原图"
        case .enhance: return "增强"
        case .grayscale: return "灰度"
        case .blackWhite: return "黑白"
        }
    }
}

enum PageState: Equatable {
    case processing
    case done
    case failed
}

/// 一页扫描结果。原图数据与拉正结果都只保存在内存里。
struct ScanPage: Identifiable {
    let id: UUID
    /// 相机输出的 HEIC/JPEG 原始数据（EXIF 方向尚未应用）。
    let originalData: Data
    /// 工作图坐标下的四边形（左上原点，y 向下）。
    var quad: Quad
    /// Vision 的原始检测框（失败时为 6% 内缩框），供手动裁剪“重置为检测框”。
    var detectedQuad: Quad
    var workingSize: CGSize
    var filter: PageFilter
    /// 原图全分辨率透视拉正结果；处理完成前为 nil。
    var correctedImage: CGImage?
    var state: PageState

    init(id: UUID = UUID(),
         originalData: Data = Data(),
         quad: Quad,
         detectedQuad: Quad? = nil,
         workingSize: CGSize,
         filter: PageFilter = .original,
         correctedImage: CGImage? = nil,
         state: PageState = .processing) {
        self.id = id
        self.originalData = originalData
        self.quad = quad
        self.detectedQuad = detectedQuad ?? quad
        self.workingSize = workingSize
        self.filter = filter
        self.correctedImage = correctedImage
        self.state = state
    }
}

/// 多页文档的纯值类型模型。越界索引或不存在的 id 一律安全忽略。
struct ScanDocument {
    private(set) var pages: [ScanPage]

    init(pages: [ScanPage] = []) {
        self.pages = pages
    }

    mutating func append(_ page: ScanPage) {
        pages.append(page)
    }

    @discardableResult
    mutating func remove(id: UUID) -> ScanPage? {
        guard let index = pages.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return pages.remove(at: index)
    }

    /// 与 SwiftUI `move(fromOffsets:toOffset:)` 语义一致：`destination` 是移动前数组里的插入位置。
    /// 越界的来源索引忽略，目标位置夹到 `0...pages.count`。
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.sorted().filter { pages.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let clamped = min(max(0, destination), pages.count)
        let moving = valid.map { pages[$0] }
        let insertAt = clamped - valid.filter { $0 < clamped }.count
        var remaining = pages
        for index in valid.reversed() {
            remaining.remove(at: index)
        }
        remaining.insert(contentsOf: moving, at: insertAt)
        pages = remaining
    }

    /// 把 `id` 拖到 `targetID` 之前（页面条拖拽排序）。
    mutating func movePage(id: UUID, before targetID: UUID) {
        guard let from = pages.firstIndex(where: { $0.id == id }),
              let target = pages.firstIndex(where: { $0.id == targetID }),
              from != target else { return }
        let to = target > from ? target - 1 : target
        pages.insert(pages.remove(at: from), at: min(max(0, to), pages.count))
    }

    /// 重拍：保留原 id 与原位置，只替换内容。
    mutating func replace(id: UUID, with page: ScanPage) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index] = ScanPage(id: id,
                                originalData: page.originalData,
                                quad: page.quad,
                                detectedQuad: page.detectedQuad,
                                workingSize: page.workingSize,
                                filter: page.filter,
                                correctedImage: page.correctedImage,
                                state: page.state)
    }

    mutating func updateQuad(id: UUID, quad: Quad) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].quad = quad
    }

    mutating func updateFilter(id: UUID, filter: PageFilter) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].filter = filter
    }

    mutating func updateImage(id: UUID, image: CGImage?) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].correctedImage = image
    }

    mutating func updateState(id: UUID, state: PageState) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].state = state
    }

    func page(id: UUID) -> ScanPage? {
        pages.first(where: { $0.id == id })
    }
}
