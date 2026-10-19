import CoreGraphics
import Foundation

/// 四边形相关的纯几何计算。
enum QuadGeometry {
    /// 透视校正输出尺寸：对边长度取平均后四舍五入。
    static func outputSize(for quad: Quad) -> CGSize {
        let top = distance(quad.topLeft, quad.topRight)
        let bottom = distance(quad.bottomLeft, quad.bottomRight)
        let left = distance(quad.topLeft, quad.bottomLeft)
        let right = distance(quad.topRight, quad.bottomRight)
        return CGSize(width: ((top + bottom) * 0.5).rounded(),
                      height: ((left + right) * 0.5).rounded())
    }

    /// 四个内角偏离 90° 的最大值（度）。
    static func maxTiltDegrees(_ quad: Quad) -> Double {
        let p = quad.corners
        var maximum = 0.0
        for i in p.indices {
            let angle = interiorAngle(previous: p[(i + 3) % p.count],
                                      vertex: p[i],
                                      next: p[(i + 1) % p.count])
            maximum = max(maximum, abs(angle - 90))
        }
        return maximum
    }

    /// 在并集包围盒上均匀采样，用点是否在多边形内近似 IoU（确定性的）。
    static func iou(_ a: Quad, _ b: Quad, gridSteps: Int = 64) -> Double {
        let steps = max(1, gridSteps)
        let aPoints = a.corners
        let bPoints = b.corners
        let minX = min(aPoints.map(\.x).min() ?? 0, bPoints.map(\.x).min() ?? 0)
        let maxX = max(aPoints.map(\.x).max() ?? 0, bPoints.map(\.x).max() ?? 0)
        let minY = min(aPoints.map(\.y).min() ?? 0, bPoints.map(\.y).min() ?? 0)
        let maxY = max(aPoints.map(\.y).max() ?? 0, bPoints.map(\.y).max() ?? 0)
        let width = maxX - minX
        let height = maxY - minY
        guard width > 0, height > 0 else { return 0 }

        let cellWidth = width / CGFloat(steps)
        let cellHeight = height / CGFloat(steps)
        var intersection = 0
        var union = 0
        for ix in 0..<steps {
            let x = minX + (CGFloat(ix) + 0.5) * cellWidth
            for iy in 0..<steps {
                let y = minY + (CGFloat(iy) + 0.5) * cellHeight
                let point = CGPoint(x: x, y: y)
                let inA = contains(a, point)
                let inB = contains(b, point)
                if inA || inB { union += 1 }
                if inA && inB { intersection += 1 }
            }
        }
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func interiorAngle(previous: CGPoint,
                                      vertex: CGPoint,
                                      next: CGPoint) -> Double {
        let ux = Double(previous.x - vertex.x)
        let uy = Double(previous.y - vertex.y)
        let vx = Double(next.x - vertex.x)
        let vy = Double(next.y - vertex.y)
        let lu = (ux * ux + uy * uy).squareRoot()
        let lv = (vx * vx + vy * vy).squareRoot()
        guard lu > 1e-12, lv > 1e-12 else { return 90 }
        let cosine = max(-1, min(1, (ux * vx + uy * vy) / (lu * lv)))
        return acos(cosine) * 180 / Double.pi
    }

    /// 射线法判断点是否在四边形内；落在边界上的点不保证一致。
    private static func contains(_ quad: Quad, _ point: CGPoint) -> Bool {
        let p = quad.corners
        var inside = false
        var previous = p.count - 1
        for current in p.indices {
            let a = p[current]
            let b = p[previous]
            if (a.y > point.y) != (b.y > point.y) {
                let x = a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y)
                if point.x < x { inside.toggle() }
            }
            previous = current
        }
        return inside
    }
}
