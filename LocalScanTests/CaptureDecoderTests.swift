import CoreFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import LocalScan

final class CaptureDecoderTests: XCTestCase {
    private enum TestError: Error {
        case encodingFailed
    }

    /// EXIF 6（.right）表示存储像素需要顺时针转 90° 才是正方向：
    /// 原始左上角的内容摆正后出现在右上角，宽高互换。
    func testOrientationRightSwapsDimensionsAndMovesMarkerToTopRight() throws {
        let rawSize = CGSize(width: 400, height: 300)
        let raw = image(size: rawSize,
                        marker: CGRect(x: 0, y: 0, width: 100, height: 100))
        let data = try jpegData(from: raw, orientation: .right)

        let decoded = try CaptureDecoder().decode(data)

        XCTAssertEqual(decoded.original.width, 300)
        XCTAssertEqual(decoded.original.height, 400)
        XCTAssertEqual(decoded.working.width, 300)
        XCTAssertEqual(decoded.working.height, 400)
        XCTAssertEqual(decoded.workingSize, CGSize(width: 300, height: 400))

        // 原左上角 -> 摆正后右上角。
        XCTAssertLessThan(TestImages.luminance(decoded.original,
                                               x: decoded.original.width - 40,
                                               y: 40), 60)
        XCTAssertGreaterThan(TestImages.luminance(decoded.original, x: 40, y: 40), 200)
        XCTAssertGreaterThan(TestImages.luminance(decoded.original,
                                                  x: 40,
                                                  y: decoded.original.height - 40), 200)
        XCTAssertGreaterThan(TestImages.luminance(decoded.original,
                                                  x: decoded.original.width - 40,
                                                  y: decoded.original.height - 40), 200)
    }

    func testOrientationUpKeepsDimensionsAndWorkingSizeBounded() throws {
        let rawSize = CGSize(width: 2400, height: 1800)
        let raw = image(size: rawSize,
                        marker: CGRect(x: 0, y: 0, width: 300, height: 300))
        let data = try jpegData(from: raw, orientation: .up)

        let decoded = try CaptureDecoder().decode(data)

        XCTAssertEqual(decoded.original.width, 2400)
        XCTAssertEqual(decoded.original.height, 1800)
        XCTAssertEqual(decoded.workingSize,
                       ImageSizing.workingSize(
                        for: CGSize(width: 2400, height: 1800)))
        XCTAssertEqual(decoded.workingSize, CGSize(width: 2048, height: 1536))
        XCTAssertEqual(decoded.working.width, 2048)
        XCTAssertEqual(decoded.working.height, 1536)
        XCTAssertLessThanOrEqual(max(decoded.working.width, decoded.working.height), 2048)
        XCTAssertEqual(Double(decoded.working.width) / Double(decoded.working.height),
                       4.0 / 3.0,
                       accuracy: 0.01)

        // orientation 1 不旋转：左上角标记仍在左上角。
        XCTAssertLessThan(TestImages.luminance(decoded.original, x: 40, y: 40), 60)
        XCTAssertLessThan(TestImages.luminance(decoded.working, x: 40, y: 40), 60)
        XCTAssertGreaterThan(TestImages.luminance(decoded.original,
                                                  x: decoded.original.width - 40,
                                                  y: 40), 200)
    }

    /// 白底，可选在左上角（y 向下）画一个黑色方块。
    private func image(size: CGSize, marker: CGRect?) -> CGImage {
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

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0,
                            width: CGFloat(width), height: CGFloat(height)))
        if let marker {
            context.saveGState()
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(marker)
            context.restoreGState()
        }

        guard let result = context.makeImage() else {
            fatalError("无法生成测试图像")
        }
        return result
    }

    private func jpegData(from image: CGImage,
                          orientation: CGImagePropertyOrientation) throws -> Data {
        guard let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TestError.encodingFailed
        }
        let properties: [String: Any] = [
            kCGImagePropertyOrientation as String: orientation.rawValue,
            kCGImageDestinationLossyCompressionQuality as String: 0.95,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.encodingFailed
        }
        return data as Data
    }
}
