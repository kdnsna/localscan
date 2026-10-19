import CoreGraphics
import XCTest
@testable import LocalScan

final class CornerRefinerTests: XCTestCase {
    private let size = CGSize(width: 600, height: 800)
    private var truth: Quad {
        Quad(topLeft: CGPoint(x: 120, y: 100),
             topRight: CGPoint(x: 480, y: 140),
             bottomRight: CGPoint(x: 450, y: 700),
             bottomLeft: CGPoint(x: 90, y: 660))
    }

    private func image() -> CGImage {
        TestImages.page(size: size, quad: truth)
    }

    func testRefinesOffsetCornerTowardTruth() {
        var offset = truth
        offset.topLeft = CGPoint(x: truth.topLeft.x + 7,
                                 y: truth.topLeft.y + 6)
        let refined = CornerRefiner().refine(offset, in: image())
        let before = TestImages.distance(offset.topLeft, truth.topLeft)
        let after = TestImages.distance(refined.topLeft, truth.topLeft)

        XCTAssertLessThan(after, before * 0.75)
        XCTAssertTrue(refined.isConvex)
    }

    func testLeavesCorrectQuadEssentiallyUnchanged() {
        let refined = CornerRefiner().refine(truth, in: image())
        XCTAssertLessThan(refined.maxCornerDisplacement(to: truth), 2)
    }
}
