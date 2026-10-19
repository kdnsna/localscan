import CoreGraphics

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
}
