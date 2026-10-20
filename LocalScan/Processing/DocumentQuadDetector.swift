import CoreGraphics
import Vision

/// 在工作图上跑一次文档分割，返回工作图像素坐标（左上原点，y 向下）。
/// 检测失败或结果退化时回退到 6% 内缩框。
enum DocumentQuadDetector {
    static func detect(in image: CGImage) -> Quad {
        let request = VNDetectDocumentSegmentationRequest()
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
                .perform([request])
            if let observation = request.results?.first {
                let quad = DocumentDetectorGeometry.quad(
                    fromVisionPoints: [observation.topLeft,
                                       observation.topRight,
                                       observation.bottomRight,
                                       observation.bottomLeft])
                if quad.isFinite, quad.isConvex, quad.area > 0 {
                    return quad
                }
            }
        } catch {
            // 找边失败不阻断拍摄：使用默认内缩框，仍可在手动裁剪里调整。
        }
        return Quad.insetDefault(for: CGSize(width: image.width,
                                             height: image.height))
    }
}
