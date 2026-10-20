import CoreGraphics

/// 手动裁剪编辑器的纯坐标映射：工作图按 aspect-fit 放进视图，坐标原点均为左上。
enum CornerEditorGeometry {
    static func fittedRect(imageSize: CGSize, viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let scale = min(viewSize.width / imageSize.width,
                        viewSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale,
                          height: imageSize.height * scale)
        return CGRect(x: (viewSize.width - size.width) / 2,
                      y: (viewSize.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    static func viewPoint(fromImage point: CGPoint,
                          imageSize: CGSize,
                          viewSize: CGSize) -> CGPoint {
        let rect = fittedRect(imageSize: imageSize, viewSize: viewSize)
        guard rect.width > 0, rect.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return .zero }
        return CGPoint(x: rect.minX + point.x / imageSize.width * rect.width,
                       y: rect.minY + point.y / imageSize.height * rect.height)
    }

    static func imagePoint(fromView point: CGPoint,
                           imageSize: CGSize,
                           viewSize: CGSize) -> CGPoint {
        let rect = fittedRect(imageSize: imageSize, viewSize: viewSize)
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(x: (point.x - rect.minX) / rect.width * imageSize.width,
                       y: (point.y - rect.minY) / rect.height * imageSize.height)
    }

    static func clamp(_ point: CGPoint, to imageSize: CGSize) -> CGPoint {
        CGPoint(x: min(max(0, point.x), max(0, imageSize.width)),
                y: min(max(0, point.y), max(0, imageSize.height)))
    }

    static func replacingCorner(_ quad: Quad, index: Int, with point: CGPoint) -> Quad {
        var result = quad
        switch index {
        case 0: result.topLeft = point
        case 1: result.topRight = point
        case 2: result.bottomRight = point
        case 3: result.bottomLeft = point
        default: return quad
        }
        return result
    }
}
