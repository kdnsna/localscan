import CoreGraphics

/// 四边形时域平滑：检测更新时从旧框向新框做 smoothstep 过渡；
/// 长时间没有检测则返回 nil。
struct QuadSmoother {
    var duration: Double
    var dropAfter: Double

    private var current: Quad?
    private var start: Quad?
    private var target: Quad?
    private var elapsed: Double = 0
    private var timeSinceDetection: Double = 0

    init(duration: Double = ScanDefaults.smoothingDuration,
         dropAfter: Double = ScanDefaults.smoothingDropAfter) {
        self.duration = max(0, duration)
        self.dropAfter = max(0, dropAfter)
    }

    mutating func update(_ new: Quad?, dt: Double) -> Quad? {
        // 非有限（NaN/无穷）或负的时间步按 0 处理，避免污染计时。
        let step = dt.isFinite ? max(0, dt) : 0

        guard let new = new else {
            timeSinceDetection += step
            if timeSinceDetection >= dropAfter {
                current = nil
                start = nil
                target = nil
                elapsed = 0
                return nil
            }
            advance(by: step)
            return current
        }

        timeSinceDetection = 0
        guard let existing = current else {
            current = new
            start = new
            target = new
            elapsed = duration
            return new
        }

        // 只有目标真的变化时才重新开始过渡，避免每帧都被重置。
        if target != new {
            start = existing
            target = new
            elapsed = 0
        }
        advance(by: step)
        return current
    }

    private mutating func advance(by step: Double) {
        guard let start = start, let target = target else { return }
        guard duration > 0 else {
            current = target
            elapsed = 0
            return
        }
        elapsed = min(duration, elapsed + step)
        let t = min(1, max(0, elapsed / duration))
        let eased = t * t * (3 - 2 * t)
        current = interpolate(start, target, progress: CGFloat(eased))
    }

    private func interpolate(_ a: Quad, _ b: Quad, progress: CGFloat) -> Quad {
        let t = min(1, max(0, progress))
        func lerp(_ p: CGPoint, _ q: CGPoint) -> CGPoint {
            CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
        }
        return Quad(topLeft: lerp(a.topLeft, b.topLeft),
                    topRight: lerp(a.topRight, b.topRight),
                    bottomRight: lerp(a.bottomRight, b.bottomRight),
                    bottomLeft: lerp(a.bottomLeft, b.bottomLeft))
    }
}
