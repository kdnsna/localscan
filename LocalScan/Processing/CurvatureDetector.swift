import CoreGraphics

/// 一张已经透视拉正的书页是「平纸」还是需要展平的「弯曲书页」。
enum PageCurvature: Equatable {
    case flat
    case curved
}

/// 弯曲判定的结果。`score` 是检测到的最大弯曲偏离量（归一化到画面高度，0...1），
/// 越大表示越弯；阈值见 `EdgeCurvatureDetector.Thresholds`。
struct CurvatureResult: Equatable {
    let curvature: PageCurvature
    let score: Float

    var isCurved: Bool { curvature == .curved }

    static let flat = CurvatureResult(curvature: .flat, score: 0)
}

/// 廉价弯曲判定。输入必须是已经透视拉正的整页图像。
protocol CurvatureDetecting {
    func detect(in image: CGImage) -> CurvatureResult
}

/// 基于「接近水平的边缘是否成直线」的确定性、纯 CPU 判定。
///
/// 做法：
/// 1. 缩到长边 ≤ 512 的灰度图；
/// 2. 取竖直梯度明显大于水平梯度的像素，得到近似水平的边缘；
/// 3. 水平膨胀后做连通域，只保留足够宽、明显横向的长条；
/// 4. 对每个长条做最小二乘直线拟合，取残差最大值作为弯曲分数。
///
/// 平纸的文本行/表格线残差接近线宽；弯曲书页的同一行会横向偏移数个百分点。
/// 没有检测到可信长条时保守地返回平纸，绝不因为「没看到线」而启动展平。
struct EdgeCurvatureDetector: CurvatureDetecting {
    enum Thresholds {
        /// 灰度缓冲的长边上限（像素）。判定只看低频结构，不需要全分辨率。
        static let maxDimension = 512
        /// 竖直梯度阈值（0...1 灰度）。
        static let gradientThreshold: Float = 0.08
        /// 只保留竖直梯度至少是水平梯度这么多倍的像素（近似水平边缘）。
        static let orientationRatio: Float = 1.2
        /// 水平膨胀半径（像素），用来接上文字/网格线之间的空隙。
        static let dilationRadius = 2
        /// 一个连通域至少包含的像素数。
        static let minimumComponentPixels = 24
        /// 连通域横向跨度至少占画面宽度的比例。
        static let minimumSpanFraction: CGFloat = 0.15
        /// 横向跨度至少是纵向跨度的多少倍，排除竖线/文字块。
        static let minimumAspectRatio: CGFloat = 1.8
        /// 判定为弯曲的归一化残差阈值（占画面高度）。
        static let curvedDeviationFraction: CGFloat = 0.008
    }

    func detect(in image: CGImage) -> CurvatureResult {
        guard image.width > 2, image.height > 2,
              let gray = Self.grayscale(from: image,
                                        maxDimension: Thresholds.maxDimension) else {
            return .flat
        }

        let width = gray.width
        let height = gray.height
        guard width > 2, height > 2 else { return .flat }

        let edge = Self.horizontalEdges(in: gray)
        let mask = Self.dilateHorizontally(edge,
                                           width: width,
                                           height: height,
                                           radius: Thresholds.dilationRadius)

        var visited = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        stack.reserveCapacity(256)
        var lineComponents = 0
        var maxDeviation: Double = 0

        for start in 0..<(width * height) where mask[start] && !visited[start] {
            visited[start] = true
            stack.append(start)

            var pixelCount = 0
            var minX = width
            var maxX = 0
            var minY = height
            var maxY = 0
            var sumX: Double = 0
            var sumY: Double = 0
            var sumXX: Double = 0
            var sumXY: Double = 0
            var sumYY: Double = 0

            while let index = stack.popLast() {
                let x = index % width
                let y = index / width
                pixelCount += 1
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                let dx = Double(x)
                let dy = Double(y)
                sumX += dx
                sumY += dy
                sumXX += dx * dx
                sumXY += dx * dy
                sumYY += dy * dy

                for offsetY in -1...1 {
                    let nextY = y + offsetY
                    guard nextY >= 0, nextY < height else { continue }
                    for offsetX in -1...1 where offsetX != 0 || offsetY != 0 {
                        let nextX = x + offsetX
                        guard nextX >= 0, nextX < width else { continue }
                        let nextIndex = nextY * width + nextX
                        if mask[nextIndex] && !visited[nextIndex] {
                            visited[nextIndex] = true
                            stack.append(nextIndex)
                        }
                    }
                }
            }

            guard pixelCount >= Thresholds.minimumComponentPixels else { continue }
            let spanX = maxX - minX + 1
            let spanY = maxY - minY + 1
            guard CGFloat(spanX) >= CGFloat(width) * Thresholds.minimumSpanFraction,
                  CGFloat(spanX) >= CGFloat(spanY) * Thresholds.minimumAspectRatio else {
                continue
            }

            let count = Double(pixelCount)
            let meanX = sumX / count
            let meanY = sumY / count
            let varianceX = sumXX / count - meanX * meanX
            guard varianceX > 1e-9 else { continue }
            let covariance = sumXY / count - meanX * meanY
            let slope = covariance / varianceX
            let intercept = meanY - slope * meanX

            // 最小二乘残差平方和 = Σ(y - (a·x + b))²，用求和量展开计算。
            var sumSquaredError = sumYY
                - 2 * slope * sumXY
                - 2 * intercept * sumY
                + slope * slope * sumXX
                + 2 * slope * intercept * sumX
                + count * intercept * intercept
            if sumSquaredError < 0 { sumSquaredError = 0 }
            let rms = (sumSquaredError / count).squareRoot() / Double(height)
            lineComponents += 1
            maxDeviation = max(maxDeviation, rms)
        }

        guard lineComponents > 0 else { return .flat }
        let score = Float(min(1, maxDeviation))
        let curvature: PageCurvature =
            CGFloat(maxDeviation) >= Thresholds.curvedDeviationFraction ? .curved : .flat
        return CurvatureResult(curvature: curvature, score: score)
    }

    // MARK: - 灰度与边缘

    private struct GrayImage {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    private static func grayscale(from image: CGImage,
                                  maxDimension: Int) -> GrayImage? {
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

    private static func horizontalEdges(in gray: GrayImage) -> [Bool] {
        let width = gray.width
        let height = gray.height
        var edges = [Bool](repeating: false, count: width * height)
        guard width > 2, height > 2 else { return edges }

        for y in 1..<(height - 1) {
            let row = y * width
            let previousRow = row - width
            let nextRow = row + width
            for x in 1..<(width - 1) {
                let index = row + x
                let vertical = abs(Float(gray.pixels[nextRow + x])
                    - Float(gray.pixels[previousRow + x])) / 255
                let horizontal = abs(Float(gray.pixels[row + x + 1])
                    - Float(gray.pixels[row + x - 1])) / 255
                if vertical >= Thresholds.gradientThreshold,
                   vertical >= horizontal * Thresholds.orientationRatio {
                    edges[index] = true
                }
            }
        }
        return edges
    }

    private static func dilateHorizontally(_ edges: [Bool],
                                           width: Int,
                                           height: Int,
                                           radius: Int) -> [Bool] {
        guard radius > 0 else { return edges }
        var dilated = edges
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where edges[row + x] {
                let lower = max(0, x - radius)
                let upper = min(width - 1, x + radius)
                for nextX in lower...upper {
                    dilated[row + nextX] = true
                }
            }
        }
        return dilated
    }
}
