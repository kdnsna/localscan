import Combine
import CoreGraphics
import Foundation

private struct PreparedCapture: @unchecked Sendable {
    let decoded: DecodedCapture
    let quad: Quad
}

private struct DecodedOriginal: @unchecked Sendable {
    let image: CGImage
}

/// 一次扫描会话：持有文档模型与图片，负责后台解码/找边/透视拉正。
/// 所有页面更新都在主线程；解码和 Core Image 工作不阻塞相机。
@MainActor
final class ScanSession: ObservableObject {
    @Published private(set) var document = ScanDocument()
    /// 非 nil 时，下一张照片替换该页（从页面详情点“重拍”后回到相机）。
    @Published private(set) var pendingRetakePageID: UUID?
    @Published private(set) var errorMessage: String?

    let images = PageImageStore()
    private let decoder = CaptureDecoder()
    private let queue = ProcessingQueue()
    /// 丢弃重新裁剪/重拍后到达的旧处理结果。
    private var tokens: [UUID: UUID] = [:]

    var pageCount: Int { document.pages.count }
    var pages: [ScanPage] { document.pages }
    var latestPage: ScanPage? { document.pages.last }

    func page(id: UUID) -> ScanPage? { document.page(id: id) }

    func add(_ page: ScanPage) {
        document.append(page)
    }

    func replace(id: UUID, with page: ScanPage) {
        document.replace(id: id, with: page)
    }

    func beginRetake(pageID: UUID) {
        guard document.page(id: pageID) != nil else { return }
        pendingRetakePageID = pageID
    }

    func cancelRetake() {
        pendingRetakePageID = nil
    }

    func movePages(fromOffsets: IndexSet, toOffset: Int) {
        document.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func movePage(id: UUID, before targetID: UUID) {
        document.movePage(id: id, before: targetID)
    }

    func deletePages(atOffsets offsets: IndexSet) {
        let ids = offsets.compactMap { index -> UUID? in
            guard document.pages.indices.contains(index) else { return nil }
            return document.pages[index].id
        }
        for id in ids {
            document.remove(id: id)
            images.remove(id)
            tokens[id] = nil
            if pendingRetakePageID == id {
                pendingRetakePageID = nil
            }
        }
    }

    func delete(id: UUID) {
        document.remove(id: id)
        images.remove(id)
        tokens[id] = nil
        if pendingRetakePageID == id { pendingRetakePageID = nil }
    }

    func setFilter(_ filter: PageFilter, for id: UUID) {
        document.updateFilter(id: id, filter: filter)
    }

    func clearError() {
        errorMessage = nil
    }

    /// 手动裁剪确认后重新拉正；不重新跑角点细化。
    func updateQuad(pageID: UUID, quad: Quad) {
        guard let page = document.page(id: pageID) else { return }
        document.updateQuad(id: pageID, quad: quad)
        document.updateImage(id: pageID, image: nil)
        document.updateState(id: pageID, state: .processing)
        let token = UUID()
        tokens[pageID] = token
        let data = page.originalData
        let workingSize = page.workingSize
        let decoder = self.decoder
        let queue = self.queue
        Task { [weak self] in
            do {
                let original = try await Task.detached(priority: .userInitiated) {
                    DecodedOriginal(image: try decoder.decodeOriginal(data))
                }.value
                let image = try await queue.correct(original: original.image,
                                                    quad: quad,
                                                    workingSize: workingSize)
                guard let self, self.tokens[pageID] == token,
                      self.document.page(id: pageID) != nil else { return }
                self.tokens[pageID] = nil
                self.document.updateImage(id: pageID, image: image)
                self.document.updateState(id: pageID, state: .done)
            } catch {
                guard let self, self.tokens[pageID] == token else { return }
                self.tokens[pageID] = nil
                self.document.updateState(id: pageID, state: .failed)
                self.errorMessage = "重新裁剪失败，请重试。"
            }
        }
    }

    /// 相机照片入口（自动/手动相同）。解码 -> EXIF 摆正 -> 工作图找边 -> 入队拉正。
    func ingest(capturedData: Data) {
        let retakeID = pendingRetakePageID
        pendingRetakePageID = nil
        errorMessage = nil

        let decoder = self.decoder
        let queue = self.queue
        Task { [weak self] in
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    let decoded = try decoder.decode(capturedData)
                    let quad = DocumentQuadDetector.detect(in: decoded.working)
                    return PreparedCapture(decoded: decoded, quad: quad)
                }.value
                guard let self else { return }

                let decoded = prepared.decoded
                let quad = prepared.quad
                let targetID = retakeID.flatMap {
                    self.document.page(id: $0) != nil ? $0 : nil
                } ?? UUID()
                let filter = retakeID.flatMap {
                    self.document.page(id: $0)?.filter
                } ?? .original
                let page = ScanPage(id: targetID,
                                    originalData: capturedData,
                                    quad: quad,
                                    workingSize: decoded.workingSize,
                                    filter: filter,
                                    state: .processing)

                self.images.store(working: decoded.working, for: targetID)
                if retakeID == targetID {
                    self.document.replace(id: targetID, with: page)
                } else {
                    self.document.append(page)
                }

                let token = UUID()
                self.tokens[targetID] = token
                do {
                    let result = try await queue.process(original: decoded.original,
                                                         working: decoded.working,
                                                         quad: quad,
                                                         workingSize: decoded.workingSize)
                    guard self.tokens[targetID] == token,
                          self.document.page(id: targetID) != nil else { return }
                    self.tokens[targetID] = nil
                    self.document.updateImage(id: targetID, image: result.image)
                    self.document.updateQuad(id: targetID, quad: result.quad)
                    self.document.updateState(id: targetID, state: .done)
                } catch {
                    guard self.tokens[targetID] == token else { return }
                    self.tokens[targetID] = nil
                    self.document.updateState(id: targetID, state: .failed)
                    self.errorMessage = "这一页处理失败，请重试。"
                }
            } catch {
                guard let self else { return }
                self.errorMessage = "无法解码照片，请重新拍摄。"
            }
        }
    }
}
