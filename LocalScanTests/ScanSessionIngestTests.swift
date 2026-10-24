import CoreFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import LocalScan

/// 端到端：相机数据 -> ScanSession.ingest -> 解码/找边/拉正 -> .done。
///
/// 只使用 `TestImages.page(size:quad:)` 生成的合成图，并用 ImageIO 编码成
/// JPEG Data；不读取任何照片文件。
final class ScanSessionIngestTests: XCTestCase {
    private enum TestError: Error {
        case jpegEncodingFailed
        case timedOut
    }

    private let originalSize = CGSize(width: 1200, height: 1600)
    private var pageQuad: Quad {
        Quad(topLeft: CGPoint(x: 120, y: 140),
             topRight: CGPoint(x: 1080, y: 110),
             bottomRight: CGPoint(x: 1050, y: 1470),
             bottomLeft: CGPoint(x: 100, y: 1430))
    }

    @MainActor
    func testIngestCompletesWithPixelQuadAndCorrectedImage() async throws {
        let data = try jpegData(from: TestImages.page(size: originalSize,
                                                      quad: pageQuad))
        let session = ScanSession()
        session.ingest(capturedData: data)

        let page = try await waitForPage(in: session) {
            $0.state == .done || $0.state == .failed
        }

        XCTAssertEqual(session.pageCount, 1)
        XCTAssertEqual(page.state, .done, session.errorMessage ?? "处理失败")
        XCTAssertEqual(page.workingSize,
                       ImageSizing.workingSize(for: originalSize))

        let corrected = try XCTUnwrap(page.correctedImage)
        XCTAssertGreaterThan(corrected.width, 100)
        XCTAssertGreaterThan(corrected.height, 100)
        let aspect = Double(corrected.width) / Double(corrected.height)
        XCTAssertGreaterThan(aspect, 0.2)
        XCTAssertLessThan(aspect, 5)

        // 回归：quad 必须是工作图像素坐标，不是 0–1 归一化值。
        let workingArea = page.workingSize.width * page.workingSize.height
        XCTAssertGreaterThan(page.quad.area, workingArea * 0.05)
        for corner in page.quad.corners {
            XCTAssertTrue((-1...page.workingSize.width + 1).contains(corner.x),
                          "x 越界: \(corner)")
            XCTAssertTrue((-1...page.workingSize.height + 1).contains(corner.y),
                          "y 越界: \(corner)")
        }
    }

    @MainActor
    func testBackToBackIngestKeepsCaptureOrder() async throws {
        let firstData = try jpegData(from: TestImages.page(size: originalSize, quad: pageQuad))
        let secondData = try jpegData(from: TestImages.page(size: originalSize, quad: pageQuad))
        let session = ScanSession()

        session.ingest(capturedData: firstData)
        session.ingest(capturedData: secondData)
        let deadline = Date().addingTimeInterval(30)
        while session.pages.count < 2
                || session.pages.contains(where: { $0.state == .processing }) {
            if Date() >= deadline {
                XCTFail("连拍处理超时")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(session.pages.map(\.originalData), [firstData, secondData])
        XCTAssertTrue(session.pages.allSatisfy { $0.state == .done },
                      session.errorMessage ?? "连拍处理失败")
    }

    @MainActor
    func testRetakeReplacesPageWithoutAddingAnother() async throws {
        let firstData = try jpegData(from: TestImages.page(size: originalSize,
                                                           quad: pageQuad))
        let session = ScanSession()
        session.ingest(capturedData: firstData)

        let firstPage = try await waitForPage(in: session) {
            $0.state == .done || $0.state == .failed
        }
        XCTAssertEqual(firstPage.state, .done, session.errorMessage ?? "首次处理失败")
        let pageID = firstPage.id

        session.beginRetake(pageID: pageID)
        XCTAssertEqual(session.pendingRetakePageID, pageID)

        let retakeQuad = Quad(topLeft: CGPoint(x: 160, y: 180),
                              topRight: CGPoint(x: 1020, y: 150),
                              bottomRight: CGPoint(x: 1000, y: 1420),
                              bottomLeft: CGPoint(x: 140, y: 1380))
        let secondData = try jpegData(from: TestImages.page(
            size: CGSize(width: 1000, height: 1400),
            quad: retakeQuad))
        session.ingest(capturedData: secondData)

        let retakenPage = try await waitForPage(in: session) {
            $0.id == pageID
                && $0.originalData == secondData
                && ($0.state == .done || $0.state == .failed)
        }

        XCTAssertEqual(session.pageCount, 1)
        XCTAssertEqual(retakenPage.id, pageID)
        XCTAssertEqual(retakenPage.state, .done, session.errorMessage ?? "重拍处理失败")
        XCTAssertNotNil(retakenPage.correctedImage)
    }

    @MainActor
    private func waitForPage(in session: ScanSession,
                             timeout: TimeInterval = 20,
                             where predicate: (ScanPage) -> Bool) async throws -> ScanPage {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let page = session.pages.first(where: predicate) {
                return page
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("等待页面处理超时（\(Int(timeout)) 秒），当前页数 \(session.pageCount)")
        throw TestError.timedOut
    }

    private func jpegData(from image: CGImage) throws -> Data {
        guard let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TestError.jpegEncodingFailed
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.jpegEncodingFailed
        }
        return data as Data
    }
}
