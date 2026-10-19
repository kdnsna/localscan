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

    /// 四个角点坐标是否全部有限（非 NaN、非无穷）。
    var isFinite: Bool {
        corners.allSatisfy { $0.x.isFinite && $0.y.isFinite }
    }

    /// 把 4 个任意顺序的点排成 TL、TR、BR、BL。屏幕坐标 y 向下，极角升序即顺时针。
    ///
    /// 这里只负责排序，**不验证形状**：凹四边形、共线点会得到一个可能自交或面积为 0
    /// 的四边形，调用方必须自己检查 `isConvex` 和 `area`。
    ///
    /// 任一点含 NaN/无穷时返回 `.zero`（无法可靠排序）。
    /// 左上角取 x+y 最小者；并列时依次取 y 更小、x 更小者。同极角（共线/重合）时
    /// 先按到中心距离从远到近，再按 y、x 排序，保证输入顺序不影响结果。
    static func ordered(from points: [CGPoint]) -> Quad {
        precondition(points.count == 4, "Quad.ordered 需要恰好 4 个点")
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return .zero
        }
        let center = CGPoint(
            x: points.reduce(CGFloat.zero) { $0 + $1.x } / CGFloat(points.count),
            y: points.reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(points.count)
        )
        var sorted = points.sorted { a, b in
            let angleA = atan2(Double(a.y - center.y), Double(a.x - center.x))
            let angleB = atan2(Double(b.y - center.y), Double(b.x - center.x))
            if angleA != angleB { return angleA < angleB }

            let radiusA = (a.x - center.x) * (a.x - center.x)
                + (a.y - center.y) * (a.y - center.y)
            let radiusB = (b.x - center.x) * (b.x - center.x)
                + (b.y - center.y) * (b.y - center.y)
            if radiusA != radiusB { return radiusA > radiusB }
            if a.y != b.y { return a.y < b.y }
            return a.x < b.x
        }

        // 旋转到 x+y 最小的点作为左上角；显式字典序并列规则保证结果确定。
        var start = 0
        for i in 1..<sorted.count where isTopLeftCandidate(sorted[i], than: sorted[start]) {
            start = i
        }
        sorted = (0..<4).map { sorted[(start + $0) % 4] }
        return Quad(topLeft: sorted[0], topRight: sorted[1],
                    bottomRight: sorted[2], bottomLeft: sorted[3])
    }

    private static func isTopLeftCandidate(_ a: CGPoint, than b: CGPoint) -> Bool {
        let sumA = a.x + a.y
        let sumB = b.x + b.y
        if sumA != sumB { return sumA < sumB }
        if a.y != b.y { return a.y < b.y }
        return a.x < b.x
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
