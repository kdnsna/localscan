import CoreGraphics
import CoreImage
import Foundation

enum PerspectiveCorrectionError: Error, Equatable {
    /// 原图尺寸无效或 Core Image 无法渲染。
    case invalidImage
    /// 四边形非有限、非凸或面积过小。
    case invalidQuad
    case filterUnavailable
    case outputTooLarge
    case renderFailed
}

/// 全分辨率透视拉正。只做几何重采样，不叠加任何增强滤镜。
///
/// **输入约定**：`image` 必须已经应用 EXIF 方向（upright）；本类不读取图像
/// 元数据，也不做任何旋转。入参 `quad` 是 **工作图** 像素坐标（左上原点，
/// y 向下）；内部用 `Quad.mapped` 映射回原图，再转成 Core Image 的左下原点坐标。
final class PerspectiveCorrector {
    /// 复用 CIContext：CIContext 创建代价高，且本身是线程安全的。
    private let context: CIContext
    private let maximumOutputPixelCount: Int
    private let maximumOutputDimension = 8192

    init(context: CIContext = CIContext(),
         maximumOutputPixelCount: Int = 20_000_000) {
        self.context = context
        self.maximumOutputPixelCount = max(1, maximumOutputPixelCount)
    }

    func correct(_ image: CGImage,
                 quad: Quad,
                 workingSize: CGSize) throws -> CGImage {
        try validate(quad, workingSize: workingSize)
        guard image.width > 0, image.height > 0 else {
            throw PerspectiveCorrectionError.invalidImage
        }
        let originalSize = CGSize(width: CGFloat(image.width),
                                  height: CGFloat(image.height))
        let mapped = quad.mapped(from: workingSize, to: originalSize)
        return try render(CIImage(cgImage: image), quad: mapped)
    }

    func correct(_ image: CIImage,
                 quad: Quad,
                 workingSize: CGSize) throws -> CGImage {
        try validate(quad, workingSize: workingSize)
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else {
            throw PerspectiveCorrectionError.invalidImage
        }
        let mapped = quad.mapped(from: workingSize, to: extent.size)
        return try render(image, quad: mapped)
    }

    /// 校验工作图坐标下的四边形。面积阈值按工作图像素面积取相对值，
    /// 同时保留至少 1 px²，避免退化四边形进入 Core Image。
    private func validate(_ quad: Quad, workingSize: CGSize) throws {
        guard workingSize.width.isFinite, workingSize.height.isFinite,
              workingSize.width > 0, workingSize.height > 0 else {
            throw PerspectiveCorrectionError.invalidImage
        }
        guard quad.isFinite else {
            throw PerspectiveCorrectionError.invalidQuad
        }
        let minimumArea = max(CGFloat(1), workingSize.width * workingSize.height * 1e-6)
        guard quad.area.isFinite, quad.area >= minimumArea, quad.isConvex else {
            throw PerspectiveCorrectionError.invalidQuad
        }
    }

    private func render(_ image: CIImage, quad: Quad) throws -> CGImage {
        let extent = image.extent
        // 图像坐标 -> Core Image 左下原点坐标；mapped 的四角仍在原图像素系。
        func ciPoint(_ point: CGPoint) -> CGPoint {
            CGPoint(x: extent.minX + point.x,
                    y: extent.minY + extent.height - point.y)
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            throw PerspectiveCorrectionError.filterUnavailable
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(true, forKey: "inputCrop")
        filter.setValue(CIVector(cgPoint: ciPoint(quad.topLeft)),
                        forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: ciPoint(quad.topRight)),
                        forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: ciPoint(quad.bottomRight)),
                        forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: ciPoint(quad.bottomLeft)),
                        forKey: "inputBottomLeft")

        guard let output = filter.outputImage else {
            throw PerspectiveCorrectionError.renderFailed
        }
        let outputExtent = output.extent
        guard outputExtent.width.isFinite, outputExtent.height.isFinite,
              outputExtent.width > 0, outputExtent.height > 0 else {
            throw PerspectiveCorrectionError.renderFailed
        }
        guard outputExtent.width <= CGFloat(maximumOutputDimension),
              outputExtent.height <= CGFloat(maximumOutputDimension),
              outputExtent.width * outputExtent.height <= CGFloat(maximumOutputPixelCount) else {
            throw PerspectiveCorrectionError.outputTooLarge
        }
        guard let cgImage = context.createCGImage(output, from: outputExtent) else {
            throw PerspectiveCorrectionError.renderFailed
        }
        return cgImage
    }
}
