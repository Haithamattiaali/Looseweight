import CoreGraphics
import ImageIO
import LooseweightKit
import UIKit
import UniformTypeIdentifiers

enum ImageTools {
    /// Largest image the model reads without downscaling (~3.5 MP, long edge ≤ 2576), so its pixel
    /// coordinates match ours exactly.
    static let modelMaxPixels = 3_500_000.0
    static let modelMaxLongEdge = 2_576.0

    static func cgImage(_ image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage, image.imageOrientation == .up { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }

    static func sizeForModel(width: Int, height: Int) -> CGSize {
        let w = Double(width), h = Double(height)
        let scale = min(1, modelMaxLongEdge / max(w, h), (modelMaxPixels / (w * h)).squareRoot())
        return CGSize(width: (w * scale).rounded(.down), height: (h * scale).rounded(.down))
    }

    static func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = max(Int(size.width), 1), height = max(Int(size.height), 1)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func jpeg(_ image: CGImage, quality: Double = 0.85) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// 8-bit grayscale copy with the given long edge, for the sharpness check.
    static func grayscale(_ image: CGImage, longEdge: Int = 512) -> (pixels: [UInt8], width: Int, height: Int)? {
        let scale = Double(longEdge) / Double(max(image.width, image.height))
        let width = max(Int(Double(image.width) * scale), 3), height = max(Int(Double(image.height) * scale), 3)
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (pixels, width, height) : nil
    }
}

/// Serves `zoom_photo`: crops the full-resolution upright photo for a region given in model-image pixels.
struct PhotoZoomer: PhotoZooming, @unchecked Sendable {
    let fullImage: CGImage
    let modelSize: CGSize

    func zoom(x: Double, y: Double, width: Double, height: Double) async -> Data? {
        let scaleX = Double(fullImage.width) / modelSize.width
        let scaleY = Double(fullImage.height) / modelSize.height
        var rect = CGRect(x: x * scaleX, y: y * scaleY, width: width * scaleX, height: height * scaleY).integral
        rect = rect.intersection(CGRect(x: 0, y: 0, width: fullImage.width, height: fullImage.height))
        guard rect.width >= 8, rect.height >= 8, let crop = fullImage.cropping(to: rect) else { return nil }
        let limit = 1_568.0
        let scale = min(1, limit / Double(max(crop.width, crop.height)))
        let target = CGSize(width: Double(crop.width) * scale, height: Double(crop.height) * scale)
        guard let output = scale < 1 ? ImageTools.resized(crop, to: target) : crop else { return nil }
        return ImageTools.jpeg(output, quality: 0.9)
    }
}
