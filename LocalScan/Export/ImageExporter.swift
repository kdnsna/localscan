import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 可导出的图片格式。JPEG/HEIC 都使用 ImageIO 的有损质量参数。
enum ImageExportFormat: String, CaseIterable, Identifiable {
    case jpeg
    case heic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .heic: return .heic
        }
    }
}

typealias ExportFormat = ImageExportFormat
typealias ImageFormat = ImageExportFormat

enum ImageExportError: Error, Equatable {
    case invalidImage
    /// 当前环境没有对应的 ImageIO 编码器（HEIC 在部分模拟器上不可用）。
    case destinationUnavailable
    case encodingFailed
    case writeFailed
}

/// 把拉正后的 CGImage 编码成 JPEG/HEIC，并写入临时目录。
/// 不读写相册、不上传，所有编码都在本机 ImageIO 完成。
enum ImageExporter {
    typealias Format = ImageExportFormat

    static let qualityRange = ScanDefaults.jpegQualityRange
    static let defaultQuality = ScanDefaults.jpegQuality

    /// 质量限制在 0.80...0.88；非有限值回退到默认 0.85。
    static func clampedQuality(_ quality: Double) -> Double {
        guard quality.isFinite else { return defaultQuality }
        return min(max(quality, qualityRange.lowerBound), qualityRange.upperBound)
    }

    static func encode(_ image: CGImage,
                       as format: Format,
                       quality: Double = defaultQuality) throws -> Data {
        guard image.width > 0, image.height > 0 else {
            throw ImageExportError.invalidImage
        }
        guard let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                data, format.utType.identifier as CFString, 1, nil) else {
            throw ImageExportError.destinationUnavailable
        }

        let properties: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String:
                clampedQuality(quality),
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination), (data as Data).count > 0 else {
            throw ImageExportError.encodingFailed
        }
        return data as Data
    }

    static func encode(_ image: CGImage,
                       format: Format,
                       quality: Double = defaultQuality) throws -> Data {
        try encode(image, as: format, quality: quality)
    }

    /// 临时文件名形如 `Scan-001.jpg`；索引从 1 开始。
    static func temporaryURL(for format: Format, index: Int = 1) -> URL {
        let number = max(1, index)
        let name = String(format: "Scan-%03d", number) + "." + format.fileExtension
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    @discardableResult
    static func writeTemporaryFile(_ image: CGImage,
                                   format: Format,
                                   index: Int = 1,
                                   quality: Double = defaultQuality) throws -> URL {
        let data = try encode(image, as: format, quality: quality)
        let url = temporaryURL(for: format, index: index)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ImageExportError.writeFailed
        }
        return url
    }

    @discardableResult
    static func writeTemporaryFile(for image: CGImage,
                                   format: Format,
                                   index: Int = 1,
                                   quality: Double = defaultQuality) throws -> URL {
        try writeTemporaryFile(image, format: format, index: index, quality: quality)
    }
}
