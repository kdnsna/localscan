import CoreGraphics
import CoreImage
import Foundation

/// 书页展平。输入是已经透视拉正的整页图像；返回 nil 表示当前实现不可用或失败，
/// 由管线回退到平纸输出。
protocol Dewarping {
    var isAvailable: Bool { get }
    func dewarp(_ image: CGImage) -> CGImage?
}

/// 网格上的一个归一化位移。正值表示图像内容向 **右 / 下** 移动，
/// 单位是画面宽 / 高的比例（0.01 = 1% 画面尺寸）。
struct DewarpOffset: Equatable {
    var dx: CGFloat
    var dy: CGFloat

    static let zero = DewarpOffset(dx: 0, dy: 0)
}

/// 规则控制网格：`columns × rows` 个节点，row-major（从左上到右下）。
/// 未来的 6 点回归网络或 UVDoc 网格可以直接转换成这个结构。
struct DewarpGrid: Equatable {
    let columns: Int
    let rows: Int
    let offsets: [DewarpOffset]

    var isValid: Bool {
        guard columns >= 2, rows >= 2,
              offsets.count == columns * rows else { return false }
        return offsets.allSatisfy { $0.dx.isFinite && $0.dy.isFinite }
    }

    static let identity = DewarpGrid(
        columns: 3,
        rows: 3,
        offsets: Array(repeating: .zero, count: 9))

    static func uniform(columns: Int = 3,
                        rows: Int = 3,
                        dx: CGFloat,
                        dy: CGFloat) -> DewarpGrid {
        let count = max(0, columns * rows)
        return DewarpGrid(columns: columns,
                          rows: rows,
                          offsets: Array(repeating: DewarpOffset(dx: dx, dy: dy),
                                         count: count))
    }
}

/// 确定性网格 / TPS 展平。
///
/// 先用控制网格拟合一个「输出坐标 -> 源坐标」的 TPS，再把 TPS 采样成一张低分辨率
/// 位移图，最后用 Core Image 的 `CIWarpKernel` 做全分辨率重采样。TPS 求解和位移图
/// 生成是纯 CPU、固定顺序的；重采样交给 Core Image（后续可以替换成 Metal kernel）。
///
/// 位移图的采样只在 `dewarp` 第一次被调用时创建 kernel，平纸路径不会编译 kernel。
final class GridDewarper: Dewarping {
    let grid: DewarpGrid
    private let providedContext: CIContext?
    /// 只在真正需要展平时创建 CIContext，平纸路径不付这份初始化成本。
    private lazy var renderContext: CIContext = {
        self.providedContext ?? CIContext()
    }()

    /// 位移图长边上限。TPS 是低频形变，129×129 的位移图足够，且避免每个像素都算 TPS。
    private static let displacementMapMaxDimension = 129

    private static let kernelSource = """
    kernel vec2 localScanDewarp(sampler displacement,
                                float imageWidth,
                                float imageHeight,
                                float mapWidth,
                                float mapHeight,
                                float offsetScale) {
        vec2 dest = destCoord();
        vec2 unit = clamp(dest / vec2(imageWidth, imageHeight),
                          vec2(0.0, 0.0), vec2(1.0, 1.0));
        vec2 mapCoord = unit * vec2(mapWidth - 1.0, mapHeight - 1.0);
        vec2 offset = (sample(displacement, mapCoord).xy - vec2(0.5, 0.5))
            * offsetScale;
        return dest + offset;
    }
    """

    private lazy var kernel: CIWarpKernel? = CIWarpKernel(source: GridDewarper.kernelSource)

    var isAvailable: Bool { grid.isValid }

    init(grid: DewarpGrid, context: CIContext? = nil) {
        self.grid = grid
        self.providedContext = context
    }

    func dewarp(_ image: CGImage) -> CGImage? {
        guard grid.isValid, image.width > 1, image.height > 1 else { return nil }
        // 恒等网格不需要任何重采样；同时避免默认回退路径在书页上做无意义的工作。
        if grid.offsets.allSatisfy({ $0.dx == 0 && $0.dy == 0 }) {
            return image
        }
        let imageSize = CGSize(width: CGFloat(image.width),
                               height: CGFloat(image.height))
        guard let spline = makeSpline(imageSize: imageSize),
              let displacement = makeDisplacementMap(spline: spline, imageSize: imageSize),
              let kernel = kernel else {
            return nil
        }

        let extent = CGRect(x: 0, y: 0,
                            width: imageSize.width, height: imageSize.height)
        let input = CIImage(cgImage: image)
        let arguments: [Any] = [
            displacement.image,
            NSNumber(value: Double(imageSize.width)),
            NSNumber(value: Double(imageSize.height)),
            NSNumber(value: Double(displacement.width)),
            NSNumber(value: Double(displacement.height)),
            NSNumber(value: Double(displacement.vectorScale)),
        ]
        guard let output = kernel.apply(extent: extent,
                                        roiCallback: { _, _ in extent },
                                        image: input,
                                        arguments: arguments) else {
            return nil
        }
        let rendered = output.cropped(to: extent)
        guard let result = renderContext.createCGImage(rendered, from: extent) else {
            return nil
        }
        // 位移图数据必须活到 createCGImage 完成；这里显式引用一次，避免被提前释放。
        _ = displacement.data
        return result
    }

