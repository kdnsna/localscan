import CoreGraphics
import Foundation
import os

struct ProcessedPage {
    /// 在工作图坐标下细化后的四边形。
    let quad: Quad
    /// 原图全分辨率透视拉正（可能再经过展平）的结果。
    let image: CGImage
    /// 对拉正结果做廉价弯曲判定的结果；平纸路径不启动展平。
    let curvature: CurvatureResult
}

/// 串行后台处理：细化工作图角点，映射回原图做全分辨率拉正，再按需展平。
///
/// **输入约定**：`original` 与 `working` 都必须已经应用 EXIF 方向（upright）；
/// 本队列不读取图像元数据，也不做任何旋转。`quad` 使用工作图像素坐标
/// （左上原点，y 向下）。
///
/// 处理顺序：角点细化 -> 透视拉正 -> 廉价弯曲判定 -> （仅弯曲时）展平。
/// 平纸只多一次低分辨率判定，不做任何展平重采样；滤镜/增强在更外层对结果应用。
///
/// 细化、拉正与判定都在专用串行 `DispatchQueue` 上执行：多个页面按提交顺序处理，
/// 调用方只 `await` 结果，CPU 工作不占用调用方线程，也不阻塞 Swift 并发协作线程池。
final class ProcessingQueue: @unchecked Sendable {
    private let refiner: CornerRefiner
    private let corrector: PerspectiveCorrector
    private let curvatureDetector: CurvatureDetecting
    private let dewarper: Dewarping?
    private let work = DispatchQueue(label: "com.kdnsna.localscan.processing",
                                     qos: .userInitiated)
    private let log = OSLog(subsystem: "com.kdnsna.localscan",
                            category: .pointsOfInterest)

    init(refiner: CornerRefiner = CornerRefiner(),
         corrector: PerspectiveCorrector = PerspectiveCorrector(),
         curvatureDetector: CurvatureDetecting = EdgeCurvatureDetector(),
         dewarper: Dewarping? = DewarpChain(
            primary: UVDocDewarper(),
            fallback: GridDewarper(grid: .identity))) {
        self.refiner = refiner
        self.corrector = corrector
        self.curvatureDetector = curvatureDetector
        self.dewarper = dewarper
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
        try await run { [refiner, corrector, curvatureDetector, dewarper, log] in
            os_signpost(.begin, log: log, name: "Refine")
            let refined = refiner.refine(quad, in: working)
            os_signpost(.end, log: log, name: "Refine")

            os_signpost(.begin, log: log, name: "PerspectiveCorrect")
            let corrected = try corrector.correct(original,
                                                  quad: refined,
                                                  workingSize: workingSize)
            os_signpost(.end, log: log, name: "PerspectiveCorrect")

            os_signpost(.begin, log: log, name: "CurvatureDetect")
            let curvature = curvatureDetector.detect(in: corrected)
            os_signpost(.end, log: log, name: "CurvatureDetect")

            guard curvature.isCurved,
                  let dewarper = dewarper,
                  dewarper.isAvailable else {
                return ProcessedPage(quad: refined, image: corrected,
                                     curvature: curvature)
            }

            os_signpost(.begin, log: log, name: "Dewarp")
            defer {
                os_signpost(.end, log: log, name: "Dewarp")
            }
            let image = dewarper.dewarp(corrected) ?? corrected
            return ProcessedPage(quad: refined, image: image,
                                 curvature: curvature)
        }
    }

    /// 手动裁剪确认后只重跑透视拉正与按需展平，不再做角点细化。
    func correct(original: CGImage,
                 quad: Quad,
                 workingSize: CGSize) async throws -> CGImage {
        try await run { [corrector, curvatureDetector, dewarper] in
            let corrected = try corrector.correct(original,
                                                  quad: quad,
                                                  workingSize: workingSize)
            let curvature = curvatureDetector.detect(in: corrected)
            guard curvature.isCurved,
                  let dewarper = dewarper,
                  dewarper.isAvailable else {
                return corrected
            }
            return dewarper.dewarp(corrected) ?? corrected
        }
    }
}
