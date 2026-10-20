import CoreGraphics
import Foundation
import os

struct ProcessedPage {
    /// 在工作图坐标下细化后的四边形。
    let quad: Quad
    /// 原图全分辨率透视拉正结果。
    let image: CGImage
}

/// 串行后台处理：细化工作图角点，再映射回原图做全分辨率拉正。
///
/// **输入约定**：`original` 与 `working` 都必须已经应用 EXIF 方向（upright）；
/// 本队列不读取图像元数据，也不做任何旋转。`quad` 使用工作图像素坐标
/// （左上原点，y 向下）。
///
/// 细化与拉正都在专用串行 `DispatchQueue` 上执行：多个页面按提交顺序处理，
/// 调用方只 `await` 结果，CPU 工作不占用调用方线程，也不阻塞 Swift 并发协作线程池。
final class ProcessingQueue: @unchecked Sendable {
    private let refiner: CornerRefiner
    private let corrector: PerspectiveCorrector
    private let work = DispatchQueue(label: "com.kdnsna.localscan.processing",
                                     qos: .userInitiated)
    private let log = OSLog(subsystem: "com.kdnsna.localscan",
                            category: .pointsOfInterest)

    init(refiner: CornerRefiner = CornerRefiner(),
         corrector: PerspectiveCorrector = PerspectiveCorrector()) {
        self.refiner = refiner
        self.corrector = corrector
    }

    private func run<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            work.async {
                continuation.resume(with: Result { try body() })
            }
        }
    }

    func process(original: CGImage,
                 working: CGImage,
                 quad: Quad,
                 workingSize: CGSize) async throws -> ProcessedPage {
        try await run { [refiner, corrector, log] in
            os_signpost(.begin, log: log, name: "Refine")
            let refined = refiner.refine(quad, in: working)
            os_signpost(.end, log: log, name: "Refine")

            os_signpost(.begin, log: log, name: "PerspectiveCorrect")
            defer {
                os_signpost(.end, log: log, name: "PerspectiveCorrect")
            }
            let image = try corrector.correct(original,
                                              quad: refined,
                                              workingSize: workingSize)
            return ProcessedPage(quad: refined, image: image)
        }
    }

    /// 手动裁剪确认后只重跑透视拉正，不再做角点细化。
    func correct(original: CGImage,
                 quad: Quad,
                 workingSize: CGSize) async throws -> CGImage {
        try await run { [corrector] in
            try corrector.correct(original, quad: quad, workingSize: workingSize)
        }
    }
}