    // MARK: - TPS 与位移图

    private func makeSpline(imageSize: CGSize) -> ThinPlateSpline? {
        let width = imageSize.width
        let height = imageSize.height
        guard width > 1, height > 1 else { return nil }

        var destinations: [CGPoint] = []
        var sources: [CGPoint] = []
        destinations.reserveCapacity(grid.offsets.count)
        sources.reserveCapacity(grid.offsets.count)

        for row in 0..<grid.rows {
            let rowFraction = CGFloat(row) / CGFloat(grid.rows - 1)
            for column in 0..<grid.columns {
                let columnFraction = CGFloat(column) / CGFloat(grid.columns - 1)
                // 网格 row 0 在画面顶部；Core Image / TPS 使用左下原点，先换到 CI 坐标。
                let visualX = columnFraction * width
                let visualY = rowFraction * height
                let destination = CGPoint(x: visualX, y: height - visualY)
                let offset = grid.offsets[row * grid.columns + column]
                // 内容向右 / 下移动 d。水平方向源坐标 = dest.x - dx；
                // Core Image 的 y 轴向上，内容向下移动 d 时源坐标 = dest.y + dy。
                let source = CGPoint(x: destination.x - offset.dx * width,
                                     y: destination.y + offset.dy * height)
                destinations.append(destination)
                sources.append(source)
            }
        }
        return ThinPlateSpline(controlPoints: destinations, values: sources)
    }

    private struct DisplacementMap {
        let image: CIImage
        let data: Data
        let width: Int
        let height: Int
        /// 位移编码尺度：存储值 = offset / vectorScale + 0.5，保证落在 [0,1]。
        let vectorScale: CGFloat
    }

    private func makeDisplacementMap(spline: ThinPlateSpline,
                                     imageSize: CGSize) -> DisplacementMap? {
        let width = min(Self.displacementMapMaxDimension,
                        max(2, Int(imageSize.width.rounded())))
        let height = min(Self.displacementMapMaxDimension,
                         max(2, Int(imageSize.height.rounded())))
        guard width >= 2, height >= 2 else { return nil }

        // 支持 ±1 个画面长边的位移；正常书页弯曲远小于这个范围。
        let vectorScale = max(imageSize.width, imageSize.height) * 2
        guard vectorScale.isFinite, vectorScale > 0 else { return nil }

        // RGBAf：R/G 存编码后的源坐标偏移，B 恒 0，A 恒 1。
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            // 数据行 0 是画面顶部；CI 的 y=0 在画面底部。
            let unitY = 1 - (CGFloat(row) + 0.5) / CGFloat(height)
            for column in 0..<width {
                let unitX = (CGFloat(column) + 0.5) / CGFloat(width)
                let destination = CGPoint(x: unitX * imageSize.width,
                                          y: unitY * imageSize.height)
                let source = spline.map(destination)
                let index = (row * width + column) * 4
                pixels[index] = Float((source.x - destination.x) / vectorScale + 0.5)
                pixels[index + 1] = Float((source.y - destination.y) / vectorScale + 0.5)
                pixels[index + 2] = 0
                pixels[index + 3] = 1
            }
        }

        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        // CIImage(bitmapData:...) is non-optional on current SDK; do not guard-let it.
        let image = CIImage(bitmapData: data,
                            bytesPerRow: width * MemoryLayout<Float>.size * 4,
                            size: CGSize(width: width, height: height),
                            format: .RGBAf,
                            colorSpace: nil)
        return DisplacementMap(image: image, data: data, width: width, height: height,
                               vectorScale: vectorScale)
    }
}

/// 展平级联：优先用可用的实现（例如 UVDoc），失败时退回确定性网格展平。
struct DewarpChain: Dewarping {
    let primary: Dewarping?
    let fallback: Dewarping?

    var isAvailable: Bool {
        (primary?.isAvailable ?? false) || (fallback?.isAvailable ?? false)
    }

    func dewarp(_ image: CGImage) -> CGImage? {
        if let primary = primary, primary.isAvailable,
           let output = primary.dewarp(image) {
            return output
        }
        if let fallback = fallback, fallback.isAvailable,
           let output = fallback.dewarp(image) {
            return output
        }
        return nil
    }
}

