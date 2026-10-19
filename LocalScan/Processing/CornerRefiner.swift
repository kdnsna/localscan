import CoreGraphics
import Foundation

/// 在工作图（灰度）上做轻量角点细化：每个角点在 ±1.5% 对角线的窗口内搜索，
/// 用两条相邻边两侧的灰度差之和作为分数。纯 CPU、确定性；若没有明显改进
/// （默认分数提升 5% 且至少 2 个灰度级），返回原四边形。
struct CornerRefiner {
    struct Options {
        /// 搜索半径占四边形对角线的比例。
        var searchFraction: CGFloat = 0.015
        /// 灰度缓冲的长边上限，避免在 2048 px 工作图上做全尺寸搜索。
        var maxDimension: Int = 1024
        /// 最优分数相对原分数至少提升这个比例才接受。
        var minImprovement: Float = 0.05
        /// 同时要求至少提升这么多灰度级，过滤平坦区域的噪声。
        var minGain: Float = 2
        /// 每条边的采样点数。
        var sampleCount: Int = 8
    }

    var options: Options

    init(options: Options = Options()) {
        self.options = options
    }

    func refine(_ quad: Quad, in image: CGImage) -> Quad {
        guard quad.isFinite, quad.isConvex,
              image.width > 1, image.height > 1 else {
            return quad
        }
        guard let gray = Self.grayscale(from: image,
                                        maxDimension: options.maxDimension) else {
            return quad
        }

        let imageSize = CGSize(width: CGFloat(image.width),
                               height: CGFloat(image.height))
        let scaleX = CGFloat(gray.width) / imageSize.width
        let scaleY = CGFloat(gray.height) / imageSize.height
        let scaled = quad.scaled(by: scaleX, scaleY)
        guard scaled.isFinite, scaled.isConvex else { return quad }

        let radius = max(1, scaled.diagonalLength * options.searchFraction)
        let points = scaled.corners
        var refined = points
        for i in points.indices {
            let previous = points[(i + 3) % points.count]
            let next = points[(i + 1) % points.count]
            if let candidate = refineCorner(points[i], previous: previous,
                                            next: next, gray: gray,
                                            radius: radius) {
                refined[i] = candidate
            }
        }

        let refinedQuad = Quad(topLeft: refined[0], topRight: refined[1],
                               bottomRight: refined[2], bottomLeft: refined[3])
        guard refinedQuad.isFinite, refinedQuad.isConvex else { return quad }

        let result = refinedQuad.scaled(by: 1 / scaleX, 1 / scaleY)
        guard result.isFinite, result.isConvex else { return quad }
        return result
    }

    private func refineCorner(_ corner: CGPoint,
                              previous: CGPoint,
                              next: CGPoint,
                              gray: GrayImage,
                              radius: CGFloat) -> CGPoint? {
        let originalScore = (edgeScore(corner, previous, gray)
            + edgeScore(corner, next, gray)) * 0.5
        var best = corner
        var bestScore = originalScore

        // 至少 4 步，最多 48 步；步长随搜索窗口变化但始终是确定值。
        let steps = max(4, min(48, Int((radius / 0.5).rounded(.up))))
        let step = radius / CGFloat(steps)
        let maxX = CGFloat(gray.width - 1)
        let maxY = CGFloat(gray.height - 1)

        for iy in -steps...steps {
            let y = corner.y + CGFloat(iy) * step
            guard y >= 0, y <= maxY else { continue }
            for ix in -steps...steps {
                let x = corner.x + CGFloat(ix) * step
                guard x >= 0, x <= maxX else { continue }
                let candidate = CGPoint(x: x, y: y)
                let score = (edgeScore(candidate, previous, gray)
                    + edgeScore(candidate, next, gray)) * 0.5
                if score > bestScore {
                    bestScore = score
                    best = candidate
                }
            }
        }

        let clearlyBetter = bestScore > originalScore * (1 + options.minImprovement)
            && bestScore - originalScore > options.minGain
        return clearlyBetter ? best : nil
    }

    /// 沿 corner->adjacent 的线段取若干点，比较每个点沿法线 ±1.5 px 的灰度差。
    /// 直线正好压在边缘上时差值最大；离开边缘后两侧同色，分数迅速下降。
    private func edgeScore(_ corner: CGPoint,
                           _ adjacent: CGPoint,
                           _ gray: GrayImage) -> Float {
        let dx = adjacent.x - corner.x
        let dy = adjacent.y - corner.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1 else { return 0 }
        let normalX = -dy / length
        let normalY = dx / length
        let sampleCount = max(3, options.sampleCount)
        let offset: CGFloat = 1.5
        var total: Float = 0
        for i in 0..<sampleCount {
            let t = 0.08 + 0.62 * (CGFloat(i) + 0.5) / CGFloat(sampleCount)
            let x = corner.x + dx * t
            let y = corner.y + dy * t
            let a = gray.sample(x + normalX * offset, y + normalY * offset)
            let b = gray.sample(x - normalX * offset, y - normalY * offset)
            total += abs(a - b)
        }
        return total / Float(sampleCount)
    }

    // MARK: - 灰度缓冲

    private struct GrayImage {
        let width: Int
        let height: Int
        let pixels: [UInt8]

        func sample(_ x: CGFloat, _ y: CGFloat) -> Float {
            let maxX = CGFloat(width - 1)
            let maxY = CGFloat(height - 1)
            let fx = min(max(x, 0), maxX)
            let fy = min(max(y, 0), maxY)
            let x0 = Int(fx)
            let y0 = Int(fy)
            let x1 = min(x0 + 1, width - 1)
            let y1 = min(y0 + 1, height - 1)
            let tx = Float(fx - CGFloat(x0))
            let ty = Float(fy - CGFloat(y0))

            let p00 = Float(pixels[y0 * width + x0])
            let p10 = Float(pixels[y0 * width + x1])
            let p01 = Float(pixels[y1 * width + x0])
            let p11 = Float(pixels[y1 * width + x1])
            let top = p00 + (p10 - p00) * tx
            let bottom = p01 + (p11 - p01) * tx
            return top + (bottom - top) * ty
        }
    }

    private static func grayscale(from image: CGImage, maxDimension: Int) -> GrayImage? {
        let longSide = max(image.width, image.height)
        let scale = min(1, CGFloat(max(1, maxDimension)) / CGFloat(longSide))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)

        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0,
                                           width: CGFloat(width),
                                           height: CGFloat(height)))
            return true
        }
        guard drawn else { return nil }
        return GrayImage(width: width, height: height, pixels: pixels)
    }
}
