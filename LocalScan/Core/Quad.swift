import CoreGraphics
import Foundation

/// 四边形（顺序固定为 TL、TR、BR、BL）。坐标既可以是像素，也可以是归一化值。
struct Quad: Equatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    static let zero = Quad(topLeft: .zero, topRight: .zero,
                           bottomRight: .zero, bottomLeft: .zero)

    var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// 按 x、y 各自的比例缩放。
    func scaled(by sx: CGFloat, _ sy: CGFloat) -> Quad {
        Quad(topLeft: CGPoint(x: topLeft.x * sx, y: topLeft.y * sy),
             topRight: CGPoint(x: topRight.x * sx, y: topRight.y * sy),
             bottomRight: CGPoint(x: bottomRight.x * sx, y: bottomRight.y * sy),
             bottomLeft: CGPoint(x: bottomLeft.x * sx, y: bottomLeft.y * sy))
    }

    func scaled(by sx: CGFloat, sy: CGFloat) -> Quad {
        scaled(by: sx, sy)
    }

    /// 工作图坐标 -> 原图坐标（或反向），按尺寸比例映射。
    func mapped(from source: CGSize, to target: CGSize) -> Quad {
        guard source.width > 0, source.height > 0 else { return self }
        return scaled(by: target.width / source.width,
                      target.height / source.height)
    }

    /// 鞋带公式面积。
    var area: CGFloat {
        let p = corners
        var twiceArea: CGFloat = 0
        for i in p.indices {
            let j = (i + 1) % p.count
            twiceArea += p[i].x * p[j].y - p[j].x * p[i].y
        }
        return abs(twiceArea) * 0.5
    }

    var isConvex: Bool {
        let p = corners
        var sign: CGFloat = 0
        for i in p.indices {
            let a = p[i]
            let b = p[(i + 1) % p.count]
            let c = p[(i + 2) % p.count]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            guard abs(cross) > 1e-9 else { return false }
            let current: CGFloat = cross > 0 ? 1 : -1
            if sign == 0 {
                sign = current
            } else if sign != current {
                return false
            }
        }
        return true
    }

    /// 两条对角线的平均长度。
    var diagonalLength: CGFloat {
        let d1 = Quad.distance(topLeft, bottomRight)
        let d2 = Quad.distance(topRight, bottomLeft)
        return (d1 + d2) * 0.5
    }

    /// 同名角点之间的最大位移。
    func maxCornerDisplacement(to other: Quad) -> CGFloat {
        zip(corners, other.corners).map { Quad.distance($0.0, $0.1) }.max() ?? 0
    }

    /// 把 4 个任意顺序的点排成 TL、TR、BR、BL。屏幕坐标 y 向下，极角升序即顺时针。
    static func ordered(from points: [CGPoint]) -> Quad {
        precondition(points.count == 4, "Quad.ordered 需要恰好 4 个点")
        let center = CGPoint(
            x: points.reduce(CGFloat.zero) { $0 + $1.x } / CGFloat(points.count),
            y: points.reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(points.count)
        )
        var sorted = points.sorted {
            atan2(Double($0.y - center.y), Double($0.x - center.x))
                < atan2(Double($1.y - center.y), Double($1.x - center.x))
        }

        // 旋转到 x+y 最小的点作为左上角；并列时取更靠上的点。
        var start = 0
        for i in 1..<sorted.count {
            let a = sorted[i]
            let b = sorted[start]
            if a.x + a.y < b.x + b.y
                || (a.x + a.y == b.x + b.y && a.y < b.y) {
                start = i
            }
        }
        sorted = (0..<4).map { sorted[(start + $0) % 4] }
        return Quad(topLeft: sorted[0], topRight: sorted[1],
                    bottomRight: sorted[2], bottomLeft: sorted[3])
    }

    /// 找边失败时的默认四边形：四边各向内缩 `inset`（默认 6%）。
    static func insetDefault(for size: CGSize,
                             inset: CGFloat = ScanDefaults.defaultQuadInset) -> Quad {
        guard size.width > 0, size.height > 0 else { return .zero }
        let fraction = min(0.5, max(0, inset))
        let dx = size.width * fraction
        let dy = size.height * fraction
        return Quad(topLeft: CGPoint(x: dx, y: dy),
                    topRight: CGPoint(x: size.width - dx, y: dy),
                    bottomRight: CGPoint(x: size.width - dx, y: size.height - dy),
                    bottomLeft: CGPoint(x: dx, y: size.height - dy))
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
