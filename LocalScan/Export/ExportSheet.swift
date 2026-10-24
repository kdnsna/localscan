import CoreGraphics
import SwiftUI
import UIKit

private enum ExportKind: String, Identifiable {
    case images
    case pdf

    var id: String { rawValue }
}

private struct ExportItem: @unchecked Sendable {
    let image: CGImage
    let filter: PageFilter
}

private enum ExportFailure: Error {
    case filterFailed
}

/// 在后台按当前滤镜渲染页面，再交给 ImageExporter / PDFAssembler。
private enum ExportWriter {
    static func write(_ items: [ExportItem],
                      kind: ExportKind,
                      imageFormat: ImageExportFormat) throws -> [URL] {
        switch kind {
        case .images:
            return try items.enumerated().map { pair in
                guard let rendered = PageFilterRenderer.shared.apply(pair.element.filter,
                                                                     to: pair.element.image) else {
                    throw ExportFailure.filterFailed
                }
                return try ImageExporter.writeTemporaryFile(rendered,
                                                            format: imageFormat,
                                                            index: pair.offset + 1)
            }
        case .pdf:
            let url = try PDFAssembler.writeTemporaryFile(pageCount: items.count) { index in
                let item = items[index]
                guard let rendered = PageFilterRenderer.shared.apply(item.filter,
                                                                     to: item.image) else {
                    throw ExportFailure.filterFailed
                }
                return rendered
            }
            return [url]
        }
    }
}

/// 系统分享面板。包含“存储到‘文件’”；不发起任何网络请求。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// 分享结束（完成或取消）时调用一次。
    var onComplete: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items,
                                                  applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController,
                                context: Context) {}
}

/// 导出选项：图片（JPEG/HEIC）或多页 PDF，然后弹出系统分享面板。
@MainActor
struct ExportSheet: View {
    @ObservedObject var session: ScanSession

    @Environment(\.dismiss) private var dismiss
    @State private var kind: ExportKind = .images
    @State private var imageFormat: ImageExportFormat = .jpeg
    @State private var isExporting = false
    @State private var shareURLs: [URL] = []
    @State private var showShareSheet = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("格式") {
                    Picker("类型", selection: $kind) {
                        Text("图片").tag(ExportKind.images)
                        Text("PDF").tag(ExportKind.pdf)
                    }
                    .pickerStyle(.segmented)

                    if kind == .images {
                        Picker("图片格式", selection: $imageFormat) {
                            ForEach(ImageExportFormat.allCases) { format in
                                Text(format.title).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    Button(isExporting ? "正在导出…" : "分享 \(session.pageCount) 页") {
                        startExport()
                    }
                    .disabled(!canExport)
                    if let exportStatusMessage {
                        Text(exportStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet, onDismiss: cleanUpShared) {
                ShareSheet(items: shareURLs, onComplete: cleanUpShared)
            }
        }
    }

    private var canExport: Bool {
        !isExporting && !session.pages.isEmpty
            && session.pages.allSatisfy { $0.correctedImage != nil }
    }

    private var exportStatusMessage: String? {
        if session.pages.contains(where: { $0.state == .failed }) {
            return "有页面处理失败，请重拍后再导出。"
        }
        if session.pages.contains(where: { $0.state == .processing }) {
            return "页面仍在处理，完成后即可导出。"
        }
        return nil
    }

    private func startExport() {
        guard !session.pages.isEmpty else {
            errorMessage = "没有可导出的页面。"
            return
        }
        let items: [ExportItem] = session.pages.compactMap { page in
            guard let image = page.correctedImage else { return nil }
            return ExportItem(image: image, filter: page.filter)
        }
        guard items.count == session.pages.count else {
            errorMessage = session.pages.contains(where: { $0.state == .failed })
                ? "有页面处理失败，请重拍后再导出。"
                : "还有页面正在处理，请稍后再导出。"
            return
        }

        let kind = self.kind
        let imageFormat = self.imageFormat
        // 新导出前清掉旧文件（同名文件也会被覆盖）。
        cleanUpShared()
        ExportFileStore.removeAll()
        isExporting = true
        errorMessage = nil
        Task {
            do {
                let urls = try await Task.detached(priority: .userInitiated) {
                    try ExportWriter.write(items, kind: kind, imageFormat: imageFormat)
                }.value
                isExporting = false
                shareURLs = urls
                showShareSheet = true
            } catch {
                isExporting = false
                errorMessage = "导出失败，请重试。"
            }
        }
    }

    /// 删除本次导出的临时文件；可重复调用。
    private func cleanUpShared() {
        ExportFileStore.remove(shareURLs)
        shareURLs = []
    }
}
