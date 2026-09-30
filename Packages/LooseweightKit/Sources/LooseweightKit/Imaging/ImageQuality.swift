import Foundation

public enum ImageQuality {
    /// Below this Laplacian variance (8-bit grayscale, long edge ≈ 512 px) a photo is treated as blurry.
    public static let blurThreshold = 45.0

    /// Variance of the 4-neighbour Laplacian — a standard sharpness score. Higher is sharper.
    public static func laplacianVariance(gray: [UInt8], width: Int, height: Int) -> Double {
        guard width >= 3, height >= 3, gray.count == width * height else { return 0 }
        var sum = 0.0, sumSquares = 0.0
        var count = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = Double(gray[y * width + x])
                let laplacian = Double(gray[(y - 1) * width + x]) + Double(gray[(y + 1) * width + x])
                    + Double(gray[y * width + x - 1]) + Double(gray[y * width + x + 1]) - 4 * center
                sum += laplacian
                sumSquares += laplacian * laplacian
                count += 1
            }
        }
        let mean = sum / count
        return sumSquares / count - mean * mean
    }

    /// Mean brightness 0...255.
    public static func meanBrightness(gray: [UInt8]) -> Double {
        guard !gray.isEmpty else { return 0 }
        return Double(gray.reduce(0) { $0 + Int($1) }) / Double(gray.count)
    }

    /// Plain-English problems worth a retake prompt.
    public static func warnings(gray: [UInt8], width: Int, height: Int) -> [String] {
        var problems: [String] = []
        if laplacianVariance(gray: gray, width: width, height: height) < blurThreshold { problems.append("the photo looks blurry") }
        let brightness = meanBrightness(gray: gray)
        if brightness < 45 { problems.append("the photo is very dark") }
        if brightness > 235 { problems.append("the photo is overexposed") }
        return problems
    }
}
