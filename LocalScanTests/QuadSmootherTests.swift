import XCTest
@testable import LocalScan

final class QuadSmootherTests: XCTestCase {
    func testSmoothstepEasingAndCompletion() {
        var smoother = QuadSmoother(duration: 1, dropAfter: 2)
        let start = QuadFixtures.rect(0, 0, 100, 100)
        let end = QuadFixtures.rect(100, 0, 100, 100)

        XCTAssertEqual(smoother.update(start, dt: 0)!, start)
        // smoothstep(0.25) = 0.15625
        let quarter = smoother.update(end, dt: 0.25)!
        XCTAssertEqual(quarter.topLeft.x, 15.625, accuracy: 1e-6)
        XCTAssertEqual(smoother.update(end, dt: 0.75)!, end)
    }

    func testDropsAfterNoDetection() {
        var smoother = QuadSmoother(duration: 0.15, dropAfter: 0.5)
        let quad = QuadFixtures.rect(0, 0, 100, 100)

        XCTAssertEqual(smoother.update(quad, dt: 0.016)!, quad)
        XCTAssertNotNil(smoother.update(nil, dt: 0.49))
        XCTAssertNil(smoother.update(nil, dt: 0.02))
        XCTAssertEqual(smoother.update(quad, dt: 0)!, quad)
    }

    func testRepeatedTargetDoesNotRestartTransition() {
        var smoother = QuadSmoother(duration: 0.2, dropAfter: 1)
        let start = QuadFixtures.rect(0, 0, 100, 100)
        let end = QuadFixtures.rect(100, 0, 100, 100)

        XCTAssertEqual(smoother.update(start, dt: 0)!, start)
        let halfway = smoother.update(end, dt: 0.1)!
        XCTAssertNotEqual(halfway, end)
        XCTAssertEqual(smoother.update(end, dt: 0.1)!, end)
    }
}
