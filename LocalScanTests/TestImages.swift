import CoreGraphics
import Foundation
@testable import LocalScan

/// 测试用内存图像工具：只画在 CGContext 里，不读写任何文件。
enum TestImages {
    /// 黑色背景上画一个白色四边形。路径坐标是左上原点（y 向下），
    /// 绘制前翻转上下文，使内存中的图像与 Quad 约定一致。
    static func page(size: CGSize, quad: Quad,
                     background: CGFloat = 0,
                     foreground: CGFloat = 1) -> CGImage {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("无法创建测试用位图上下文")
        }

        context.setFillColor(CGColor(gray: background, alpha: 1))
        context.fill(CGRect(x: 0, y: 0,
                            width: CGFloat(width),
                            height: CGFloat(height)))

        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(gray: foreground, alpha: 1))
        let path = CGMutablePath()
        path.move(to: quad.topLeft)
        path.addLine(to: quad.topRight)
        path.addLine(to: quad.bottomRight)
        path.addLine(to: quad.bottomLeft)
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
        context.restoreGState()

        guard let image = context.makeImage() else {
            fatalError("无法生成测试图像")
        }
        return image
    }

    /// 左暗右亮的照明渐变，中间叠一块中灰「文档」矩形。用于验证增强不是空操作。
    static func lightingGradient(size: CGSize) -> CGImage {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("无法创建测试用位图上下文")
        }

        for x in 0..<width {
            let t = CGFloat(x) / CGFloat(max(1, width - 1))
            let level = 0.12 + (0.95 - 0.12) * t
            context.setFillColor(CGColor(gray: level, alpha: 1))
            context.fill(CGRect(x: CGFloat(x), y: 0,
                                width: 1, height: CGFloat(height)))
        }

        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: CGFloat(width) * 0.2,
                            y: CGFloat(height) * 0.2,
                            width: CGFloat(width) * 0.6,
                            height: CGFloat(height) * 0.6))

        guard let image = context.makeImage() else {
            fatalError("无法生成测试图像")
        }
        return image
    }

    /// 读取图像某点的亮度（0...255，行 0 为图像顶部）。
    static func luminance(_ image: CGImage, x: Int, y: Int) -> Int {
        let width = image.width
        let height = image.height
        precondition(x >= 0 && x < width && y >= 0 && y < height)
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
                                           width: CGFloat(width),
                                           height: CGFloat(height)))
        }
        let index = (y * width + x) * 4
        let red = Int(pixels[index])
        let green = Int(pixels[index + 1])
        let blue = Int(pixels[index + 2])
        return (red + green + blue) / 3
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// RGBA8 像素字节，用于“像素完全一致”和确定性断言。
    static func rgbaBytes(_ image: CGImage) -> [UInt8] {
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
                                           width: CGFloat(width),
                                           height: CGFloat(height)))
        }
        return pixels
    }

    /// 白底黑线的规则网格。`amplitude` > 0 时水平/竖直网格线按正弦弯曲，
    /// 用来构造可重复的「弯曲书页」测试图；0 表示平直网格。
    static func gridPage(size: CGSize,
                         columns: Int = 6,
                         rows: Int = 5,
                         lineWidth: CGFloat = 2,
                         amplitude: CGFloat = 0) -> CGImage {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("无法创建测试用位图上下文")
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0,
                            width: CGFloat(width), height: CGFloat(height)))
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        let usableWidth = max(1, CGFloat(width) - 2 * lineWidth)
        let usableHeight = max(1, CGFloat(height) - 2 * lineWidth)
        let maxAmplitude = min(amplitude, min(usableWidth, usableHeight) * 0.12)

        for row in 0..<max(1, rows) {
            let fraction = rows <= 1 ? 0.5 : CGFloat(row) / CGFloat(rows - 1)
            let baseY = lineWidth + fraction * usableHeight
            let path = CGMutablePath()
            for x in stride(from: CGFloat(lineWidth), through: CGFloat(width) - lineWidth,
                            by: 2) {
                let unit = (x - lineWidth) / usableWidth
                let y = baseY + maxAmplitude * CGFloat(sin(Double.pi * Double(unit)))
                if x == lineWidth {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.addPath(path)
            context.strokePath()
        }

        for column in 0..<max(1, columns) {
            let fraction = columns <= 1 ? 0.5 : CGFloat(column) / CGFloat(columns - 1)
            let baseX = lineWidth + fraction * usableWidth
            let path = CGMutablePath()
            for y in stride(from: CGFloat(lineWidth), through: CGFloat(height) - lineWidth,
                            by: 2) {
                let unit = (y - lineWidth) / usableHeight
                let x = baseX + maxAmplitude * CGFloat(sin(Double.pi * Double(unit)))
                if y == lineWidth {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.addPath(path)
            context.strokePath()
        }

        context.restoreGState()
        guard let image = context.makeImage() else {
            fatalError("无法生成测试网格图像")
        }
        return image
    }

    /// 白底 + 居中的黑色方块，用于验证网格展平把标记移到预期位置。
    static func markerPage(size: CGSize,
                           center: CGPoint,
                           markerSide: CGFloat = 40) -> CGImage {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("无法创建测试用位图上下文")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0,
                            width: CGFloat(width), height: CGFloat(height)))
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: center.x - markerSide / 2,
                            y: center.y - markerSide / 2,
                            width: markerSide,
                            height: markerSide))
        context.restoreGState()

        guard let image = context.makeImage() else {
            fatalError("无法生成测试标记图像")
        }
        return image
    }
}
