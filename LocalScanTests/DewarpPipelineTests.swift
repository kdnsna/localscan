import CoreGraphics
import XCTest
@testable import LocalScan

final class DewarpPipelineTests: XCTestCase {
    private let size = CGSize(width: 480, height: 360)
    private var fullQuad: Quad { QuadFixtures.rect(0, 0, size.width, size.height) }

    private final class RecordingDewarper: Dewarping {
        private(set) var calls = 0
        let isAvailable = true

        func dewarp(_ image: CGImage) -> CGImage? {
            calls += 1
            return image
        }
    }

    func testFlatSyntheticPageStaysOnFlatPath() async throws {
        let image = TestImages.gridPage(size: size, amplitude: 0)
        let dewarper = RecordingDewarper()
        let queue = ProcessingQueue(curvatureDetector: EdgeCurvatureDetector(),
                                    dewarper: dewarper)

        let result = try await queue.process(original: image,
                                             working: image,
                                             quad: fullQuad,
                                             workingSize: size)

        XCTAssertEqual(result.curvature.curvature, .flat)
        XCTAssertEqual(dewarper.calls, 0, "平纸路径只能跑廉价判定，不能启动展平")
        XCTAssertEqual(CGFloat(result.image.width), size.width, accuracy: 2)
        XCTAssertEqual(CGFloat(result.image.height), size.height, accuracy: 2)
    }

    func testCurvedSyntheticPageRunsDewarper() async throws {
        let image = TestImages.gridPage(size: size, amplitude: 16)
        let dewarper = RecordingDewarper()
        let queue = ProcessingQueue(curvatureDetector: EdgeCurvatureDetector(),
                                    dewarper: dewarper)

        let result = try await queue.process(original: image,
                                             working: image,
                                             quad: fullQuad,
                                             workingSize: size)

        XCTAssertEqual(result.curvature.curvature, .curved)
        XCTAssertEqual(dewarper.calls, 1)
    }

    /// 展平之后仍然可以正常应用经典「增强」滤镜。
    func testEnhanceStillRendersAfterDefaultPipeline() async throws {
        let image = TestImages.gridPage(size: size, amplitude: 16)
        let result = try await ProcessingQueue().process(original: image,
                                                         working: image,
                                                         quad: fullQuad,
                                                         workingSize: size)
        let enhanced = try XCTUnwrap(PageFilterRenderer.shared.apply(.enhance,
                                                                     to: result.image))
        XCTAssertEqual(enhanced.width, result.image.width)
        XCTAssertEqual(enhanced.height, result.image.height)
        XCTAssertGreaterThan(TestImages.luminance(enhanced,
                                                  x: 40,
                                                  y: 40), 120)
    }

    func testDisabledUVDocSafelyFallsBack() {
        let dewarper = UVDocDewarper(bundle: .main, featureFlagEnabled: false)
        XCTAssertFalse(dewarper.isAvailable)
        XCTAssertNil(dewarper.dewarp(TestImages.gridPage(size: size)))
    }

    func testManualCorrectAlsoRunsCurvatureDetection() async throws {
        let image = TestImages.gridPage(size: size, amplitude: 16)
        let dewarper = RecordingDewarper()
        let queue = ProcessingQueue(curvatureDetector: EdgeCurvatureDetector(),
                                    dewarper: dewarper)
        _ = try await queue.correct(original: image,
                                    quad: fullQuad,
                                    workingSize: size)
        XCTAssertEqual(dewarper.calls, 1)
    }
}
