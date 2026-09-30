import CoreImage
import CoreVideo
import Foundation
import ImageIO
import LooseweightKit
import Vision

/// On-device "is this food?" check with Apple Vision's image classifier. The decision itself lives in
/// `FoodPresenceDetector` (LooseweightKit); this file only turns images into labels.
enum FoodGate {
    /// All classifier labels above a small floor (the detector picks the food ones).
    static func labels(for image: CGImage, orientation: CGImagePropertyOrientation = .up) -> [ClassifierLabel] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let observations = request.results ?? []
        return observations
            .filter { $0.confidence >= 0.02 }
            .map { ClassifierLabel(label: $0.identifier, confidence: Double($0.confidence)) }
    }

    /// One-shot check for a picked library photo, off the main thread. True when it looks like food, or when
    /// Vision gave no answer at all (never block on a failure).
    static func looksLikeFood(_ image: CGImage) async -> Bool {
        await Task.detached(priority: .userInitiated) { () -> Bool in
            let found = labels(for: image)
            if found.isEmpty { return true }
            return FoodPresenceDetector.looksLikeFood(found)
        }.value
    }
}

/// Throttled live classification of ARKit camera frames. Called on the ARKit delegate queue: it copies a small
/// downscaled image right away (no ARFrame or camera buffer is kept) and classifies it on its own queue.
final class LiveFoodClassifier: @unchecked Sendable {
    private let lock = NSLock()
    private var lastTime: TimeInterval = 0
    private var busy = false
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "looseweight.foodgate", qos: .utility)
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    init(interval: TimeInterval = 0.5) {
        self.interval = interval
    }

    func reset() {
        lock.lock()
        lastTime = 0
        lock.unlock()
    }

    /// Returns quickly. `completion` runs on a background queue with the frame's labels.
    func submit(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, completion: @escaping @Sendable ([ClassifierLabel]) -> Void) {
        lock.lock()
        let due = !busy && timestamp - lastTime >= interval
        if due {
            busy = true
            lastTime = timestamp
        }
        lock.unlock()
        guard due else { return }

        guard let small = downscaled(pixelBuffer) else {
            finish()
            return
        }
        queue.async { [weak self] in
            let found = FoodGate.labels(for: small, orientation: .right)
            self?.finish()
            completion(found)
        }
    }

    private func finish() {
        lock.lock()
        busy = false
        lock.unlock()
    }

    /// A ~360 px copy of the camera image, detached from the camera's buffer pool.
    private func downscaled(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let longest = max(image.extent.width, image.extent.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 360 / longest)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent)
    }
}
