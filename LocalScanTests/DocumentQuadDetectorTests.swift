import CoreGraphics
import XCTest
@testable import LocalScan

/// 拍后路径：Vision 归一化点 -> 工作图像素四边形 -> ProcessingQueue 拉正。
final class DocumentQuadDetectorTests: XCTestCase {
    private let size = CGSize(width: 600, height: 800)
    private let pixelQuad = Quad(topLeft: CGPoint(x: 120, y: 100),
                                 topRight: CGPoint(x: 480, y: 140),
                                 bottomRight: CGPoint(x: 450, y: 700),
                                 bottomLeft: CGPoint(x: 90, y: 660))

    /// 像素四边形 -> Vision 归一化点（左下原点）。
    private func visionPoints(for quad: Quad) -> [CGPoint] {
        quad.corners.map { CGPoint(x: $0.x / size.width, y: 1 - $0.y / size.height) }
    }

    func testVisionPointsAreScaledToPixels() throws {
        let quad = try XCTUnwrap(DocumentQuadDetector.pixelQuad(
            fromVisionPoints: visionPoints(for: pixelQuad), imageSize: size))
        XCTAssertLessThan(quad.maxCornerDisplacement(to: pixelQuad), 1e-6)
        XCTAssertGreaterThan(quad.area, 1000)
    }

    func testDegenerateAndConcaveQuadsAreRejectedInPixels() {
        let tiny = [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5001, y: 0.5),
                    CGPoint(x: 0.5001, y: 0.4999), CGPoint(x: 0.5, y: 0.4999)]
        XCTAssertNil(DocumentQuadDetector.pixelQuad(fromVisionPoints: tiny, imageSize: size))
        let concave = Quad(topLeft: CGPoint(x: 0, y: 0), topRight: CGPoint(x: 600, y: 0),
                           bottomRight: CGPoint(x: 600, y: 800),
                           bottomLeft: CGPoint(x: 300, y: 400))
        XCTAssertNil(DocumentQuadDetector.pixelQuad(
            fromVisionPoints: visionPoints(for: concave), imageSize: size))
        XCTAssertNil(DocumentQuadDetector.pixelQuad(
            fromVisionPoints: visionPoints(for: pixelQuad), imageSize: .zero))
    }

    func testQuadSmallerThanOnePercentIsRejected() {
        // 0.09 × 0.09 = 0.81% 画面面积，低于 1% 阈值。
        let small = Quad(topLeft: CGPoint(x: 0.40, y: 0.40),
                         topRight: CGPoint(x: 0.49, y: 0.40),
                         bottomRight: CGPoint(x: 0.49, y: 0.49),
                         bottomLeft: CGPoint(x: 0.40, y: 0.49))
        XCTAssertNil(DocumentQuadDetector.pixelQuad(
            fromVisionPoints: visionPoints(for: small), imageSize: size))
    }

    func testScaledQuadPassesProcessingQueue() async throws {
        let image = TestImages.page(size: size, quad: pixelQuad)
        let quad = try XCTUnwrap(DocumentQuadDetector.pixelQuad(
            fromVisionPoints: visionPoints(for: pixelQuad), imageSize: size))
        let result = try await ProcessingQueue().process(original: image,
                                                         working: image,
                                                         quad: quad,
                                                         workingSize: size)
        XCTAssertGreaterThan(result.image.width, 100)
        XCTAssertGreaterThan(result.image.height, 100)
    }

    /// 回归：未缩放的归一化框（旧 bug）会被拉正判为无效。
    func testUnscaledNormalizedQuadIsRejectedByCorrector() {
        let image = TestImages.page(size: size, quad: pixelQuad)
        let normalized = DocumentDetectorGeometry.quad(
            fromVisionPoints: visionPoints(for: pixelQuad))
        XCTAssertThrowsError(try PerspectiveCorrector().correct(image,
                                                                quad: normalized,
                                                                workingSize: size))
    }

    /// 真实 detect（检测到或回退内缩框）返回的必须是像素坐标，并能直接拉正。
    func testDetectReturnsPixelQuadThatCorrects() async throws {
        let image = TestImages.page(size: size, quad: pixelQuad)
        let quad = DocumentQuadDetector.detect(in: image)
        XCTAssertGreaterThan(quad.area, size.width * size.height * 0.05)
        for corner in quad.corners {
            XCTAssertTrue((-1...size.width + 1).contains(corner.x))
            XCTAssertTrue((-1...size.height + 1).contains(corner.y))
        }
        _ = try await ProcessingQueue().process(original: image, working: image,
                                                quad: quad, workingSize: size)
    }
}
