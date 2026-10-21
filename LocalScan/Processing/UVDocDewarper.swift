import CoreGraphics
import CoreML
import Foundation

/// 可选的 UVDoc 展平器（本 PR 只留骨架，**不包含任何模型文件**）。
///
/// 只有同时满足以下条件才会尝试加载模型：
/// 1. 功能开关打开（`UserDefaults` 中的 `featureFlagKey`）；
/// 2. App bundle 里确实存在 `UVDoc.mlmodelc`。
///
/// 模型缺失、加载失败或功能关闭时 `isAvailable` 为 false，管线会自动回退到
/// 确定性网格展平或平纸输出。模型推理尚未实现，因此即使加载成功，`dewarp`
/// 目前也返回 nil，让管线继续走回退路径。
final class UVDocDewarper: Dewarping {
    /// 功能开关的 UserDefaults key。默认关闭；这是本地开关，不涉及网络下发。
    static let featureFlagKey = "LocalScan.feature.uvdocDewarper"
    /// 预期随包模型资源名（编译后的 Core ML 模型目录）。
    static let modelResourceName = "UVDoc"
    static let modelResourceExtension = "mlmodelc"

    static var featureFlagEnabled: Bool {
        UserDefaults.standard.bool(forKey: featureFlagKey)
    }

    private let model: MLModel?

    var isAvailable: Bool { model != nil }

    init(bundle: Bundle = .main,
         featureFlagEnabled: Bool = UVDocDewarper.featureFlagEnabled) {
        guard featureFlagEnabled,
              let url = bundle.url(forResource: UVDocDewarper.modelResourceName,
                                   withExtension: UVDocDewarper.modelResourceExtension) else {
            model = nil
            return
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        guard let loaded = try? MLModel(contentsOf: url,
                                        configuration: configuration) else {
            model = nil
            return
        }
        model = loaded
    }

    func dewarp(_ image: CGImage) -> CGImage? {
        guard model != nil else { return nil }
        // M2-2 只做可行性骨架：不加载/不运行模型推理。等模型 PR 再实现 45×31 网格输出。
        return nil
    }
}
