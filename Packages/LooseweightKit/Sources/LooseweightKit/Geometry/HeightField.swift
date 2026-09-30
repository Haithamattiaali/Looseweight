import Foundation

/// Square grid lying on the table plane. Each cell stores the height of the visible surface above the table.
public struct HeightField: Sendable {
    public let plane: Plane
    public let origin: Vec3
    public let axisU: Vec3
    public let axisV: Vec3
    public let cellSize: Double
    public let columns: Int
    public let rows: Int
    /// Height in metres per cell; NaN where nothing is known.
    public internal(set) var heights: [Float]
    public internal(set) var sampleCounts: [UInt16]
    /// True where the height was filled from neighbours instead of measured.
    public internal(set) var interpolated: [Bool]
    public let framesFused: Int

    public var cellArea: Double { cellSize * cellSize }

    public func index(column: Int, row: Int) -> Int { row * columns + column }

    /// Plane coordinates (metres) of a cell centre, relative to `origin`.
    public func planeCoordinates(column: Int, row: Int) -> (s: Double, t: Double) {
        let half = Double(columns) * cellSize / 2
        return ((Double(column) + 0.5) * cellSize - half, (Double(row) + 0.5) * cellSize - half)
    }

    public func cell(containing point: Vec3) -> (column: Int, row: Int)? {
        let offset = point - origin
        let half = Double(columns) * cellSize / 2
        let column = Int(((offset.dot(axisU) + half) / cellSize).rounded(.down))
        let row = Int(((offset.dot(axisV) + half) / cellSize).rounded(.down))
        guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
        return (column, row)
    }

    /// World position of the surface top in a cell, when known.
    public func surfacePoint(column: Int, row: Int) -> Vec3? {
        let h = heights[index(column: column, row: row)]
        guard !h.isNaN else { return nil }
        let (s, t) = planeCoordinates(column: column, row: row)
        return origin + axisU * s + axisV * t + plane.normal * Double(h)
    }

    public func basePoint(column: Int, row: Int) -> Vec3 {
        let (s, t) = planeCoordinates(column: column, row: row)
        return origin + axisU * s + axisV * t
    }

    /// Share of cells inside the grid that hold a measured (not interpolated) height.
    public var measuredFraction: Double {
        let measured = zip(heights, interpolated).filter { !$0.0.isNaN && !$0.1 }.count
        return Double(measured) / Double(max(heights.count, 1))
    }
}

/// Accumulates depth frames (one or many, from a moving phone) into a `HeightField`.
public struct HeightFieldBuilder: Sendable {
    public let plane: Plane
    public let origin: Vec3
    public let cellSize: Double
    public let columns: Int
    public let rows: Int
    private let axisU: Vec3
    private let axisV: Vec3
    private var samples: [[Float]]
    private var frames = 0

    /// - Parameters:
    ///   - plane: table plane, oriented so the camera is on the positive side.
    ///   - center: a point near the middle of the plate; projected onto the plane.
    ///   - size: side of the square area to cover, metres.
    ///   - cellSize: grid spacing, metres.
    public init(plane: Plane, center: Vec3, size: Double = 0.7, cellSize: Double = 0.004) {
        self.plane = plane
        self.origin = plane.projected(center)
        self.cellSize = cellSize
        let count = max(Int((size / cellSize).rounded()), 1)
        self.columns = count
        self.rows = count
        let (u, v) = plane.basis
        self.axisU = u
        self.axisV = v
        self.samples = Array(repeating: [], count: count * count)
    }

    /// Adds a depth frame. Points below the table (beyond `belowTolerance`) or implausibly high are ignored.
    public mutating func add(
        _ frame: DepthFrame,
        stride: Int = 1,
        minimumConfidence: UInt8 = 1,
        belowTolerance: Double = 0.02,
        maximumHeight: Double = 0.30
    ) {
        let half = Double(columns) * cellSize / 2
        frame.forEachValidPixel(stride: stride, minimumConfidence: minimumConfidence, range: 0.08...2.5) { _, _, point in
            let h = plane.height(of: point)
            guard h > -belowTolerance, h < maximumHeight else { return }
            let offset = point - origin
            let column = Int(((offset.dot(axisU) + half) / cellSize).rounded(.down))
            let row = Int(((offset.dot(axisV) + half) / cellSize).rounded(.down))
            guard column >= 0, column < columns, row >= 0, row < rows else { return }
            samples[row * columns + column].append(Float(h))
        }
        frames += 1
    }

    /// - Parameters:
    ///   - surfacePercentile: which sample represents the cell top (high values reject side walls and noise below).
    ///   - fillPasses: hole-filling passes; each pass fills cells with at least 3 known neighbours.
    public func build(surfacePercentile: Double = 0.7, fillPasses: Int = 5) -> HeightField {
        var heights = [Float](repeating: .nan, count: samples.count)
        var counts = [UInt16](repeating: 0, count: samples.count)
        for (index, values) in samples.enumerated() where !values.isEmpty {
            heights[index] = Float(values.percentile(surfacePercentile) ?? .nan)
            counts[index] = UInt16(min(values.count, Int(UInt16.max)))
        }
        var interpolated = [Bool](repeating: false, count: samples.count)
        for _ in 0..<fillPasses {
            var next = heights
            var changed = false
            for row in 0..<rows {
                for column in 0..<columns where heights[row * columns + column].isNaN {
                    var sum: Float = 0
                    var known = 0
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let r = row + dy, c = column + dx
                            guard r >= 0, r < rows, c >= 0, c < columns else { continue }
                            let value = heights[r * columns + c]
                            if !value.isNaN { sum += value; known += 1 }
                        }
                    }
                    if known >= 3 {
                        next[row * columns + column] = sum / Float(known)
                        interpolated[row * columns + column] = true
                        changed = true
                    }
                }
            }
            heights = next
            if !changed { break }
        }
        return HeightField(
            plane: plane,
            origin: origin,
            axisU: axisU,
            axisV: axisV,
            cellSize: cellSize,
            columns: columns,
            rows: rows,
            heights: heights,
            sampleCounts: counts,
            interpolated: interpolated,
            framesFused: frames
        )
    }
}
