import CoreGraphics
import Vision

/// 在工作图上跑一次文档分割，返回工作图像素坐标（左上原点，y 向下）。
/// 检测失败或结果退化时回退到 6% 内缩框。
enum DocumentQuadDetector {
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
    /// 凸性与面积在像素坐标上检查；面积阈值与 PerspectiveCorrector 一致，
    /// 不通过时返回 nil，由调用方回退到内缩框。
    static func pixelQuad(fromVisionPoints points: [CGPoint],
                          imageSize: CGSize) -> Quad? {
        guard points.count == 4,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let pixel = DocumentDetectorGeometry.quad(fromVisionPoints: points)
            .scaled(by: imageSize.width, imageSize.height)
        let minimumArea = max(CGFloat(1), imageSize.width * imageSize.height * 1e-6)
        guard pixel.isFinite, pixel.isConvex,
              pixel.area.isFinite, pixel.area >= minimumArea else { return nil }
        return pixel
    }
}
