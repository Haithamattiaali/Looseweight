import Foundation

/// Binary mask over the upright photo, stored at its own resolution and looked up with normalised coordinates.
public struct RegionMask: Sendable, Hashable {
    public let width: Int
    public let height: Int
    public private(set) var bits: [Bool]

    public init(width: Int, height: Int, bits: [Bool]) {
        precondition(bits.count == width * height, "mask size mismatch")
        self.width = width
        self.height = height
        self.bits = bits
    }

    /// Mask of one label in a label map (for example an on-device instance segmentation).
    public init(labels: [UInt8], width: Int, height: Int, label: UInt8) {
        self.init(width: width, height: height, bits: labels.map { $0 == label })
    }

    /// Rasterises a polygon given in upright photo pixels (`photoWidth × photoHeight`).
    public init(polygon: [(x: Double, y: Double)], photoWidth: Int, photoHeight: Int, resolution: Int = 320) {
        let scale = Double(resolution) / Double(max(photoWidth, photoHeight))
        let width = max(Int((Double(photoWidth) * scale).rounded()), 1)
        let height = max(Int((Double(photoHeight) * scale).rounded()), 1)
        var bits = [Bool](repeating: false, count: width * height)
        let points = polygon.map { (x: $0.x * scale, y: $0.y * scale) }
        if points.count >= 3 {
            for row in 0..<height {
                let y = Double(row) + 0.5
                var crossings: [Double] = []
                for index in points.indices {
                    let a = points[index]
                    let b = points[(index + 1) % points.count]
                    if (a.y <= y && b.y > y) || (b.y <= y && a.y > y) {
                        crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
                    }
                }
                crossings.sort()
                var pair = 0
                while pair + 1 < crossings.count {
                    let start = max(Int((crossings[pair] - 0.5).rounded(.up)), 0)
                    let end = min(Int((crossings[pair + 1] - 0.5).rounded(.down)), width - 1)
                    if start <= end {
                        for column in start...end { bits[row * width + column] = true }
                    }
                    pair += 2
                }
            }
        }
        self.init(width: width, height: height, bits: bits)
    }

    public func contains(normalized point: (u: Double, v: Double)) -> Bool {
        guard point.u >= 0, point.u < 1, point.v >= 0, point.v < 1 else { return false }
        let column = min(Int(point.u * Double(width)), width - 1)
        let row = min(Int(point.v * Double(height)), height - 1)
        return bits[row * width + column]
    }

    public var coverage: Double {
        Double(bits.filter { $0 }.count) / Double(max(bits.count, 1))
    }

    public var isEmpty: Bool { !bits.contains(true) }

    /// Normalised bounding box (x, y, width, height) of the set bits.
    public var normalizedBounds: (x: Double, y: Double, width: Double, height: Double)? {
        var minColumn = width, maxColumn = -1, minRow = height, maxRow = -1
        for row in 0..<height {
            for column in 0..<width where bits[row * width + column] {
                minColumn = min(minColumn, column); maxColumn = max(maxColumn, column)
                minRow = min(minRow, row); maxRow = max(maxRow, row)
            }
        }
        guard maxColumn >= 0 else { return nil }
        return (Double(minColumn) / Double(width), Double(minRow) / Double(height),
                Double(maxColumn - minColumn + 1) / Double(width), Double(maxRow - minRow + 1) / Double(height))
    }

    public func union(_ other: RegionMask) -> RegionMask {
        guard other.width == width, other.height == height else {
            var result = self
            for row in 0..<height {
                for column in 0..<width where !result.bits[row * width + column] {
                    let point = ((Double(column) + 0.5) / Double(width), (Double(row) + 0.5) / Double(height))
                    if other.contains(normalized: point) { result.bits[row * width + column] = true }
                }
            }
            return result
        }
        return RegionMask(width: width, height: height, bits: zip(bits, other.bits).map { $0 || $1 })
    }
}
