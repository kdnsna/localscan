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

    func testResetAllowsAnotherTrigger() {
        var detector = StabilityDetector()
        for _ in 1...4 {
            _ = detector.feed(quad(), frameSize: frame)
        }
        detector.reset()
        XCTAssertEqual(detector.stableFrameCount, 0)

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

    func testRequiredFramesIsClampedToThreeThroughFive() {
        XCTAssertEqual(StabilityDetector.Config(requiredFrames: 1).requiredFrames, 3)
        XCTAssertEqual(StabilityDetector.Config(requiredFrames: 9).requiredFrames, 5)
    }
}
