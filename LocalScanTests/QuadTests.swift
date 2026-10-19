import XCTest
@testable import LocalScan

final class QuadTests: XCTestCase {
    func testOrderingFromShuffledPoints() {
        let expected = QuadFixtures.rect(10, 20, 100, 50)
        let shuffled = [expected.bottomRight, expected.topRight,
                        expected.bottomLeft, expected.topLeft]
        XCTAssertEqual(Quad.ordered(from: shuffled), expected)
    }

    func testOrderingIsDeterministicForDiamondTie() {
        // 菱形上、左两点 x+y 相同；按 y 更小选上面的点作为 TL。
        let points = [CGPoint(x: 100, y: 50), CGPoint(x: 50, y: 100),
                      CGPoint(x: 0, y: 50), CGPoint(x: 50, y: 0)]
        let expected = Quad(topLeft: CGPoint(x: 50, y: 0),
                            topRight: CGPoint(x: 100, y: 50),
                            bottomRight: CGPoint(x: 50, y: 100),
                            bottomLeft: CGPoint(x: 0, y: 50))
        for shift in points.indices {
            let rotated = Array(points[shift...]) + Array(points[..<shift])
            XCTAssertEqual(Quad.ordered(from: rotated), expected)
        }
    }

    func testOrderingDegenerateInputsDoesNotCrash() {
        // 凹点集：只排序、不修复；调用方需检查 isConvex。
        let concave = Quad.ordered(from: [CGPoint(x: 0, y: 0),
                                          CGPoint(x: 100, y: 0),
                                          CGPoint(x: 100, y: 100),
                                          CGPoint(x: 50, y: 50)])
        XCTAssertFalse(concave.isConvex)
        XCTAssertGreaterThan(concave.area, 0)

        let collinear = Quad.ordered(from: [CGPoint(x: 0, y: 0),
                                            CGPoint(x: 10, y: 0),
                                            CGPoint(x: 20, y: 0),
                                            CGPoint(x: 30, y: 0)])
        XCTAssertEqual(collinear.area, 0, accuracy: 1e-9)
        XCTAssertFalse(collinear.isConvex)

        let nan = Quad.ordered(from: [CGPoint(x: CGFloat.nan, y: 0),
                                      CGPoint(x: 10, y: 0),
                                      CGPoint(x: 10, y: 10),
                                      CGPoint(x: 0, y: 10)])
        XCTAssertEqual(nan, .zero)
    }

    func testMappingRoundTrip() {
        let quad = QuadFixtures.rect(100, 50, 800, 600)
        let working = CGSize(width: 1024, height: 768)
        let original = CGSize(width: 4032, height: 3024)

        let mapped = quad.mapped(from: working, to: original)
        XCTAssertEqual(mapped.topLeft.x, CGFloat(100) * 4032 / 1024, accuracy: 1e-9)
        XCTAssertEqual(mapped.bottomRight.y, CGFloat(650) * 3024 / 768, accuracy: 1e-9)

        let roundTrip = mapped.mapped(from: original, to: working)
        for (actual, expected) in zip(roundTrip.corners, quad.corners) {
            XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9)
            XCTAssertEqual(actual.y, expected.y, accuracy: 1e-9)
        }
    }

    func testDefaultInsetIsSixPercentPerSide() {
        let quad = Quad.insetDefault(for: CGSize(width: 1000, height: 500))
        XCTAssertEqual(quad.topLeft, CGPoint(x: 60, y: 30))
        XCTAssertEqual(quad.topRight, CGPoint(x: 940, y: 30))
        XCTAssertEqual(quad.bottomRight, CGPoint(x: 940, y: 470))
        XCTAssertEqual(quad.bottomLeft, CGPoint(x: 60, y: 470))
        XCTAssertEqual(Quad.insetDefault(for: .zero), Quad.zero)
    }

    func testShoelaceAreaAndConvexity() {
        let rectangle = QuadFixtures.rect(0, 0, 100, 50)
        XCTAssertEqual(rectangle.area, 5000, accuracy: 1e-9)
        XCTAssertTrue(rectangle.isConvex)

        let bowTie = Quad(topLeft: CGPoint(x: 0, y: 0),
                          topRight: CGPoint(x: 100, y: 100),
                          bottomRight: CGPoint(x: 100, y: 0),
                          bottomLeft: CGPoint(x: 0, y: 100))
        XCTAssertFalse(bowTie.isConvex)
    }

    func testDiagonalAndCornerDisplacement() {
        let a = QuadFixtures.rect(0, 0, 300, 400)
        let b = QuadFixtures.rect(10, 0, 300, 400)
        XCTAssertEqual(a.diagonalLength, 500, accuracy: 1e-9)
        XCTAssertEqual(a.maxCornerDisplacement(to: b), 10, accuracy: 1e-9)
    }
}
