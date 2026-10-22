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
/// 位移图，全分辨率重采样目前走确定性 CPU 双线性（模拟器上带 sampler 的 CI kernel 会编不过）。
/// TPS 求解是纯 CPU、固定顺序的；后续可再换成 Metal / CI kernel。
///
final class GridDewarper: Dewarping {
    let grid: DewarpGrid
    private let providedContext: CIContext?
    /// 只在真正需要展平时创建 CIContext，平纸路径不付这份初始化成本。
    private lazy var renderContext: CIContext = {
        self.providedContext ?? CIContext()
    }()

    func dewarp(_ image: CGImage) -> CGImage? {
        guard grid.isValid, image.width > 1, image.height > 1 else { return nil }
        // 恒等网格不需要任何重采样。
        if grid.offsets.allSatisfy({ $0.dx == 0 && $0.dy == 0 }) {
            return image
        }
        let imageSize = CGSize(width: CGFloat(image.width),
                               height: CGFloat(image.height))
        guard let spline = makeSpline(imageSize: imageSize) else { return nil }
        return Self.resampleCPU(image, spline: spline)
    }

    /// CPU 双线性重采样。当前 SDK 上带 sampler 的 `CIWarpKernel`/`CIColorKernel` 都会在模拟器里编译失败，
    /// M2-2 骨架先用确定性 CPU 路径保证行为与单测；后续可再换成 Metal。
    private static func resampleCPU(_ image: CGImage, spline: ThinPlateSpline) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 1, height > 1 else { return nil }

        let srcBytes = rgbaBytes(image)
        var dstBytes = [UInt8](repeating: 255, count: width * height * 4)

        for visualY in 0..<height {
            for visualX in 0..<width {
                // makeSpline / TPS 使用 Core Image 左下原点。
                let destCI = CGPoint(x: CGFloat(visualX) + 0.5,
                                     y: CGFloat(height - 1 - visualY) + 0.5)
                let sourceCI = spline.map(destCI)
                let srcVisualX = sourceCI.x - 0.5
                let srcVisualY = CGFloat(height) - sourceCI.y - 0.5
                let rgba = bilinearSample(srcBytes, width: width, height: height,
                                          x: srcVisualX, y: srcVisualY)
                let index = (visualY * width + visualX) * 4
                dstBytes[index] = rgba.0
                dstBytes[index + 1] = rgba.1
                dstBytes[index + 2] = rgba.2
                dstBytes[index + 3] = rgba.3
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = dstBytes.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let result = CGImage(width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bitsPerPixel: 32,
                                   bytesPerRow: width * 4,
                                   space: colorSpace,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider,
                                   decode: nil,
                                   shouldInterpolate: false,
                                   intent: .defaultIntent) else {
            return nil
        }
        return result
    }

    private static func rgbaBytes(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return
            }
            context.draw(image, in: CGRect(x: 0, y: 0,
                                           width: CGFloat(width), height: CGFloat(height)))
        }
        return pixels
    }

    private static func bilinearSample(_ bytes: [UInt8],
                                       width: Int,
                                       height: Int,
                                       x: CGFloat,
                                       y: CGFloat) -> (UInt8, UInt8, UInt8, UInt8) {
        if x.isNaN || y.isNaN || !x.isFinite || !y.isFinite {
            return (255, 255, 255, 255)
        }
        let maxX = CGFloat(width - 1)
        let maxY = CGFloat(height - 1)
        let clampedX = min(max(x, 0), maxX)
        let clampedY = min(max(y, 0), maxY)
        let x0 = Int(clampedX.rounded(.down))
        let y0 = Int(clampedY.rounded(.down))
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = clampedX - CGFloat(x0)
        let ty = clampedY - CGFloat(y0)

        func pixel(_ px: Int, _ py: Int) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
            let index = (py * width + px) * 4
            return (CGFloat(bytes[index]), CGFloat(bytes[index + 1]),
                    CGFloat(bytes[index + 2]), CGFloat(bytes[index + 3]))
        }

        let p00 = pixel(x0, y0)
        let p10 = pixel(x1, y0)
        let p01 = pixel(x0, y1)
        let p11 = pixel(x1, y1)

        func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a * (1 - t) + b * t }

        let r = mix(mix(p00.0, p10.0, tx), mix(p01.0, p11.0, tx), ty)
        let g = mix(mix(p00.1, p10.1, tx), mix(p01.1, p11.1, tx), ty)
        let b = mix(mix(p00.2, p10.2, tx), mix(p01.2, p11.2, tx), ty)
        let a = mix(mix(p00.3, p10.3, tx), mix(p01.3, p11.3, tx), ty)
        return (UInt8(clamping: Int(r.rounded())),
                UInt8(clamping: Int(g.rounded())),
                UInt8(clamping: Int(b.rounded())),
                UInt8(clamping: Int(a.rounded())))
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



