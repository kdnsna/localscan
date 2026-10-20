import CoreGraphics

/// 自动拍摄触发：连续 N 帧角点稳定、倾斜和面积达标时返回一次 true。
///
/// 触发后会锁存（`isLatched`），继续收到稳定帧也不会再次返回 true。
/// 只有稳定状态被打破才会解除锁存：无四边形、面积/倾斜/相邻帧位移超限，
/// 或与触发时的页面差异过大（换页）。解除后需再连续 N 帧稳定才会再次触发。
/// 手动拍摄成功后、或重新打开自动拍摄时调用 `latch(reference:)`：同样锁存，
/// 直到稳定被打破或换页才解锁，避免对同一页重复拍摄。
///
/// `requiredFrames` 计的是“稳定帧”的数量，包含第一帧。第一帧没有前帧可比，
/// 所以默认 `requiredFrames = 4` 实际做的是 3 次相邻帧比较；实现与
/// `feed` 中的 `stableFrameCount` 计数一致。
/// 倾斜用四个内角偏离 90° 的最大值近似（见 `QuadGeometry.maxTiltDegrees`）。
struct StabilityDetector {
    struct Config {
        /// 需要连续稳定的帧数（含首帧），因此相邻帧比较次数为 `requiredFrames - 1`。
        var requiredFrames: Int
        var maxDisplacementFraction: CGFloat
        var maxTiltDegrees: Double
        var minAreaFraction: CGFloat
        /// 锁存后与触发时页面相比，判定为换页的角点位移上限（占对角线比例）。
        var pageChangeDisplacementFraction: CGFloat

        init(requiredFrames: Int = ScanDefaults.autoCaptureRequiredFrames,
             maxDisplacementFraction: CGFloat = ScanDefaults.autoCaptureMaxDisplacementFraction,
             maxTiltDegrees: Double = ScanDefaults.tiltWarningDegrees,
             minAreaFraction: CGFloat = ScanDefaults.autoCaptureMinAreaFraction,
             pageChangeDisplacementFraction: CGFloat =
                ScanDefaults.autoCapturePageChangeDisplacementFraction) {
            let range = ScanDefaults.autoCaptureRequiredFramesRange
            self.requiredFrames = min(range.upperBound, max(range.lowerBound, requiredFrames))
            self.maxDisplacementFraction = max(0, maxDisplacementFraction)
            self.maxTiltDegrees = max(0, maxTiltDegrees)
            self.minAreaFraction = min(1, max(0, minAreaFraction))
            self.pageChangeDisplacementFraction = max(0, pageChangeDisplacementFraction)
        }
    }

    var config: Config
    private(set) var stableFrameCount = 0
    /// 触发后保持锁存，直到稳定状态被打破或显式 `rearm()` / `reset()`。
    private(set) var isLatched = false
    private var previous: Quad?
    /// 触发时的四边形，用于识别锁存期间的明显换页。
    private var triggeredQuad: Quad?

    init(config: Config = Config()) {
        self.config = config
    }

    /// 喂入一帧检测结果；返回 true 表示本帧应触发一次拍照。
    /// 锁存期间始终返回 false，直到稳定状态被打破。
    mutating func feed(_ quad: Quad?, frameSize: CGSize) -> Bool {
        guard let quad = quad, frameSize.width > 0, frameSize.height > 0 else {
            loseStability()
            return false
        }

        let areaFraction = quad.area / (frameSize.width * frameSize.height)
        let tilt = QuadGeometry.maxTiltDegrees(quad)
        guard areaFraction >= config.minAreaFraction,
              tilt <= config.maxTiltDegrees else {
            loseStability()
            return false
        }

        let displacement = previous.map { quad.maxCornerDisplacement(to: $0) } ?? 0
        let displacementLimit = quad.diagonalLength * config.maxDisplacementFraction
        guard displacement <= displacementLimit else {
            loseStability()
            return false
        }

        // 锁存后即使每帧位移都很小，累计移动到明显不同的页面也要解除锁存。
        if isLatched, let triggeredQuad {
            let pageChangeLimit = triggeredQuad.diagonalLength
                * config.pageChangeDisplacementFraction
            if quad.maxCornerDisplacement(to: triggeredQuad) > pageChangeLimit {
                loseStability()
                return false
            }
        }

        previous = quad
        guard !isLatched else { return false }

        stableFrameCount += 1
        guard stableFrameCount >= config.requiredFrames else { return false }
        isLatched = true
        triggeredQuad = quad
        return true
    }

    /// 主动锁存（手动拍摄成功后、重新打开自动拍摄时）：以 `reference`
    /// （缺省为最近一帧）作为换页判定基准，直到稳定被打破或换页才会再次累计。
    /// 没有任何基准框（`reference` 与最近一帧都为 nil）时不锁存，只清零稳定计数：
    /// 否则换页判定无从比较，锁存永远解不开，自动拍摄会失效。
    mutating func latch(reference: Quad? = nil) {
        stableFrameCount = 0
        guard let base = reference ?? previous else {
            isLatched = false
            triggeredQuad = nil
            return
        }
        isLatched = true
        triggeredQuad = base
    }

    /// 解锁：下一次连续 N 帧稳定可再次触发。保留当前帧作为位移基准。
    /// 仅用于测试或确需立即重新计数的场景；手动拍摄请用 `latch(reference:)`。
    mutating func rearm() {
        stableFrameCount = 0
        isLatched = false
        triggeredQuad = nil
    }

    /// 完整重置（会话开始/停止等生命周期变化）：解除锁存并清空位移基准。
    mutating func reset() {
        rearm()
        previous = nil
    }

    private mutating func loseStability() {
        stableFrameCount = 0
        isLatched = false
        triggeredQuad = nil
        previous = nil
    }
}

/// 自动拍摄门控：关闭时完全不喂帧，因此绝不触发；开启时才委托稳定判定。
/// 纯值类型，便于单测。重新打开时锁存（以关闭前最后一帧为基准），
/// 需先出现不稳定或换页才开始新一轮计数。
struct AutoCaptureGate {
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue, isEnabled else { return }
            detector.latch()
        }
    }

    private(set) var detector: StabilityDetector

    init(isEnabled: Bool = true,
         detector: StabilityDetector = StabilityDetector()) {
        self.isEnabled = isEnabled
        self.detector = detector
    }

    /// 返回 true 表示本帧应触发一次自动拍照；关闭时永远返回 false。
    mutating func feed(_ quad: Quad?, frameSize: CGSize) -> Bool {
        guard isEnabled else { return false }
        return detector.feed(quad, frameSize: frameSize)
    }

    /// 手动拍摄成功后调用：以当前框为基准锁存，防止自动再拍同一页。
    mutating func latchAfterManualCapture(reference: Quad?) {
        detector.latch(reference: reference)
    }

    /// 控制器在手动拍摄回调里调用：只有成功拍到（`succeeded`）才锁存；失败不改变状态。
    mutating func handleManualCaptureResult(succeeded: Bool, reference: Quad?) {
        guard succeeded else { return }
        latchAfterManualCapture(reference: reference)
    }

    /// 会话中断结束：没有检测框时只清计数/解锁，避免恢复后永远锁死；
    /// 有基准框时锁存到同页稳定被打破，防止恢复后重复拍同一页。
    mutating func handleInterruptionEnded(lastDetectedQuad: Quad?) {
        latchAfterManualCapture(reference: lastDetectedQuad)
    }

    /// 会话级完整重置。
    mutating func reset() {
        detector.reset()
    }
}
