import CoreGraphics
import XCTest
@testable import LocalScan

final class CornerEditorGeometryTests: XCTestCase {
    private let imageSize = CGSize(width: 1000, height: 500)

    func testFittedRectCentersAspectFit() {
        let rect = CornerEditorGeometry.fittedRect(
            imageSize: imageSize,
            viewSize: CGSize(width: 300, height: 300))
        XCTAssertEqual(rect.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(rect.minY, 75, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 300, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 150, accuracy: 1e-9)
    }

    func testViewAndImageMappingRoundTrip() {
        let viewSize = CGSize(width: 400, height: 300)
        let point = CGPoint(x: 750, y: 125)
        let viewPoint = CornerEditorGeometry.viewPoint(fromImage: point,
                                                       imageSize: imageSize,
                                                       viewSize: viewSize)
        let roundTrip = CornerEditorGeometry.imagePoint(fromView: viewPoint,
                                                        imageSize: imageSize,
                                                        viewSize: viewSize)
        XCTAssertEqual(roundTrip.x, point.x, accuracy: 1e-9)
        XCTAssertEqual(roundTrip.y, point.y, accuracy: 1e-9)
    }

    func testClampingToImageBounds() {
        let size = CGSize(width: 100, height: 80)
        XCTAssertEqual(CornerEditorGeometry.clamp(CGPoint(x: -5, y: 90), to: size),
                       CGPoint(x: 0, y: 80))
        XCTAssertEqual(CornerEditorGeometry.clamp(CGPoint(x: 30, y: 40), to: size),
                       CGPoint(x: 30, y: 40))
    }

    func testReplacingCornerKeepsOtherCorners() {
        let quad = QuadFixtures.rect(10, 10, 100, 100)
        let updated = CornerEditorGeometry.replacingCorner(
            quad, index: 2, with: CGPoint(x: 105, y: 105))
        XCTAssertEqual(updated.bottomRight, CGPoint(x: 105, y: 105))
        XCTAssertEqual(updated.topLeft, quad.topLeft)
        XCTAssertEqual(updated.topRight, quad.topRight)
        XCTAssertEqual(updated.bottomLeft, quad.bottomLeft)
    }
}
