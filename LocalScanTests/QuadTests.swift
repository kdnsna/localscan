import XCTest
@testable import LocalScan

final class QuadTests: XCTestCase {
    func testOrderingFromShuffledPoints() {
        let expected = QuadFixtures.rect(10, 20, 100, 50)
        let shuffled = [expected.bottomRight, expected.topRight,
                        expected.bottomLeft, expected.topLeft]
        XCTAssertEqual(Quad.ordered(from: shuffled), expected)
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
