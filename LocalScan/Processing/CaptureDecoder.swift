import CoreGraphics
import CoreImage
import Foundation
import ImageIO

enum CaptureDecodeError: Error, Equatable {
    /// 数据不是可识别的图像，或 ImageIO 无法解码。
    case invalidData
    case decodeFailed
    /// EXIF 方向摆正失败。
    case orientationFailed
    /// 工作图缩放渲染失败。
    case renderFailed
}

/// 相机照片解码结果。`original` 与 `working` 都已按 EXIF 方向摆正。
struct DecodedCapture: @unchecked Sendable {
    let original: CGImage
    let working: CGImage
    let workingSize: CGSize
}

/// 把相机输出的 HEIC/JPEG `Data` 解码成摆正后的原图与工作图。
///
/// **坐标约定**：之后所有四边形都使用摆正后工作图的像素坐标
/// （左上原点、x 向右、y 向下）。原图可能带有 EXIF 方向信息，透视拉正之前
/// 必须先按 EXIF 摆正；本类型返回的两张图都已经完成这一步，调用方不应再自行旋转。
///
/// 工作图长边受 `ImageSizing.workingSize` 限制（默认不超过 2048 px），
/// 使用 CGContext 高质量缩放并保持宽高比；原图始终保留全分辨率。
final class CaptureDecoder: @unchecked Sendable {
    /// 复用的 CIContext：创建代价高且线程安全。
    private let context = CIContext()

    func decode(_ data: Data) throws -> DecodedCapture {
        let original = try decodeOriginal(data)
        let workingSize = ImageSizing.workingSize(
            for: CGSize(width: CGFloat(original.width),
                        height: CGFloat(original.height)))
        guard workingSize.width >= 1, workingSize.height >= 1 else {
            throw CaptureDecodeError.decodeFailed
        }

        let working = try scaled(original, to: workingSize)
        return DecodedCapture(
            original: original,
            working: working,
            workingSize: CGSize(width: CGFloat(working.width),
                                height: CGFloat(working.height)))
    }

    /// 只解码并摆正原图（手动重新裁剪时按需调用，避免每页常驻全分辨率位图）。
    func decodeOriginal(_ data: Data) throws -> CGImage {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw CaptureDecodeError.invalidData
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any]
        let orientationNumber = properties?[kCGImagePropertyOrientation] as? NSNumber
        let rawOrientation = orientationNumber?.uint32Value
            ?? CGImagePropertyOrientation.up.rawValue
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up

        guard let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CaptureDecodeError.decodeFailed
        }
        return try upright(raw, orientation: orientation)
    }

    /// 用 Core Image 应用 EXIF 方向；输出仍保持左上原点、y 向下的像素语义。
    private func upright(_ image: CGImage,
                         orientation: CGImagePropertyOrientation) throws -> CGImage {
        guard orientation != .up else { return image }
        let oriented = CIImage(cgImage: image).oriented(orientation)
        let extent = oriented.extent
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width >= 1, extent.height >= 1,
              let result = context.createCGImage(oriented, from: extent) else {
            throw CaptureDecodeError.orientationFailed
        }
        return result
    }

    /// CGContext 高质量缩放。目标尺寸取整后与返回的 `workingSize` 完全一致。
    private func scaled(_ image: CGImage, to size: CGSize) throws -> CGImage {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        if width == image.width, height == image.height {
            return image
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaptureDecodeError.renderFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0,
                                       width: CGFloat(width),
                                       height: CGFloat(height)))
        guard let result = context.makeImage() else {
            throw CaptureDecodeError.renderFailed
        }
        return result
    }
}
