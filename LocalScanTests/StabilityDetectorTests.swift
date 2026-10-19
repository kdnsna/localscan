import XCTest
@testable import LocalScan

final class StabilityDetectorTests: XCTestCase {
    private let frame = CGSize(width: 1000, height: 1000)

    private func quad(offset: CGFloat = 0) -> Quad {
        QuadFixtures.rect(200 + offset, 200, 600, 600)
    }

    func testTriggersOnFourthStableFrameOnlyOnce() {
        var detector = StabilityDetector()

        for _ in 1...3 {
            XCTAssertFalse(detector.feed(quad(), frameSize: frame))
        }
        XCTAssertTrue(detector.feed(quad(), frameSize: frame))
        XCTAssertFalse(detector.feed(quad(), frameSize: frame))
        XCTAssertEqual(detector.stableFrameCount, 4)
    }

    func testSustainedStabilityFiresExactlyOnce() {
        var detector = StabilityDetector()
        var triggerCount = 0

        for _ in 0..<30 {
            if detector.feed(quad(), frameSize: frame) {
                triggerCount += 1
            }
        }

        XCTAssertEqual(triggerCount, 1)
        XCTAssertTrue(detector.isLatched)
        XCTAssertEqual(detector.stableFrameCount, 4)
    }

    func testStabilityLossThenRegainFiresSecondTime() {
        var detector = StabilityDetector()
        for _ in 1...4 {
            _ = detector.feed(quad(), frameSize: frame)
        }
        XCTAssertTrue(detector.isLatched)

        XCTAssertFalse(detector.feed(nil, frameSize: frame))
        XCTAssertFalse(detector.isLatched)
        XCTAssertEqual(detector.stableFrameCount, 0)

        var secondTriggerCount = 0
        for _ in 1...4 {
            if detector.feed(quad(), frameSize: frame) {
                secondTriggerCount += 1
            }
        }
        XCTAssertEqual(secondTriggerCount, 1)
    }

    func testLargeCornerDisplacementBreaksLatch() {
        var detector = StabilityDetector()
        for _ in 1...4 {
            _ = detector.feed(quad(), frameSize: frame)
        }
        XCTAssertTrue(detector.isLatched)

        XCTAssertFalse(detector.feed(quad(offset: 200), frameSize: frame))
        XCTAssertFalse(detector.isLatched)

        for _ in 1...3 {
            XCTAssertFalse(detector.feed(quad(offset: 200), frameSize: frame))
        }
        XCTAssertTrue(detector.feed(quad(offset: 200), frameSize: frame))
    }

    func testGradualMoveToDifferentPageBreaksLatch() {
        var config = StabilityDetector.Config()
        config.pageChangeDisplacementFraction = 0.05
        var detector = StabilityDetector(config: config)

        for _ in 1...4 {
            _ = detector.feed(quad(), frameSize: frame)
        }
        XCTAssertTrue(detector.isLatched)

        // 每帧 10 px 小于相邻帧位移上限（约 12.7 px），但累计超过换页阈值。
        for step in 1...6 {
            XCTAssertFalse(detector.feed(quad(offset: CGFloat(step) * 10),
                                         frameSize: frame))
        }
        XCTAssertFalse(detector.isLatched)
    }

    func testResetAllowsAnotherTrigger() {
        var detector = StabilityDetector()
        for _ in 1...4 {
            _ = detector.feed(quad(), frameSize: frame)
        }
        detector.reset()
        XCTAssertEqual(detector.stableFrameCount, 0)
        XCTAssertFalse(detector.isLatched)

        for _ in 1...3 {
            XCTAssertFalse(detector.feed(quad(), frameSize: frame))
        }
        XCTAssertTrue(detector.feed(quad(), frameSize: frame))
    }

    func testRearmAllowsAnotherTrigger() {
        var detector = StabilityDetector()
        for _ in 1...4 {
            _ = detector.feed(quad(), frameSize: frame)
        }
        detector.rearm()
        XCTAssertEqual(detector.stableFrameCount, 0)
        XCTAssertFalse(detector.isLatched)

        for _ in 1...3 {
            XCTAssertFalse(detector.feed(quad(), frameSize: frame))
        }
        XCTAssertTrue(detector.feed(quad(), frameSize: frame))
    }

