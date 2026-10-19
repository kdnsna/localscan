import CoreGraphics

/// 全局默认参数（起点值，见 docs/PLAN.md 与 docs/research/）。
enum ScanDefaults {
    /// 算法工作图长边范围（像素）。原图始终另行保留。
    static let workingLongSideRange: ClosedRange<CGFloat> = 1600...2048
    /// 默认工作图长边。
    static let workingLongSide: CGFloat = 2048
    /// 导出 JPEG 质量范围与默认值。
    static let jpegQualityRange: ClosedRange<Double> = 0.80...0.88
    static let jpegQuality: Double = 0.85
    /// 倾斜提示阈值（度）。
    static let tiltWarningDegrees: Double = 18
}

/// 计算算法工作图尺寸：长边缩到 `maxLongSide`，不放大，保持宽高比，取整到整数像素。
enum ImageSizing {
    static func workingSize(for original: CGSize,
                            maxLongSide: CGFloat = ScanDefaults.workingLongSide) -> CGSize {
        guard original.width > 0, original.height > 0, maxLongSide > 0 else { return .zero }
        let longSide = max(original.width, original.height)
        guard longSide > maxLongSide else { return original }
        let scale = maxLongSide / longSide
        return CGSize(width: (original.width * scale).rounded(),
                      height: (original.height * scale).rounded())
    }
}
