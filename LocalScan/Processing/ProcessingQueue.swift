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
/// `actor` 保证多个页面按提交顺序串行处理；调用方只 `await` 结果，
/// CPU 工作不在调用方线程（例如主线程）上执行。
actor ProcessingQueue {
    private let refiner: CornerRefiner
    private let corrector: PerspectiveCorrector
    private let log = OSLog(subsystem: "com.kdnsna.localscan",
                            category: .pointsOfInterest)

    init(refiner: CornerRefiner = CornerRefiner(),
         corrector: PerspectiveCorrector = PerspectiveCorrector()) {
        self.refiner = refiner
        self.corrector = corrector
    }

    func process(original: CGImage,
                 working: CGImage,
                 quad: Quad,
                 workingSize: CGSize) async throws -> ProcessedPage {
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
