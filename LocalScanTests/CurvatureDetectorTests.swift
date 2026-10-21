import CoreGraphics
import XCTest
@testable import LocalScan

final class CurvatureDetectorTests: XCTestCase {
    private let size = CGSize(width: 480, height: 360)

    func testFlatSyntheticGridStaysFlat() {
        let image = TestImages.gridPage(size: size, amplitude: 0)
        let result = EdgeCurvatureDetector().detect(in: image)

        XCTAssertEqual(result.curvature, .flat)
        XCTAssertFalse(result.isCurved)
        XCTAssertLessThan(result.score, 0.008)
    }

    func testSyntheticCurvedGridIsClassifiedCurved() {
        let image = TestImages.gridPage(size: size, amplitude: 16)
        let result = EdgeCurvatureDetector().detect(in: image)

        XCTAssertEqual(result.curvature, .curved)
        XCTAssertTrue(result.isCurved)
        XCTAssertGreaterThan(result.score, 0.008)
    }

    /// 空白页没有可信长条，必须保守地留在平纸路径。
    func testBlankPageIsFlat() {
        let image = TestImages.page(size: size, quad: QuadFixtures.rect(0, 0, 480, 360),
                                    background: 1, foreground: 1)
        XCTAssertEqual(EdgeCurvatureDetector().detect(in: image).curvature, .flat)
    }
}
