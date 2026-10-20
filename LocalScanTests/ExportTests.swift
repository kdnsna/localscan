import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import LocalScan

private func syntheticImage(width: CGFloat = 600, height: CGFloat = 800) -> CGImage {
    TestImages.page(size: CGSize(width: width, height: height),
                    quad: QuadFixtures.rect(0, 0, width, height))
}

final class ImageExporterTests: XCTestCase {
    func testJPEGEncodeProducesJPEGData() throws {
        let data = try ImageExporter.encode(syntheticImage(), as: .jpeg)
        XCTAssertFalse(data.isEmpty)

        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?,
                       UTType.jpeg.identifier)
    }

    func testHEICEncodeProducesHEICDataOrSkipsWhenUnavailable() throws {
        let data: Data
        do {
            data = try ImageExporter.encode(syntheticImage(), as: .heic)
        } catch ImageExportError.destinationUnavailable {
            throw XCTSkip("当前模拟器没有 HEIC 编码器")
        }
        XCTAssertFalse(data.isEmpty)

        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?,
                       UTType.heic.identifier)
    }

    func testQualityIsClampedToDefaultsRange() {
        XCTAssertEqual(ImageExporter.clampedQuality(0),
                       ScanDefaults.jpegQualityRange.lowerBound)
        XCTAssertEqual(ImageExporter.clampedQuality(1),
                       ScanDefaults.jpegQualityRange.upperBound)
        XCTAssertEqual(ImageExporter.clampedQuality(ScanDefaults.jpegQuality),
                       ScanDefaults.jpegQuality)
        XCTAssertEqual(ImageExporter.clampedQuality(.nan),
                       ScanDefaults.jpegQuality)
    }

    func testTemporaryJPEGFileUsesScanSequenceName() throws {
        let url = try ImageExporter.writeTemporaryFile(syntheticImage(),
                                                       format: .jpeg,
                                                       index: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.lastPathComponent, "Scan-003.jpg")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL,
                       ExportFileStore.directory.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}

final class PDFAssemblerTests: XCTestCase {
    func testPageSizeFromPixelsAt200DPI() {
        let size = PDFAssembler.pageSize(
            forPixelSize: CGSize(width: 1654, height: 2339),
            dpi: 200)
        XCTAssertEqual(size.width, 595.44, accuracy: 0.05)
        XCTAssertEqual(size.height, 842.04, accuracy: 0.05)
    }

    func testPageSizeClampsDPIAndRejectsInvalidPixels() {
        let pixels = CGSize(width: 1000, height: 1400)
        XCTAssertEqual(PDFAssembler.pageSize(forPixelSize: pixels, dpi: 100),
                       PDFAssembler.pageSize(forPixelSize: pixels, dpi: 200))
        XCTAssertEqual(PDFAssembler.pageSize(forPixelSize: pixels, dpi: 500),
                       PDFAssembler.pageSize(forPixelSize: pixels, dpi: 300))
        XCTAssertEqual(PDFAssembler.pageSize(forPixelSize: .zero), .zero)
    }

    func testThreePagePDFHasThreePages() throws {
        let images = (0..<3).map { _ in syntheticImage(width: 400, height: 600) }
        let data = try PDFAssembler.makePDF(from: images)
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertEqual(document.pageCount, 3)
        let expected = PDFAssembler.pageSize(
            forPixelSize: CGSize(width: 400, height: 600))
        let bounds = try XCTUnwrap(document.page(at: 0)?.bounds(for: .mediaBox))
        XCTAssertEqual(bounds.width, expected.width, accuracy: 0.5)
        XCTAssertEqual(bounds.height, expected.height, accuracy: 0.5)
    }
}

final class ExportFileStoreTests: XCTestCase {
    func testRemoveDeletesOnlyThisExportsFiles() throws {
        let a = try ImageExporter.writeTemporaryFile(syntheticImage(), format: .jpeg, index: 7)
        let b = try PDFAssembler.writeTemporaryFile(from: [syntheticImage()], index: 8)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-an-export-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: outside)
        defer {
            try? FileManager.default.removeItem(at: outside)
            ExportFileStore.removeAll()
        }

        ExportFileStore.remove([a, outside])
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testRemoveAllClearsStaleExports() throws {
        let a = try ImageExporter.writeTemporaryFile(syntheticImage(), format: .jpeg, index: 1)
        let b = try PDFAssembler.writeTemporaryFile(from: [syntheticImage()], index: 2)
        ExportFileStore.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))
        let left = try FileManager.default.contentsOfDirectory(
            atPath: ExportFileStore.directory.path)
        XCTAssertTrue(left.isEmpty)
    }
}
