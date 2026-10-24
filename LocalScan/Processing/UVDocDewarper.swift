import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation
import Metal

private enum UVDocDewarperError: Error {
    case metalUnavailable
    case invalidGridShape
    case predictionFailed(String)
}

/// 可选的端上 UVDoc 展平器。模型或 Metal 不可用、推理失败时返回 nil，由管线保留透视结果。
final class UVDocDewarper: Dewarping {
    static let featureFlagKey = "LocalScan.feature.uvdocDewarper"
    static let modelResourceName = "UVDocCoreML"
    static let modelResourceExtension = "mlmodelc"

    static var featureFlagEnabled: Bool {
        UserDefaults.standard.bool(forKey: featureFlagKey)
    }

    static let modelInputWidth = 488
    static let modelInputHeight = 712

    private let model: MLModel?
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?
    private let ciContext: CIContext?
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    var isAvailable: Bool {
        model != nil && device != nil && commandQueue != nil && pipeline != nil && ciContext != nil
    }

    convenience init(bundle: Bundle = .main,
                     featureFlagEnabled: Bool = UVDocDewarper.featureFlagEnabled) {
        guard featureFlagEnabled,
              let url = bundle.url(forResource: Self.modelResourceName,
                                   withExtension: Self.modelResourceExtension) else {
            self.init()
            return
        }
        do {
            try self.init(modelURL: url)
        } catch {
            self.init()
        }
    }

    private init() {
        model = nil
        device = nil
        commandQueue = nil
        pipeline = nil
        ciContext = nil
    }

