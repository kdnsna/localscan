import CoreGraphics
import XCTest
@testable import LocalScan

final class DocumentDetectorGeometryTests: XCTestCase {
    func testVisionPointsFlipYAndKeepCornerOrder() {
        // 输入顺序是 Vision 的 TL、TR、BR、BL；y 向上，输出改为左上原点、y 向下。
        let quad = DocumentDetectorGeometry.quad(fromVisionPoints: [
            CGPoint(x: 0.1, y: 0.9), CGPoint(x: 0.9, y: 0.8),
            CGPoint(x: 0.8, y: 0.2), CGPoint(x: 0.2, y: 0.1),
        ])
        XCTAssertEqual(quad.topLeft.x, 0.1, accuracy: 1e-9)
        XCTAssertEqual(quad.topLeft.y, 0.1, accuracy: 1e-9)
        XCTAssertEqual(quad.topRight.x, 0.9, accuracy: 1e-9)
        XCTAssertEqual(quad.topRight.y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(quad.bottomRight.x, 0.8, accuracy: 1e-9)
        XCTAssertEqual(quad.bottomRight.y, 0.8, accuracy: 1e-9)
        XCTAssertEqual(quad.bottomLeft.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(quad.bottomLeft.y, 0.9, accuracy: 1e-9)
    }

    func testRectangleStaysTopLeftFirstAndConvex() {
        // 用二进制可精确表示的 0.125 / 0.875，避免 1 - 0.9 的浮点误差。
        let quad = DocumentDetectorGeometry.quad(fromVisionPoints: [
            CGPoint(x: 0.125, y: 0.875), CGPoint(x: 0.875, y: 0.875),
            CGPoint(x: 0.875, y: 0.125), CGPoint(x: 0.125, y: 0.125),
        ])
        XCTAssertEqual(quad, Quad(topLeft: CGPoint(x: 0.125, y: 0.125),
                                  topRight: CGPoint(x: 0.875, y: 0.125),
                                  bottomRight: CGPoint(x: 0.875, y: 0.875),
                                  bottomLeft: CGPoint(x: 0.125, y: 0.875)))
        XCTAssertTrue(quad.isConvex)
        XCTAssertEqual(quad.area, 0.5625, accuracy: 1e-9)
    }
}

final class CameraPreviewGeometryTests: XCTestCase {
    func testSameAspectRatioIsUniformScaleWithoutCrop() {
        let point = CameraPreviewGeometry.viewPoint(
            fromNormalized: CGPoint(x: 0.25, y: 0.75),
            frameSize: CGSize(width: 1000, height: 2000),
            viewSize: CGSize(width: 500, height: 1000))
        XCTAssertEqual(point.x, 125, accuracy: 1e-9)
        XCTAssertEqual(point.y, 750, accuracy: 1e-9)
    }

    func testAspectFillCropsTopAndBottomWhenViewIsWider() {
        let frame = CGSize(width: 1000, height: 2000)
        let view = CGSize(width: 600, height: 600)
        let topLeft = CameraPreviewGeometry.viewPoint(
            fromNormalized: .zero, frameSize: frame, viewSize: view)
        XCTAssertEqual(topLeft.x, 0, accuracy: 1e-9)
        XCTAssertEqual(topLeft.y, -300, accuracy: 1e-9)

        let center = CameraPreviewGeometry.viewPoint(
            fromNormalized: CGPoint(x: 0.5, y: 0.5), frameSize: frame, viewSize: view)
        XCTAssertEqual(center.x, 300, accuracy: 1e-9)
        XCTAssertEqual(center.y, 300, accuracy: 1e-9)
    }

    func testAspectFillCropsLeftAndRightWhenViewIsTaller() {
        let frame = CGSize(width: 1000, height: 1000)
        let view = CGSize(width: 400, height: 800)
        let center = CameraPreviewGeometry.viewPoint(
            fromNormalized: CGPoint(x: 0.5, y: 0.5), frameSize: frame, viewSize: view)
        XCTAssertEqual(center.x, 200, accuracy: 1e-9)
        XCTAssertEqual(center.y, 400, accuracy: 1e-9)

        let bottomRight = CameraPreviewGeometry.viewPoint(
            fromNormalized: CGPoint(x: 1, y: 1), frameSize: frame, viewSize: view)
        XCTAssertEqual(bottomRight.x, 600, accuracy: 1e-9)
        XCTAssertEqual(bottomRight.y, 800, accuracy: 1e-9)
    }

    func testQuadMappingPreservesCornerLabels() {
        let quad = Quad(topLeft: CGPoint(x: 0.25, y: 0.25),
                        topRight: CGPoint(x: 0.75, y: 0.125),
                        bottomRight: CGPoint(x: 0.5, y: 0.75),
                        bottomLeft: CGPoint(x: 0.25, y: 0.5))
        let mapped = CameraPreviewGeometry.viewQuad(
            from: quad,
            frameSize: CGSize(width: 1000, height: 2000),
            viewSize: CGSize(width: 500, height: 1000))
        XCTAssertEqual(mapped.topLeft, CGPoint(x: 125, y: 250))
        XCTAssertEqual(mapped.topRight, CGPoint(x: 375, y: 125))
        XCTAssertEqual(mapped.bottomRight, CGPoint(x: 250, y: 750))
        XCTAssertEqual(mapped.bottomLeft, CGPoint(x: 125, y: 500))
    }
}