    func testJitteryInputNeverTriggers() {
        var detector = StabilityDetector()
        for i in 0..<12 {
            let offset: CGFloat = i.isMultiple(of: 2) ? 40 : -40
            XCTAssertFalse(detector.feed(quad(offset: offset), frameSize: frame))
        }
    }

    func testTooMuchTiltNeverTriggers() {
        var detector = StabilityDetector()
        // 上下边错开 200 px、高 600 px：内角偏离 90° 约 18.43°。
        let tilted = Quad(topLeft: CGPoint(x: 150, y: 200),
                          topRight: CGPoint(x: 650, y: 200),
                          bottomRight: CGPoint(x: 850, y: 800),
                          bottomLeft: CGPoint(x: 350, y: 800))
        for _ in 0..<6 {
            XCTAssertFalse(detector.feed(tilted, frameSize: frame))
        }
    }

    func testAutoCaptureGateDisabledNeverFires() {
        var gate = AutoCaptureGate(isEnabled: false)

        for _ in 0..<30 {
            XCTAssertFalse(gate.feed(quad(), frameSize: frame))
        }

        XCTAssertEqual(gate.detector.stableFrameCount, 0)
        XCTAssertFalse(gate.detector.isLatched)
    }

    /// 重新打开自动拍摄后先锁存：手机不动不会立刻拍，出现不稳定后才重新计数。
    func testAutoCaptureGateEnableWaitsForInstability() {
        var gate = AutoCaptureGate(isEnabled: false)
        gate.isEnabled = true
        for _ in 0..<30 {
            XCTAssertFalse(gate.feed(quad(), frameSize: frame))
        }
        XCTAssertFalse(gate.feed(nil, frameSize: frame))
        for _ in 1...3 {
            XCTAssertFalse(gate.feed(quad(), frameSize: frame))
        }
        XCTAssertTrue(gate.feed(quad(), frameSize: frame))
    }

    func testAutoCaptureGateToggleOffThenOnStaysLatchedWhileStill() {
        var gate = AutoCaptureGate()
        for _ in 1...4 {
            _ = gate.feed(quad(), frameSize: frame)
        }
        XCTAssertTrue(gate.detector.isLatched)

        gate.isEnabled = false
        XCTAssertFalse(gate.feed(quad(), frameSize: frame))
        gate.isEnabled = true
        for _ in 0..<30 {
            XCTAssertFalse(gate.feed(quad(), frameSize: frame))
        }
        XCTAssertTrue(gate.detector.isLatched)
    }

    /// 手动拍摄（自动尚未触发）后持续稳定：自动不再拍同一页。
    func testManualCaptureBeforeAutoFiresThenSustainedStabilityDoesNotFire() {
        var gate = AutoCaptureGate()
        for _ in 1...2 {
            XCTAssertFalse(gate.feed(quad(), frameSize: frame))
        }
        gate.latchAfterManualCapture(reference: quad())
        for _ in 0..<30 {
            XCTAssertFalse(gate.feed(quad(), frameSize: frame))
        }
    }

    /// 自动已触发后再按手动快门：仍然锁存，不会重复拍。
    func testManualCaptureAfterAutoFiredStaysLatched() {
        var gate = AutoCaptureGate()
        var fires = 0
        for _ in 1...4 where gate.feed(quad(), frameSize: frame) { fires += 1 }
        XCTAssertEqual(fires, 1)
        gate.latchAfterManualCapture(reference: quad())
        for _ in 0..<30 {
            XCTAssertFalse(gate.feed(quad(), frameSize: frame))
        }
    }

    /// 手动拍摄后换页：自动正常触发。
    func testManualCaptureThenPageChangeFiresNormally() {
        var gate = AutoCaptureGate()
        gate.latchAfterManualCapture(reference: quad())
        XCTAssertFalse(gate.feed(quad(), frameSize: frame))
        XCTAssertFalse(gate.feed(quad(offset: 200), frameSize: frame))
        for _ in 1...3 {
            XCTAssertFalse(gate.feed(quad(offset: 200), frameSize: frame))
        }
        XCTAssertTrue(gate.feed(quad(offset: 200), frameSize: frame))
    }

    func testRequiredFramesIsClampedToThreeThroughFive() {
        XCTAssertEqual(StabilityDetector.Config(requiredFrames: 1).requiredFrames, 3)
        XCTAssertEqual(StabilityDetector.Config(requiredFrames: 9).requiredFrames, 5)
    }
}
