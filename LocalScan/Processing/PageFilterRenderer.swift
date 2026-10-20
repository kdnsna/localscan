import CoreGraphics
import CoreImage

/// 页面显示滤镜。`.original` 直接返回输入图像本身，保证像素级保真。
final class PageFilterRenderer {
    static let shared = PageFilterRenderer()

    private let context = CIContext()

    func apply(_ filter: PageFilter, to image: CGImage) -> CGImage? {
        switch filter {
        case .original:
            return image
        case .grayscale:
            guard let gray = monochrome(CIImage(cgImage: image)) else { return nil }
            return render(gray)
        case .blackWhite:
            guard let gray = monochrome(CIImage(cgImage: image)),
                  let thresholded = threshold(gray) else { return nil }
            return render(thresholded)
        }
    }

    private func monochrome(_ image: CIImage) -> CIImage? {
        guard let filter = CIFilter(name: "CIPhotoEffectMono") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage
    }

    private func threshold(_ image: CIImage) -> CIImage? {
        if let filter = CIFilter(name: "CIColorThreshold") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(0.5, forKey: "inputThreshold")
            if let output = filter.outputImage { return output }
        }

        // 系统阈值滤镜不可用时的确定性回退：灰度 * 100 - 50，再 clamp 到 [0,1]。
        guard let matrix = CIFilter(name: "CIColorMatrix"),
              let clamp = CIFilter(name: "CIColorClamp") else { return nil }
        matrix.setValue(image, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: 100, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: 100, z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 100, w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        matrix.setValue(CIVector(x: -50, y: -50, z: -50, w: 0), forKey: "inputBiasVector")
        guard let matrixOutput = matrix.outputImage else { return nil }

        clamp.setValue(matrixOutput, forKey: kCIInputImageKey)
        clamp.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputMinComponents")
        clamp.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputMaxComponents")
        return clamp.outputImage
    }

    private func render(_ image: CIImage) -> CGImage? {
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else { return nil }
        return context.createCGImage(image, from: extent)
    }
}
