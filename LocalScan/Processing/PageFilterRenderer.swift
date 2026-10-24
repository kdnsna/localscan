import CoreGraphics
import CoreImage

/// 页面显示滤镜。`.original` 直接返回输入图像本身，保证像素级保真。
final class PageFilterRenderer {
    static let shared = PageFilterRenderer()

    private let context = CIContext()

    /// 背景估计用的最长边（像素）。远小于输出尺寸，只保留低频光照。
    private let backgroundMaxDimension: CGFloat = 96
    /// 背景估计的下限，避免除零 / 近零除法放大噪声。
    private let backgroundEpsilon: CGFloat = 0.02
    /// 归一化后的纸面增益：留一点高光余量，避免直接削顶成纯白。
    private let normalizationGain: CGFloat = 0.92

    func apply(_ filter: PageFilter, to image: CGImage) -> CGImage? {
        switch filter {
        case .original:
            return image
        case .enhance:
            guard let enhanced = enhance(CIImage(cgImage: image)) else { return nil }
            return render(enhanced)
        case .grayscale:
            guard let gray = monochrome(CIImage(cgImage: image)) else { return nil }
            return render(gray)
        case .blackWhite:
            let source = CIImage(cgImage: image)
            guard let normalized = enhance(source),
                  let gray = monochrome(normalized),
                  let thresholded = threshold(gray) else { return nil }
            return render(thresholded)
        }
    }

    /// 经典「增强」：低分辨率估计背景 / 光照 → 除法归一化 → 温和对比度 + 轻锐化。
    /// 全部使用固定参数的 Core Image 滤镜；不做生成、修补或笔画增强。
    private func enhance(_ image: CIImage) -> CIImage? {
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else { return nil }

        // 1. 重降采样 + 模糊，只留下低频光照。先 clamp 再模糊，避免边缘被当成透明而变暗。
        let longestSide = max(extent.width, extent.height)
        let scale = min(1, backgroundMaxDimension / longestSide)
        guard let downscale = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        downscale.setValue(image, forKey: kCIInputImageKey)
        downscale.setValue(scale, forKey: kCIInputScaleKey)
        downscale.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let small = downscale.outputImage else { return nil }

        let smallExtent = small.extent
        guard smallExtent.width > 0, smallExtent.height > 0,
              let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        let radius = max(2, min(smallExtent.width, smallExtent.height) * 0.08)
        blur.setValue(small.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(radius, forKey: kCIInputRadiusKey)
        guard let blurredSmall = blur.outputImage?.cropped(to: smallExtent) else { return nil }

        // 2. 上采样回原尺寸，得到逐像素的低频背景估计。
        guard let upscale = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        upscale.setValue(blurredSmall, forKey: kCIInputImageKey)
        upscale.setValue(1.0 / scale, forKey: kCIInputScaleKey)
        upscale.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let background = upscale.outputImage?.cropped(to: extent) else { return nil }

        // 3. 把背景夹到 [epsilon, 1]，避免近零 / 负值除法放大噪声。
        guard let lift = CIFilter(name: "CIColorClamp") else { return nil }
        lift.setValue(background, forKey: kCIInputImageKey)
        lift.setValue(CIVector(x: backgroundEpsilon,
                               y: backgroundEpsilon,
                               z: backgroundEpsilon,
                               w: 0),
                      forKey: "inputMinComponents")
        lift.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputMaxComponents")
        guard let safeBackground = lift.outputImage else { return nil }

        // CIDivideBlendMode 输出 background / image；把原图放在 background 槽，
        // 得到 result = 原图 / 光照估计（下限 epsilon）。
        guard let divide = CIFilter(name: "CIDivideBlendMode") else { return nil }
        divide.setValue(safeBackground, forKey: kCIInputImageKey)
        divide.setValue(image, forKey: kCIInputBackgroundImageKey)
        guard let normalized = divide.outputImage?.cropped(to: extent) else { return nil }

        // 4. 固定增益留出高光余量，然后温和对比度 + 轻锐化，最后 clamp 到 [0, 1]。
        guard let gain = CIFilter(name: "CIColorMatrix") else { return nil }
        gain.setValue(normalized, forKey: kCIInputImageKey)
        gain.setValue(CIVector(x: normalizationGain, y: 0, z: 0, w: 0),
                      forKey: "inputRVector")
        gain.setValue(CIVector(x: 0, y: normalizationGain, z: 0, w: 0),
                      forKey: "inputGVector")
        gain.setValue(CIVector(x: 0, y: 0, z: normalizationGain, w: 0),
                      forKey: "inputBVector")
        gain.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        guard let leveled = gain.outputImage else { return nil }

        guard let controls = CIFilter(name: "CIColorControls") else { return nil }
        controls.setValue(leveled, forKey: kCIInputImageKey)
        controls.setValue(1.08, forKey: kCIInputContrastKey)
        controls.setValue(0.0, forKey: kCIInputBrightnessKey)
        controls.setValue(1.0, forKey: kCIInputSaturationKey)
        guard let toned = controls.outputImage else { return nil }

        guard let sharpen = CIFilter(name: "CISharpenLuminance") else { return nil }
        sharpen.setValue(toned, forKey: kCIInputImageKey)
        sharpen.setValue(0.3, forKey: kCIInputSharpnessKey)
        guard let sharpened = sharpen.outputImage else { return nil }

        guard let clamp = CIFilter(name: "CIColorClamp") else { return nil }
        clamp.setValue(sharpened, forKey: kCIInputImageKey)
        clamp.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputMinComponents")
        clamp.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputMaxComponents")
        return clamp.outputImage?.cropped(to: extent) ?? sharpened.cropped(to: extent)
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
