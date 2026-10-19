import CoreGraphics

/// 自动拍摄触发：连续 N 帧角点稳定、倾斜和面积达标时返回一次 true。
/// 触发后进入冷却，直到调用 `reset()`。
struct StabilityDetector {
    struct Config {
        var requiredFrames: Int
        var maxDisplacementFraction: CGFloat
        var maxTiltDegrees: Double
        var minAreaFraction: CGFloat

        init(requiredFrames: Int = ScanDefaults.autoCaptureRequiredFrames,
             maxDisplacementFraction: CGFloat = ScanDefaults.autoCaptureMaxDisplacementFraction,
             maxTiltDegrees: Double = ScanDefaults.tiltWarningDegrees,
             minAreaFraction: CGFloat = ScanDefaults.autoCaptureMinAreaFraction) {
            let range = ScanDefaults.autoCaptureRequiredFramesRange
            self.requiredFrames = min(range.upperBound, max(range.lowerBound, requiredFrames))
            self.maxDisplacementFraction = max(0, maxDisplacementFraction)
            self.maxTiltDegrees = max(0, maxTiltDegrees)
            self.minAreaFraction = min(1, max(0, minAreaFraction))
        }
    }

    var config: Config
    private(set) var stableFrameCount = 0
    private var previous: Quad?
    private var hasTriggered = false

    init(config: Config = Config()) {
        self.config = config
    }

    mutating func feed(_ quad: Quad?, frameSize: CGSize) -> Bool {
        guard !hasTriggered else { return false }
        guard let quad = quad, frameSize.width > 0, frameSize.height > 0 else {
            stableFrameCount = 0
            previous = nil
            return false
        }

        let areaFraction = quad.area / (frameSize.width * frameSize.height)
        let tilt = QuadGeometry.maxTiltDegrees(quad)
        let displacement = previous.map { quad.maxCornerDisplacement(to: $0) } ?? 0
        let displacementLimit = quad.diagonalLength * config.maxDisplacementFraction
        let isStable = areaFraction >= config.minAreaFraction
            && tilt <= config.maxTiltDegrees
            && displacement <= displacementLimit

        previous = quad
        if isStable {
            stableFrameCount += 1
            if stableFrameCount >= config.requiredFrames {
                hasTriggered = true
                return true
            }
        } else {
            stableFrameCount = 0
        }
        return false
    }

    mutating func reset() {
        stableFrameCount = 0
        previous = nil
        hasTriggered = false
    }
}
