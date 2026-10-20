import CoreGraphics
import XCTest
@testable import LocalScan

final class PageFilterRendererTests: XCTestCase {
    private var source: CGImage {
        TestImages.page(size: CGSize(width: 240, height: 320),
                        quad: QuadFixtures.rect(20, 20, 200, 280))
    }

    func testOriginalIsPixelIdenticalToInput() {
        let input = source
        guard let output = PageFilterRenderer.shared.apply(.original, to: input) else {
            return XCTFail("原图滤镜不应失败")
        }
        XCTAssertEqual(TestImages.rgbaBytes(output),
                       TestImages.rgbaBytes(input))
    }

    func testFiltersAreDeterministic() {
        let input = source
        for filter in [PageFilter.grayscale, .blackWhite] {
            guard let first = PageFilterRenderer.shared.apply(filter, to: input),
                  let second = PageFilterRenderer.shared.apply(filter, to: input) else {
                return XCTFail("滤镜 \(filter) 渲染失败")
            }
            XCTAssertEqual(TestImages.rgbaBytes(first),
                           TestImages.rgbaBytes(second),
                           "同一输入两次输出必须逐字节一致")
        }
    }
}
