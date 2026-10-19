import CoreGraphics
import XCTest
@testable import LocalScan

final class PerspectiveCorrectionTests: XCTestCase {
    private let size = CGSize(width: 600, height: 800)
    private var quad: Quad {
        Quad(topLeft: CGPoint(x: 120, y: 100),
             topRight: CGPoint(x: 480, y: 140),
             bottomRight: CGPoint(x: 450, y: 700),
             bottomLeft: CGPoint(x: 90, y: 660))
    }

    private func sourceImage() -> CGImage {
        TestImages.page(size: size, quad: quad)
    }

    func testOutputSizeMatchesGeometryAndCenterIsWhite() throws {
        let output = try PerspectiveCorrector().correct(sourceImage(),
                                                        quad: quad,
                                                        workingSize: size)
        let expected = QuadGeometry.outputSize(for: quad)
        XCTAssertEqual(CGFloat(output.width), expected.width, accuracy: 2)
        XCTAssertEqual(CGFloat(output.height), expected.height, accuracy: 2)
        XCTAssertGreaterThan(TestImages.luminance(output,
                                                  x: output.width / 2,
                                                  y: output.height / 2), 220)
    }

    func testInvalidQuadsThrow() {
        let corrector = PerspectiveCorrector()
        let image = sourceImage()
        let concave = Quad(topLeft: CGPoint(x: 0, y: 0),
                           topRight: CGPoint(x: 100, y: 0),
                           bottomRight: CGPoint(x: 100, y: 100),
                           bottomLeft: CGPoint(x: 50, y: 50))
        let nan = Quad(topLeft: CGPoint(x: CGFloat.nan, y: 0),
                       topRight: CGPoint(x: 100, y: 0),
                       bottomRight: CGPoint(x: 100, y: 100),
                       bottomLeft: CGPoint(x: 0, y: 100))
        let tiny = QuadFixtures.rect(10, 10, 0.5, 0.5)

        for invalid in [concave, nan, tiny] {
            XCTAssertThrowsError(try corrector.correct(image,
                                                       quad: invalid,
                                                       workingSize: size)) { error in
                XCTAssertEqual(error as? PerspectiveCorrectionError,
                               PerspectiveCorrectionError.invalidQuad)
            }
        }
    }

    func testQueueProcessesFullResolutionPage() async throws {
        let image = sourceImage()
        let result = try await ProcessingQueue().process(original: image,
                                                        working: image,
                                                        quad: quad,
                                                        workingSize: size)
        let expected = QuadGeometry.outputSize(for: quad)
        XCTAssertEqual(CGFloat(result.image.width), expected.width, accuracy: 2)
        XCTAssertEqual(CGFloat(result.image.height), expected.height, accuracy: 2)
        XCTAssertGreaterThan(TestImages.luminance(result.image,
                                                  x: result.image.width / 2,
                                                  y: result.image.height / 2), 220)
    }
}
