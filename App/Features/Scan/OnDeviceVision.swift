import CoreGraphics
import LooseweightKit
import Vision

/// What Apple's on-device Vision framework finds in the photo before any AI call.
struct OnDeviceVisionResult {
    var regions: [RegionMask] = []
    var labels: [ClassifierLabel] = []
    var text: [String] = []
    var barcodes: [String] = []
}

enum OnDeviceVision {
    /// Runs segmentation, classification, text and barcode recognition in one pass (off the main thread).
    static func analyze(_ image: CGImage) async -> OnDeviceVisionResult {
        await Task.detached(priority: .userInitiated) { run(image) }.value
    }

    private static func run(_ image: CGImage) -> OnDeviceVisionResult {
        let segmentation = VNGenerateForegroundInstanceMaskRequest()
        let classification = VNClassifyImageRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        let barcodes = VNDetectBarcodesRequest()
        barcodes.symbologies = [.ean13, .ean8, .upce, .code128, .qr]

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        var result = OnDeviceVisionResult()
        for request in [segmentation, classification, text, barcodes] as [VNRequest] {
            try? handler.perform([request])
        }

        if let observation = segmentation.results?.first {
            result.regions = regions(from: observation)
        }
        result.labels = (classification.results ?? [])
            .filter { $0.confidence >= 0.08 }
            .prefix(8)
            .map { ClassifierLabel(label: $0.identifier.replacingOccurrences(of: "_", with: " "), confidence: Double($0.confidence)) }
        result.text = (text.results ?? [])
            .compactMap { $0.topCandidates(1).first }
            .filter { $0.confidence >= 0.4 }
            .map(\.string)
        result.barcodes = Array(Set((barcodes.results ?? []).compactMap(\.payloadStringValue).filter { $0.allSatisfy(\.isNumber) }))
        return result
    }

    /// One mask per separate object, ignoring specks under 1 % of the photo.
    private static func regions(from observation: VNInstanceMaskObservation) -> [RegionMask] {
        let buffer = observation.instanceMask
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var labels = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let source = base.advanced(by: row * rowBytes).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width { labels[row * width + column] = source[column] }
        }
        return observation.allInstances
            .map { RegionMask(labels: labels, width: width, height: height, label: UInt8(clamping: $0)) }
            .filter { $0.coverage >= 0.01 }
            .sorted { $0.coverage > $1.coverage }
    }
}
