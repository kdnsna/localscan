import CoreGraphics
import Foundation
import XCTest
@testable import LocalScan

final class ScanDocumentTests: XCTestCase {
    private let size = CGSize(width: 1000, height: 1400)

    private func page(id: UUID = UUID(),
                      x: CGFloat = 100,
                      filter: PageFilter = .original) -> ScanPage {
        ScanPage(id: id,
                 quad: QuadFixtures.rect(x, 100, 600, 1000),
                 workingSize: size,
                 filter: filter)
    }

    func testAppendKeepsOrderAndRemoveIgnoresMissingID() {
        let a = page(id: UUID(), x: 10)
        let b = page(x: 20)
        var document = ScanDocument()

        document.append(a)
        document.append(b)
        XCTAssertEqual(document.pages.map(\.id), [a.id, b.id])

        document.remove(id: UUID())
        XCTAssertEqual(document.pages.count, 2)

        XCTAssertEqual(document.remove(id: a.id)?.id, a.id)
        XCTAssertEqual(document.pages.map(\.id), [b.id])
    }

    func testMoveReordersAndClampsDestination() {
        let a = page(x: 10)
        let b = page(x: 20)
        let c = page(x: 30)
        var document = ScanDocument(pages: [a, b, c])

        document.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(document.pages.map(\.id), [c.id, a.id, b.id])

        document.move(fromOffsets: IndexSet(integer: 0), toOffset: 99)
        XCTAssertEqual(document.pages.map(\.id), [a.id, b.id, c.id])

        // 越界来源安全忽略。
        document.move(fromOffsets: IndexSet(integer: 99), toOffset: 0)
        XCTAssertEqual(document.pages.map(\.id), [a.id, b.id, c.id])

        // 多选移动：与 SwiftUI 语义一致。
        let d = page(x: 40)
        var multi = ScanDocument(pages: [a, b, c, d])
        multi.move(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        XCTAssertEqual(multi.pages.map(\.id), [b.id, d.id, a.id, c.id])
        multi.move(fromOffsets: IndexSet([2, 3]), toOffset: 1)
        XCTAssertEqual(multi.pages.map(\.id), [b.id, a.id, c.id, d.id])
    }

    func testReplaceKeepsIDAndPositionForRetake() {
        let a = page(x: 10)
        let b = page(x: 20)
        let c = page(x: 30)
        var document = ScanDocument(pages: [a, b, c])

        let retake = ScanPage(quad: QuadFixtures.rect(500, 500, 300, 300),
                              workingSize: CGSize(width: 800, height: 1200),
                              filter: .original,
                              state: .processing)
        document.replace(id: b.id, with: retake)

        XCTAssertEqual(document.pages.count, 3)
        XCTAssertEqual(document.pages[1].id, b.id)
        XCTAssertEqual(document.pages[1].quad, retake.quad)
        XCTAssertEqual(document.pages[1].workingSize, retake.workingSize)
        XCTAssertEqual(document.pages[1].state, .processing)

        document.replace(id: UUID(), with: retake)
        XCTAssertEqual(document.pages.map(\.id), [a.id, b.id, c.id])
    }

    func testUpdateQuadAndFilterIgnoreMissingID() {
        let a = page(x: 10)
        let b = page(x: 20)
        var document = ScanDocument(pages: [a, b])

        let cropped = QuadFixtures.rect(150, 200, 500, 700)
        document.updateQuad(id: a.id, quad: cropped)
        XCTAssertEqual(document.page(id: a.id)?.quad, cropped)
        XCTAssertEqual(document.pages[1].quad, b.quad)

        document.updateQuad(id: UUID(), quad: cropped)
        XCTAssertEqual(document.pages.map(\.quad), [cropped, b.quad])

        document.updateFilter(id: b.id, filter: .blackWhite)
        XCTAssertEqual(document.page(id: b.id)?.filter, .blackWhite)
        document.updateFilter(id: UUID(), filter: .grayscale)
        XCTAssertEqual(document.pages.map(\.filter), [.original, .blackWhite])

        XCTAssertEqual(PageFilter.allCases,
                       [.original, .enhance, .grayscale, .blackWhite])
    }

    func testMovePageBeforeTargetForStripDrag() {
        let a = page(x: 10)
        let b = page(x: 20)
        let c = page(x: 30)
        var document = ScanDocument(pages: [a, b, c])

        document.movePage(id: c.id, before: a.id)
        XCTAssertEqual(document.pages.map(\.id), [c.id, a.id, b.id])

        document.movePage(id: c.id, before: b.id)
        XCTAssertEqual(document.pages.map(\.id), [a.id, c.id, b.id])

        document.movePage(id: UUID(), before: b.id)
        XCTAssertEqual(document.pages.map(\.id), [a.id, c.id, b.id])
    }
}
