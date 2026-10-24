import CoreGraphics
import Foundation
import os
import UIKit

enum PDFAssemblerError: Error, Equatable {
    case noPages
    case invalidPageSize
    case imageEncodingFailed
    case imageDecodingFailed
    case writeFailed
}

/// 多页 PDF：每页把图片按 0.85 质量编码成 JPEG 后绘制到等比例页面。
/// 页面尺寸由像素尺寸与目标 DPI 计算：points = pixels / dpi * 72。
enum PDFAssembler {
    static let defaultDPI = ScanDefaults.pdfDPI
    static let dpiRange = ScanDefaults.pdfDPIRange

    private static let log = OSLog(subsystem: "com.kdnsna.localscan",
                                   category: .pointsOfInterest)

    /// DPI 限制在 200...300；非有限值回退到默认 200。
    static func clampedDPI(_ dpi: CGFloat) -> CGFloat {
        guard dpi.isFinite else { return defaultDPI }
        return min(max(dpi, dpiRange.lowerBound), dpiRange.upperBound)
    }

    /// 纯函数：像素尺寸 -> PDF 页面 points。无效尺寸返回 `.zero`。
    static func pageSize(forPixelSize pixels: CGSize,
                         dpi: CGFloat = defaultDPI) -> CGSize {
        guard pixels.width.isFinite, pixels.height.isFinite,
              pixels.width > 0, pixels.height > 0 else { return .zero }
        let scale = 72 / clampedDPI(dpi)
        return CGSize(width: pixels.width * scale,
                      height: pixels.height * scale)
    }

    /// 返回内存中的 PDF 数据。每页先编码成 JPEG（质量默认 0.85）再绘制。
    static func makePDF(from images: [CGImage],
                        dpi: CGFloat = defaultDPI,
                        quality: Double = ScanDefaults.jpegQuality) throws -> Data {
        guard !images.isEmpty else { throw PDFAssemblerError.noPages }

        os_signpost(.begin, log: log, name: "PDFExport")
        defer { os_signpost(.end, log: log, name: "PDFExport") }

        let quality = ImageExporter.clampedQuality(quality)
        let pages: [(image: UIImage, size: CGSize)] = try images.map { image in
            let jpeg: Data
            do {
                jpeg = try ImageExporter.encode(image, as: .jpeg, quality: quality)
            } catch {
                throw PDFAssemblerError.imageEncodingFailed
            }
            guard let uiImage = UIImage(data: jpeg) else {
                throw PDFAssemblerError.imageDecodingFailed
            }
            let size = pageSize(forPixelSize: CGSize(width: image.width,
                                                     height: image.height),
                                dpi: dpi)
            guard size.width > 0, size.height > 0 else {
                throw PDFAssemblerError.invalidPageSize
            }
            return (image: uiImage, size: size)
        }

        guard let first = pages.first else {
            throw PDFAssemblerError.noPages
        }
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "LocalScan",
            kCGPDFContextCreator as String: "LocalScan",
        ]
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: first.size),
            format: format)
        let data = renderer.pdfData { context in
            for page in pages {
                let bounds = CGRect(origin: .zero, size: page.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                page.image.draw(in: bounds)
            }
        }
        return data
    }

    /// 逐页写入临时 PDF，避免同时持有全部页面位图和完整 PDF Data。
    static func writeTemporaryFile(pageCount: Int,
                                   pageAt: (Int) throws -> CGImage,
                                   dpi: CGFloat = defaultDPI,
                                   quality: Double = ScanDefaults.jpegQuality,
                                   index: Int = 1) throws -> URL {
        guard pageCount > 0 else { throw PDFAssemblerError.noPages }
        let url = temporaryURL(index: index)
        let quality = ImageExporter.clampedQuality(quality)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "LocalScan",
            kCGPDFContextCreator as String: "LocalScan",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: .zero, format: format)
        var pageError: Error?

        os_signpost(.begin, log: log, name: "PDFExport")
        defer { os_signpost(.end, log: log, name: "PDFExport") }
        do {
            try renderer.writePDF(to: url) { context in
                for pageIndex in 0..<pageCount {
                    autoreleasepool {
                        do {
                            let image = try pageAt(pageIndex)
                            let size = pageSize(forPixelSize: CGSize(width: image.width,
                                                                     height: image.height),
                                                dpi: dpi)
                            guard size.width > 0, size.height > 0 else {
                                throw PDFAssemblerError.invalidPageSize
                            }
                            let jpeg = try ImageExporter.encode(image, as: .jpeg,
                                                                quality: quality)
                            guard let pageImage = UIImage(data: jpeg) else {
                                throw PDFAssemblerError.imageDecodingFailed
                            }
                            let bounds = CGRect(origin: .zero, size: size)
                            context.beginPage(withBounds: bounds, pageInfo: [:])
                            pageImage.draw(in: bounds)
                        } catch {
                            pageError = error
                            return
                        }
                    }
                    if pageError != nil { return }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw PDFAssemblerError.writeFailed
        }
        if let pageError {
            try? FileManager.default.removeItem(at: url)
            throw pageError
        }
        return url
    }

    /// 临时 PDF 文件名形如 `Scan-001.pdf`。
    static func temporaryURL(index: Int = 1) -> URL {
        let name = String(format: "Scan-%03d.pdf", max(1, index))
        return ExportFileStore.url(named: name)
    }

    @discardableResult
    static func writeTemporaryFile(from images: [CGImage],
                                   dpi: CGFloat = defaultDPI,
                                   quality: Double = ScanDefaults.jpegQuality,
                                   index: Int = 1) throws -> URL {
        let data = try makePDF(from: images, dpi: dpi, quality: quality)
        let url = temporaryURL(index: index)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw PDFAssemblerError.writeFailed
        }
        return url
    }
}
