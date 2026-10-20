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

    func testDraggingRejectsNonConvexPosition() {
        let quad = Quad.insetDefault(for: imageSize)
        // 把左上角拖到右下角内侧 -> 凹/自交，应被拒绝。
        let rejected = CornerEditorGeometry.dragging(quad, index: 0,
                                                     to: CGPoint(x: 800, y: 400),
                                                     imageSize: imageSize)
        XCTAssertEqual(rejected, quad)
        let moved = CornerEditorGeometry.dragging(quad, index: 0,
                                                  to: CGPoint(x: 10, y: 10),
                                                  imageSize: imageSize)
        XCTAssertEqual(moved.topLeft, CGPoint(x: 10, y: 10))
    }

    func testConfirmableRequiresConvexNonDegenerateQuad() {
        XCTAssertTrue(CornerEditorGeometry.isConfirmable(Quad.insetDefault(for: imageSize),
                                                         imageSize: imageSize))
        let concave = Quad(topLeft: CGPoint(x: 0, y: 0), topRight: CGPoint(x: 1000, y: 0),
                           bottomRight: CGPoint(x: 1000, y: 500),
                           bottomLeft: CGPoint(x: 500, y: 250))
        XCTAssertFalse(CornerEditorGeometry.isConfirmable(concave, imageSize: imageSize))
        XCTAssertFalse(CornerEditorGeometry.isConfirmable(.zero, imageSize: imageSize))
    }
}