    private init(modelURL: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: modelURL, configuration: configuration)

        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw UVDocDewarperError.metalUnavailable
        }
        self.device = device
        self.commandQueue = commandQueue
        ciContext = CIContext(mtlDevice: device)

        let library = try device.makeLibrary(source: Self.kernelSource, options: nil)
        guard let function = library.makeFunction(name: "uvdoc_dewarp") else {
            throw UVDocDewarperError.metalUnavailable
        }
        pipeline = try device.makeComputePipelineState(function: function)
    }

    func dewarp(_ image: CGImage) -> CGImage? {
        guard let model, let device, let commandQueue, let pipeline, let ciContext else {
            return nil
        }
        do {
            return try perform(image,
                               model: model,
                               device: device,
                               commandQueue: commandQueue,
                               pipeline: pipeline,
                               ciContext: ciContext)
        } catch {
            return nil
        }
    }

    /// 同步等待 Core ML / Metal；ProcessingQueue 已在专用后台队列调用。
    private func perform(_ image: CGImage,
                         model: MLModel,
                         device: MTLDevice,
                         commandQueue: MTLCommandQueue,
                         pipeline: MTLComputePipelineState,
                         ciContext: CIContext) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 1, height > 1 else {
            throw UVDocDewarperError.predictionFailed("invalid image size")
        }
        let ciImage = CIImage(cgImage: image)

        let inputBuffer = try Self.makePixelBuffer(width: Self.modelInputWidth,
                                                   height: Self.modelInputHeight)
        let resized = ciImage.stretched(toWidth: Self.modelInputWidth,
                                        height: Self.modelInputHeight)
        ciContext.render(resized, to: inputBuffer)

        let inputValue = MLFeatureValue(pixelBuffer: inputBuffer)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["image": inputValue])
        let output = try model.prediction(from: provider)
        guard let gridArray = output.featureValue(for: "grid")?.multiArrayValue else {
            throw UVDocDewarperError.predictionFailed("missing grid output")
        }
        let grid = try Self.extractGrid(gridArray)

        let fullBuffer = try Self.makePixelBuffer(width: width, height: height)
        ciContext.render(ciImage, to: fullBuffer)

        let srcDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                               width: width,
                                                               height: height,
                                                               mipmapped: false)
        srcDesc.usage = [.shaderRead]
        let dstDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                               width: width,
                                                               height: height,
                                                               mipmapped: false)
        dstDesc.usage = [.shaderWrite]
        guard let srcTexture = device.makeTexture(descriptor: srcDesc),
              let dstTexture = device.makeTexture(descriptor: dstDesc) else {
            throw UVDocDewarperError.metalUnavailable
        }

        CVPixelBufferLockBaseAddress(fullBuffer, .readOnly)
        guard let base = CVPixelBufferGetBaseAddress(fullBuffer) else {
            CVPixelBufferUnlockBaseAddress(fullBuffer, .readOnly)
            throw UVDocDewarperError.predictionFailed("missing pixel buffer storage")
        }
        srcTexture.replaceRegion(MTLRegionMake2D(0, 0, width, height),
                                 mipmapLevel: 0,
                                 withBytes: base,
                                 bytesPerRow: CVPixelBufferGetBytesPerRow(fullBuffer))
        CVPixelBufferUnlockBaseAddress(fullBuffer, .readOnly)

        var params = DewarpParams(outW: UInt32(width), outH: UInt32(height),
                                  gridW: UInt32(grid.width), gridH: UInt32(grid.height))
        let gridBuffer = grid.values.withUnsafeBufferPointer { values -> MTLBuffer? in
            guard let baseAddress = values.baseAddress else { return nil }
            return device.makeBuffer(bytes: baseAddress,
                                     length: values.count * MemoryLayout<SIMD2<Float>>.stride,
                                     options: .storageModeShared)
        }
        guard let gridBuffer,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw UVDocDewarperError.metalUnavailable
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(srcTexture, index: 0)
        encoder.setTexture(dstTexture, index: 1)
        encoder.setBuffer(gridBuffer, offset: 0, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<DewarpParams>.size, index: 1)
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(width: (width + 15) / 16,
                                   height: (height + 15) / 16,
                                   depth: 1)
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status != .error else {
            throw UVDocDewarperError.predictionFailed("Metal command failed")
        }

        let outputBytesPerRow = width * 4
        var outputBytes = [UInt8](repeating: 0, count: outputBytesPerRow * height)
        outputBytes.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            dstTexture.getBytes(baseAddress,
                                bytesPerRow: outputBytesPerRow,
                                from: MTLRegionMake2D(0, 0, width, height),
                                mipmapLevel: 0)
        }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedFirst.rawValue
        let data = outputBytes.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let output = CGImage(width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bitsPerPixel: 32,
                                   bytesPerRow: outputBytesPerRow,
                                   space: srgb,
                                   bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                                   provider: provider,
                                   decode: nil,
                                   shouldInterpolate: false,
                                   intent: .defaultIntent) else {
            throw UVDocDewarperError.predictionFailed("failed to create output image")
        }
        return output
    }

    private struct Grid {
        var width: Int
        var height: Int
        var values: [SIMD2<Float>]
    }

    private static func extractGrid(_ array: MLMultiArray) throws -> Grid {
        guard array.shape.count == 4,
              array.shape[0].intValue == 1,
              array.shape[1].intValue == 2,
              array.dataType == .float16 else {
            throw UVDocDewarperError.invalidGridShape
        }
        let gridHeight = array.shape[2].intValue
        let gridWidth = array.shape[3].intValue
        guard gridWidth > 1, gridHeight > 1 else {
            throw UVDocDewarperError.invalidGridShape
        }

        let channelStride = array.strides[1].intValue
        let heightStride = array.strides[2].intValue
        let widthStride = array.strides[3].intValue
        let base = array.dataPointer.assumingMemoryBound(to: UInt16.self)

        func read(_ channel: Int, _ row: Int, _ column: Int) -> Float {
            let index = channel * channelStride + row * heightStride + column * widthStride
            return Float(Float16(bitPattern: base[index]))
        }

        var values = [SIMD2<Float>](repeating: .zero, count: gridHeight * gridWidth)
        for row in 0..<gridHeight {
            for column in 0..<gridWidth {
                values[row * gridWidth + column] = SIMD2<Float>(read(0, row, column),
                                                                 read(1, row, column))
            }
        }
        return Grid(width: gridWidth, height: gridHeight, values: values)
    }

    private static func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA,
                                         attributes as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw UVDocDewarperError.predictionFailed("CVPixelBufferCreate failed: \(status)")
        }
        return buffer
    }

    private static let kernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct DewarpParams {
        uint outW;
        uint outH;
        uint gridW;
        uint gridH;
    };

    static float4 fetchZero(texture2d<float, access::read> texture,
                            int x, int y, uint width, uint height) {
        if (x < 0 || y < 0 || x >= int(width) || y >= int(height)) return float4(0.0);
        return texture.read(uint2(uint(x), uint(y)));
    }

    kernel void uvdoc_dewarp(texture2d<float, access::read> src [[texture(0)]],
                             texture2d<float, access::write> dst [[texture(1)]],
                             constant float2* grid [[buffer(0)]],
                             constant DewarpParams& p [[buffer(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.outW || gid.y >= p.outH) return;

        float u = (p.outW > 1) ? float(gid.x) * float(p.gridW - 1) / float(p.outW - 1) : 0.0f;
        float v = (p.outH > 1) ? float(gid.y) * float(p.gridH - 1) / float(p.outH - 1) : 0.0f;
        int x0 = int(floor(u));
        int y0 = int(floor(v));
        int x1 = min(x0 + 1, int(p.gridW) - 1);
        int y1 = min(y0 + 1, int(p.gridH) - 1);
        float fx = u - float(x0);
        float fy = v - float(y0);

        float2 g00 = grid[y0 * p.gridW + x0];
        float2 g10 = grid[y0 * p.gridW + x1];
        float2 g01 = grid[y1 * p.gridW + x0];
        float2 g11 = grid[y1 * p.gridW + x1];
        float2 g = mix(mix(g00, g10, fx), mix(g01, g11, fx), fy);
        float sx = (g.x + 1.0f) * 0.5f * float(p.outW - 1);
        float sy = (g.y + 1.0f) * 0.5f * float(p.outH - 1);

        int ix0 = int(floor(sx));
        int iy0 = int(floor(sy));
        float ax = sx - float(ix0);
        float ay = sy - float(iy0);
        float4 c00 = fetchZero(src, ix0, iy0, p.outW, p.outH);
        float4 c10 = fetchZero(src, ix0 + 1, iy0, p.outW, p.outH);
        float4 c01 = fetchZero(src, ix0, iy0 + 1, p.outW, p.outH);
        float4 c11 = fetchZero(src, ix0 + 1, iy0 + 1, p.outW, p.outH);
        float4 color = mix(mix(c00, c10, ax), mix(c01, c11, ax), ay);
        dst.write(color, gid);
    }
    """
}

private struct DewarpParams {
    var outW: UInt32
    var outH: UInt32
    var gridW: UInt32
    var gridH: UInt32
}

private extension CIImage {
    func stretched(toWidth width: Int, height: Int) -> CIImage {
        let scaleX = CGFloat(width) / extent.width
        let scaleY = CGFloat(height) / extent.height
        return transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }
}
