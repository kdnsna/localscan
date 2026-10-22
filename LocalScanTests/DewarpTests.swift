import CoreGraphics
import XCTest
@testable import LocalScan

final class DewarpTests: XCTestCase {
    private let size = CGSize(width: 400, height: 300)

    func testIdentityGridReturnsSameImageWithinTolerance() throws {
        let input = TestImages.markerPage(size: size,
                                          center: CGPoint(x: 120, y: 90),
                                          markerSide: 30)
        let output = try XCTUnwrap(GridDewarper(grid: .identity).dewarp(input))

        XCTAssertEqual(output.width, input.width)
        XCTAssertEqual(output.height, input.height)
        let difference = meanAbsoluteDifference(TestImages.rgbaBytes(input),
                                                TestImages.rgbaBytes(output))
        XCTAssertLessThan(difference, 2.0,
                          "恒等控制网格只允许重采样误差，不应真正移动内容")
    }

    func testUniformHorizontalDisplacementMovesMarkerRight() throws {
        // 400 px 宽，dx = 0.1 => 内容右移 40 px。
        let input = TestImages.markerPage(size: size,
                                          center: CGPoint(x: 200, y: 150),
                                          markerSide: 40)
        let grid = DewarpGrid.uniform(dx: 0.1, dy: 0)
        let output = try XCTUnwrap(GridDewarper(grid: grid).dewarp(input))

        XCTAssertLessThan(TestImages.luminance(output, x: 240, y: 150), 80,
                          "标记应移动到原来的右侧 40 px 处")
        XCTAssertGreaterThan(TestImages.luminance(output, x: 200, y: 150), 180,
                             "原位置应重新变成白底")
    }

    func testUniformVerticalDisplacementMovesMarkerDown() throws {
        // 300 px 高，dy = 0.1 => 内容下移 30 px。
        let input = TestImages.markerPage(size: size,
                                          center: CGPoint(x: 200, y: 150),
                                          markerSide: 40)
        let grid = DewarpGrid.uniform(dx: 0, dy: 0.1)
        let output = try XCTUnwrap(GridDewarper(grid: grid).dewarp(input))

        XCTAssertLessThan(TestImages.luminance(output, x: 200, y: 180), 80,
                          "标记应移动到原来的下方 30 px 处")
        XCTAssertGreaterThan(TestImages.luminance(output, x: 200, y: 150), 180,
                             "原位置应重新变成白底")
    }

    func testGridWarpIsDeterministic() throws {
        let input = TestImages.gridPage(size: size, amplitude: 12)
        let dewarper = GridDewarper(grid: DewarpGrid.uniform(dx: 0.02, dy: -0.01))
        let first = try XCTUnwrap(dewarper.dewarp(input))
        let second = try XCTUnwrap(dewarper.dewarp(input))

        XCTAssertEqual(TestImages.rgbaBytes(first), TestImages.rgbaBytes(second),
                       "同一输入两次网格展平必须逐字节一致")
    }

    func testInvalidGridReportsUnavailable() throws {
        let invalid = DewarpGrid(columns: 3, rows: 3,
                                 offsets: Array(repeating: .zero, count: 4))
        XCTAssertFalse(invalid.isValid)
        let dewarper = GridDewarper(grid: invalid)
        XCTAssertFalse(dewarper.isAvailable)
        XCTAssertNil(dewarper.dewarp(TestImages.markerPage(size: size,
                                                           center: CGPoint(x: 100, y: 100))))
    }

    func testUVDocStubIsUnavailableWhenFeatureFlagIsOff() {
        XCTAssertFalse(UVDocDewarper(featureFlagEnabled: false).isAvailable)
        XCTAssertNil(UVDocDewarper(featureFlagEnabled: false)
            .dewarp(TestImages.markerPage(size: size,
                                          center: CGPoint(x: 100, y: 100))))
    }

    func testDewarpChainFallsBackToGridWarpWhenPrimaryIsUnavailable() throws {
        let chain = DewarpChain(
            primary: UVDocDewarper(featureFlagEnabled: false),
            fallback: GridDewarper(grid: .uniform(dx: 0.1, dy: 0)))
        XCTAssertTrue(chain.isAvailable)

        let input = TestImages.markerPage(size: size,
                                          center: CGPoint(x: 200, y: 150),
                                          markerSide: 40)
        let output = try XCTUnwrap(chain.dewarp(input))
        XCTAssertLessThan(TestImages.luminance(output, x: 240, y: 150), 80,
                          "UVDoc 不可用时应回退到网格展平")
    }

    func testThinPlateSplineInterpolatesControlPointsAndTranslation() throws {
        let points = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 0, y: 100),
            CGPoint(x: 100, y: 100), CGPoint(x: 50, y: 50),
        ]
        let offset = CGPoint(x: 12, y: -7)
        let values = points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
        let spline = try XCTUnwrap(ThinPlateSpline(controlPoints: points, values: values))

        for point in points {
            let mapped = spline.map(point)
            XCTAssertEqual(mapped.x, point.x + offset.x, accuracy: 1e-6)
            XCTAssertEqual(mapped.y, point.y + offset.y, accuracy: 1e-6)
        }
        let interior = spline.map(CGPoint(x: 30, y: 70))
        XCTAssertEqual(interior.x, 42, accuracy: 1e-6)
        XCTAssertEqual(interior.y, 63, accuracy: 1e-6)
    }

    private func meanAbsoluteDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var total = 0
        for index in a.indices {
            total += abs(Int(a[index]) - Int(b[index]))
        }
        return Double(total) / Double(a.count)
    }
}
