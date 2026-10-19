import XCTest
@testable import LocalScan

final class ImageSizingTests: XCTestCase {
    func testDownscales12MPPortraitToLongSide2048() {
        let size = ImageSizing.workingSize(for: CGSize(width: 3024, height: 4032))
        XCTAssertEqual(size.height, 2048)
        XCTAssertEqual(size.width, 1536)
    }

    func testDoesNotUpscaleSmallImages() {
        let original = CGSize(width: 800, height: 600)
        XCTAssertEqual(ImageSizing.workingSize(for: original), original)
    }

    func testZeroSizeReturnsZero() {
        XCTAssertEqual(ImageSizing.workingSize(for: .zero), .zero)
    }

    func testDefaultsStayInsideAgreedRanges() {
        XCTAssertTrue(ScanDefaults.workingLongSideRange.contains(ScanDefaults.workingLongSide))
        XCTAssertTrue(ScanDefaults.jpegQualityRange.contains(ScanDefaults.jpegQuality))
    }
}
