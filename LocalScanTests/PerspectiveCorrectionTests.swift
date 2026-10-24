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

    func testOutputPixelBudgetRejectsBeforeRendering() {
        let corrector = PerspectiveCorrector(maximumOutputPixelCount: 1_000)
        XCTAssertThrowsError(try corrector.correct(sourceImage(),
                                                   quad: quad,
                                                   workingSize: size)) { error in
            XCTAssertEqual(error as? PerspectiveCorrectionError,
                           PerspectiveCorrectionError.outputTooLarge)
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

    /// Core Image 使用左下原点；如果 y 方向映射错了，页面左上角的黑块会跑到左下角。
    func testCoreImageYAxisKeepsTopLeftMarkerAtTopLeft() throws {
        let output = try PerspectiveCorrector().correct(markedPageImage(),
                                                        quad: quad,
                                                        workingSize: size)
        let width = output.width
        let height = output.height

        XCTAssertLessThan(TestImages.luminance(output, x: 40, y: 40), 60)
        XCTAssertGreaterThan(TestImages.luminance(output, x: width - 40, y: 40), 200)
        XCTAssertGreaterThan(TestImages.luminance(output, x: 40, y: height - 40), 200)
        XCTAssertGreaterThan(TestImages.luminance(output,
                                                  x: width - 40,
                                                  y: height - 40), 200)
    }

    /// 黑色背景上画白色页面，再在页面左上角附近画一个黑色小方块。
    private func markedPageImage(markerSide: CGFloat = 80) -> CGImage {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("无法创建测试用位图上下文")
        }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0,
                            width: CGFloat(width), height: CGFloat(height)))
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        let path = CGMutablePath()
        path.move(to: quad.topLeft)
        path.addLine(to: quad.topRight)
        path.addLine(to: quad.bottomRight)
        path.addLine(to: quad.bottomLeft)
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: quad.topLeft.x + 20,
                            y: quad.topLeft.y + 20,
                            width: markerSide,
                            height: markerSide))
        context.restoreGState()

        guard let image = context.makeImage() else {
            fatalError("无法生成测试图像")
        }
        return image
    }
}
