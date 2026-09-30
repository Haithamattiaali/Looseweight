import LooseweightKit
import UIKit

/// Image 2 for the model: the photo with the phone's numbered regions and a 5 cm scale bar.
enum OverlayRenderer {
    static let palette: [UIColor] = [.systemTeal, .systemOrange, .systemPink, .systemIndigo, .systemGreen, .systemYellow, .systemPurple, .systemRed]

    static func render(photo: CGImage, regions: [OnDeviceRegion], pixelsPerCmAtFullSize: Double?, fullWidth: Int, longEdge: CGFloat = 1024) -> CGImage? {
        let scale = longEdge / CGFloat(max(photo.width, photo.height))
        let size = CGSize(width: CGFloat(photo.width) * scale, height: CGFloat(photo.height) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIImage(cgImage: photo).draw(in: CGRect(origin: .zero, size: size))

            for (index, region) in regions.enumerated() {
                let color = palette[index % palette.count]
                if let maskImage = maskImage(region.mask, color: color.withAlphaComponent(0.33)) {
                    cg.saveGState()
                    cg.interpolationQuality = .none
                    UIImage(cgImage: maskImage).draw(in: CGRect(origin: .zero, size: size))
                    cg.restoreGState()
                }
                if let box = region.mask.normalizedBounds {
                    let center = CGPoint(x: (box.x + box.width / 2) * size.width, y: (box.y + box.height / 2) * size.height)
                    drawBadge("\(region.number)", at: center, color: color, in: cg)
                }
            }

            if let pixelsPerCm = pixelsPerCmAtFullSize {
                let length = CGFloat(pixelsPerCm * 5) * size.width / CGFloat(fullWidth)
                let origin = CGPoint(x: 24, y: size.height - 36)
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(6)
                cg.setLineCap(.round)
                cg.move(to: origin)
                cg.addLine(to: CGPoint(x: origin.x + length, y: origin.y))
                cg.strokePath()
                cg.setStrokeColor(UIColor.black.cgColor)
                cg.setLineWidth(2)
                cg.move(to: origin)
                cg.addLine(to: CGPoint(x: origin.x + length, y: origin.y))
                cg.strokePath()
                let label = NSAttributedString(string: "5 cm", attributes: [
                    .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .strokeColor: UIColor.black,
                    .strokeWidth: -3,
                ])
                label.draw(at: CGPoint(x: origin.x, y: origin.y - 30))
            }
        }
        return image.cgImage
    }

    private static func maskImage(_ mask: RegionMask, color: UIColor) -> CGImage? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        var pixels = [UInt8](repeating: 0, count: mask.width * mask.height * 4)
        for (index, set) in mask.bits.enumerated() where set {
            pixels[index * 4] = UInt8(red * alpha * 255)
            pixels[index * 4 + 1] = UInt8(green * alpha * 255)
            pixels[index * 4 + 2] = UInt8(blue * alpha * 255)
            pixels[index * 4 + 3] = UInt8(alpha * 255)
        }
        return pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: mask.width, height: mask.height, bitsPerComponent: 8, bytesPerRow: mask.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
    }

    private static func drawBadge(_ text: String, at center: CGPoint, color: UIColor, in context: CGContext) {
        let radius: CGFloat = 20
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        let label = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 22, weight: .heavy),
            .foregroundColor: UIColor.white,
        ])
        let size = label.size()
        label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }
}
