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

    /// 找边失败时的默认四边形内缩比例。
    static let defaultQuadInset: CGFloat = 0.06
    /// 时域平滑：旧框到新框的过渡时长与无检测后的丢弃时长（秒）。
    static let smoothingDuration: Double = 0.15
    static let smoothingDropAfter: Double = 0.5
    /// 自动拍摄：连续稳定帧数范围与默认值。
    static let autoCaptureRequiredFramesRange: ClosedRange<Int> = 3...5
    static let autoCaptureRequiredFrames = 4
    /// 自动拍摄：相邻帧最大角点位移（占四边形对角线比例）。
    static let autoCaptureMaxDisplacementFraction: CGFloat = 0.015
    /// 自动拍摄：锁存后与触发时页面相比，判定为“换页”的角点位移（占对角线比例）。
    static let autoCapturePageChangeDisplacementFraction: CGFloat = 0.15
    /// 自动拍摄：四边形最小面积（占画面比例）。
    static let autoCaptureMinAreaFraction: CGFloat = 0.15
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
