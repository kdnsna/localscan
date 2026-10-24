import CoreGraphics
import XCTest
@testable import LocalScan

final class PageFilterRendererTests: XCTestCase {
    private var source: CGImage {
        TestImages.page(size: CGSize(width: 240, height: 320),
                        quad: QuadFixtures.rect(20, 20, 200, 280))
    }

    func testOriginalReturnsTheInputInstance() {
        let input = source
        guard let output = PageFilterRenderer.shared.apply(.original, to: input) else {
            return XCTFail("原图滤镜不应失败")
        }
        XCTAssertTrue(output === input, "原图必须返回同一个 CGImage 实例")
        XCTAssertEqual(TestImages.rgbaBytes(output),
                       TestImages.rgbaBytes(input))
    }

    func testEnhanceIsDeterministic() {
        let input = TestImages.lightingGradient(size: CGSize(width: 240, height: 320))
        guard let first = PageFilterRenderer.shared.apply(.enhance, to: input),
              let second = PageFilterRenderer.shared.apply(.enhance, to: input) else {
            return XCTFail("增强滤镜渲染失败")
        }
        XCTAssertEqual(TestImages.rgbaBytes(first),
                       TestImages.rgbaBytes(second),
                       "同一输入两次增强输出必须逐字节一致")
    }

    func testEnhanceIsNotNoOpOnLightingGradient() {
        let input = TestImages.lightingGradient(size: CGSize(width: 240, height: 320))
        guard let original = PageFilterRenderer.shared.apply(.original, to: input),
              let enhanced = PageFilterRenderer.shared.apply(.enhance, to: input) else {
            return XCTFail("增强滤镜渲染失败")
        }
        XCTAssertEqual(enhanced.width, input.width)
        XCTAssertEqual(enhanced.height, input.height)
        XCTAssertNotEqual(TestImages.rgbaBytes(original),
                          TestImages.rgbaBytes(enhanced),
                          "有明暗渐变时增强不能是空操作")
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

    func testBlackWhiteNormalizesShadowAndProducesOnlyBlackAndWhite() throws {
        let input = shadowedPage()
        let output = try XCTUnwrap(PageFilterRenderer.shared.apply(.blackWhite, to: input))

        XCTAssertGreaterThan(TestImages.luminance(output, x: 40, y: 30), 240)
        XCTAssertGreaterThan(TestImages.luminance(output, x: 200, y: 30), 240)
        XCTAssertLessThan(TestImages.luminance(output, x: 60, y: 80), 10)
        XCTAssertLessThan(TestImages.luminance(output, x: 180, y: 80), 10)

        let bytes = TestImages.rgbaBytes(output)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            XCTAssertEqual(bytes[index], bytes[index + 1])
            XCTAssertEqual(bytes[index], bytes[index + 2])
            XCTAssertTrue(bytes[index] == 0 || bytes[index] == 255)
        }
    }

    private func shadowedPage() -> CGImage {
        let size = CGSize(width: 240, height: 160)
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.28, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: size.height))
        context.setFillColor(CGColor(gray: 0.8, alpha: 1))
        context.fill(CGRect(x: 120, y: 0, width: 120, height: size.height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 50, y: 70, width: 20, height: 20))
        context.fill(CGRect(x: 170, y: 70, width: 20, height: 20))
        return context.makeImage()!
    }
}
