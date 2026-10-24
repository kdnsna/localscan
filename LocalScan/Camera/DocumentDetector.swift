import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Vision
import os

/// Vision 的归一化角点（左下原点，y 向上）-> Quad（左上原点，y 向下）。
/// 保持 Vision 给出的 TL、TR、BR、BL 顺序，纯函数，便于单测。
enum DocumentDetectorGeometry {
    static func quad(fromVisionPoints points: [CGPoint]) -> Quad {
        guard points.count == 4 else { return .zero }
        let flipped = points.map { CGPoint(x: $0.x, y: 1 - $0.y) }
        return Quad(topLeft: flipped[0], topRight: flipped[1],
                    bottomRight: flipped[2], bottomLeft: flipped[3])
    }
}

/// 在 CVPixelBuffer 上跑 VNDetectDocumentSegmentationRequest。
/// 同一时刻只处理一帧：上一帧还在跑时直接丢帧，避免积压。
final class DocumentDetector {
    private let queue = DispatchQueue(label: "com.kdnsna.localscan.document-detector",
                                      qos: .userInitiated)
    private let lock = NSLock()
    private let signposter = OSSignposter(subsystem: "com.kdnsna.localscan",
                                          category: "DocumentDetection")
    private var isDetecting = false

    @discardableResult
    func detect(in pixelBuffer: CVPixelBuffer,
                orientation: CGImagePropertyOrientation = .right,
                completion: @escaping (Quad?) -> Void) -> Bool {
        lock.lock()
        if isDetecting {
            lock.unlock()
            return false
        }
        isDetecting = true
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            let signpostID = self.signposter.makeSignpostID()
            let interval = self.signposter.beginInterval("DocumentDetection", id: signpostID)
            var detected: Quad?
            let request = VNDetectDocumentSegmentationRequest()
            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                    orientation: orientation,
                                                    options: [:])
                try handler.perform([request])
                if let observation = request.results?.first {
                    let quad = DocumentDetectorGeometry.quad(
                        fromVisionPoints: [observation.topLeft,
                                           observation.topRight,
                                           observation.bottomRight,
                                           observation.bottomLeft])
                    if DocumentQuadDetector.isValid(quad,
                                                    imageSize: CGSize(width: 1, height: 1)) {
                        detected = quad
                    }
                }
            } catch {
                detected = nil
            }
            self.signposter.endInterval("DocumentDetection", interval)

            self.lock.lock()
            self.isDetecting = false
            self.lock.unlock()
            DispatchQueue.main.async { completion(detected) }
        }
        return true
    }
}
