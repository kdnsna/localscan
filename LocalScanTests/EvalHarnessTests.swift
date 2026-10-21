import CoreGraphics
import Foundation
import XCTest
@testable import LocalScan

/// 离线找边评测的运行端：读取本地照片，跑完整拍后路径并写 predictions.json。
///
/// 默认跳过；只有设置 LOCALSCAN_EVAL_DIR 时才运行。在模拟器里用
/// `TEST_RUNNER_LOCALSCAN_EVAL_DIR=/path/to/photos` 传进来（Xcode 会去掉
/// `TEST_RUNNER_` 前缀）。输出目录由 LOCALSCAN_EVAL_OUT 指定，默认同输入目录。
final class EvalHarnessTests: XCTestCase {
    func testOfflineEvalHarness() async throws {
        let environment = ProcessInfo.processInfo.environment
        let rawInputPath = environment["LOCALSCAN_EVAL_DIR"]
        guard let inputPath = rawInputPath?.trimmingCharacters(
            in: .whitespacesAndNewlines),
              !inputPath.isEmpty else {
            throw XCTSkip("未设置 LOCALSCAN_EVAL_DIR；跳过离线评测。")
        }

        let inputDirectory = URL(fileURLWithPath: inputPath, isDirectory: true)
        let rawOutputPath = environment["LOCALSCAN_EVAL_OUT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let outputDirectory: URL
        if let rawOutputPath, !rawOutputPath.isEmpty {
            outputDirectory = URL(fileURLWithPath: rawOutputPath, isDirectory: true)
        } else {
            outputDirectory = inputDirectory
        }

        let allowedExtensions: Set<String> = ["jpg", "jpeg", "heic", "png"]
        let files = try FileManager.default
            .contentsOfDirectory(atPath: inputDirectory.path)
            .filter { allowedExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
        guard !files.isEmpty else {
            throw XCTSkip("LOCALSCAN_EVAL_DIR 中没有 jpg/jpeg/heic/png：\(inputDirectory.path)")
        }

        try FileManager.default.createDirectory(at: outputDirectory,
                                                withIntermediateDirectories: true)

        let decoder = CaptureDecoder()
        let queue = ProcessingQueue()
        let clock = ContinuousClock()
        var predictions: [[String: Any]] = []
        var failures: [String] = []

        for file in files {
            let url = inputDirectory.appendingPathComponent(file)
            do {
                let data = try Data(contentsOf: url)
                let decoded = try decoder.decode(data)
                let workingQuad = DocumentQuadDetector.detect(in: decoded.working)
                let originalSize = CGSize(width: CGFloat(decoded.original.width),
                                          height: CGFloat(decoded.original.height))

                // 预测坐标统一写原图像素坐标；评分脚本再按宽高比例缩放。
                let outputQuad = workingQuad.mapped(from: decoded.workingSize,
                                                    to: originalSize)

                let start = clock.now
                _ = try await queue.process(original: decoded.original,
                                            working: decoded.working,
                                            quad: workingQuad,
                                            workingSize: decoded.workingSize)
                let elapsed = start.duration(to: clock.now)

                predictions.append([
                    "file": file,
                    "width": decoded.original.width,
                    "height": decoded.original.height,
                    "quad": outputQuad.corners.map { [Double($0.x), Double($0.y)] },
                    "ms": milliseconds(elapsed),
                ])
            } catch {
                failures.append("\(file): \(error)")
            }
        }

        let payload: [String: Any] = ["images": predictions]
        let json = try JSONSerialization.data(withJSONObject: payload,
                                              options: [.prettyPrinted, .sortedKeys])
        try json.write(to: outputDirectory.appendingPathComponent("predictions.json"),
                       options: .atomic)

        XCTAssertTrue(failures.isEmpty,
                      "以下图片处理失败：\n" + failures.joined(separator: "\n"))
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
