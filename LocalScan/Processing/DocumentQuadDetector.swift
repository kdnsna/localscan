import CoreGraphics
import Vision

/// 在工作图上跑一次文档分割，返回工作图像素坐标（左上原点，y 向下）。
/// 检测失败或结果退化时回退到 6% 内缩框。
enum DocumentQuadDetector {
    /// 检测框至少要覆盖工作图面积的 1%。小框通常来自误检（文字块、桌面纹理），
    /// 直接回退到 6% 内缩框比把它拉成一张模糊的“页面”更好。
    static let minimumAreaFraction: CGFloat = 0.01

    static func detect(in image: CGImage) -> Quad {
        let size = CGSize(width: image.width, height: image.height)
        let request = VNDetectDocumentSegmentationRequest()
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
                .perform([request])
            if let observation = request.results?.first,
               let quad = pixelQuad(fromVisionPoints: [observation.topLeft,
                                                       observation.topRight,
                                                       observation.bottomRight,
                                                       observation.bottomLeft],
                                    imageSize: size) {
                return quad
            }
        } catch {
            // 找边失败不阻断拍摄：使用默认内缩框，仍可在手动裁剪里调整。
        }
        return Quad.insetDefault(for: size)
    }

    /// Vision 归一化点（左下原点，0–1）-> 工作图像素坐标（左上原点）。
    /// 凸性与面积在像素坐标上检查；面积不足工作图 1% 时返回 nil，
    /// 由 `detect` 回退到 6% 内缩框。
    static func pixelQuad(fromVisionPoints points: [CGPoint],
                          imageSize: CGSize) -> Quad? {
        guard points.count == 4,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let pixel = DocumentDetectorGeometry.quad(fromVisionPoints: points)
            .scaled(by: imageSize.width, imageSize.height)
        let minimumArea = max(CGFloat(1),
                              imageSize.width * imageSize.height * minimumAreaFraction)
        guard pixel.isFinite, pixel.isConvex,
              pixel.area.isFinite, pixel.area >= minimumArea else { return nil }
        return pixel
    }
}
