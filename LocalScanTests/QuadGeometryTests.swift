import XCTest
@testable import LocalScan

final class QuadGeometryTests: XCTestCase {
    func testOutputSizeUsesAverageOppositeSides() {
        // A4 比例附近的梯形：上边 1000、下边 960，高约 1414。
        let quad = Quad(topLeft: CGPoint(x: 0, y: 0),
                        topRight: CGPoint(x: 1000, y: 0),
                        bottomRight: CGPoint(x: 980, y: 1414),
                        bottomLeft: CGPoint(x: 20, y: 1414))
        XCTAssertEqual(QuadGeometry.outputSize(for: quad),
                       CGSize(width: 980, height: 1414))
    }

    func testRectangleHasNoTilt() {
        let quad = QuadFixtures.rect(0, 0, 300, 200)
        XCTAssertEqual(QuadGeometry.maxTiltDegrees(quad), 0, accuracy: 1e-6)
    }

    func testShearedParallelogramTiltIsFortyFiveDegrees() {
        let quad = Quad(topLeft: CGPoint(x: 0, y: 0),
                        topRight: CGPoint(x: 100, y: 0),
                        bottomRight: CGPoint(x: 200, y: 100),
                        bottomLeft: CGPoint(x: 100, y: 100))
        XCTAssertEqual(QuadGeometry.maxTiltDegrees(quad), 45, accuracy: 1e-6)
    }

    func testIoUOfIdenticalQuadsIsOne() {
        let quad = QuadFixtures.rect(0, 0, 100, 100)
        XCTAssertEqual(QuadGeometry.iou(quad, quad, gridSteps: 50), 1, accuracy: 1e-9)
    }

    func testIoUOfDisjointQuadsIsZero() {
        let a = QuadFixtures.rect(0, 0, 100, 100)
        let b = QuadFixtures.rect(200, 0, 100, 100)
        XCTAssertEqual(QuadGeometry.iou(a, b, gridSteps: 50), 0, accuracy: 1e-9)
    }

    func testIoUOfHalfOverlapIsAboutHalf() {
        // 两个等面积矩形错开 1/3 边长：交集占总并集的一半。
        let a = QuadFixtures.rect(0, 0, 100, 100)
        let b = QuadFixtures.rect(100.0 / 3.0, 0, 100, 100)
        XCTAssertEqual(QuadGeometry.iou(a, b, gridSteps: 200), 0.5, accuracy: 0.02)
    }
}
