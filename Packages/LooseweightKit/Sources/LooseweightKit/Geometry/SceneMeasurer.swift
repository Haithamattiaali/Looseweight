import Foundation

public struct ContainerMeasurement: Codable, Hashable, Sendable {
    public var diameterCm: Double
    public var areaCm2: Double
    /// Typical height of the visible plate surface around the food (plate floor), when depth exists.
    public var floorHeightMm: Double?
    /// Height of the rim, when depth exists.
    public var rimHeightMm: Double?
}

public struct RegionMeasurement: Codable, Hashable, Sendable {
    public enum Method: String, Codable, Sendable {
        /// LiDAR height field: real volume.
        case depth
        /// ARKit table plane only: real footprint area, no height.
        case planeProjection
    }

    public var method: Method
    public var areaCm2: Double
    public var volumeAboveTableMl: Double?
    public var volumeAboveFloorMl: Double?
    public var medianHeightMm: Double?
    public var p90HeightMm: Double?
    public var maxHeightMm: Double?
    /// Share of the region's cells with a direct depth reading (the rest were interpolated).
    public var measuredShare: Double?
    public var container: ContainerMeasurement?
}

public struct ScaleReport: Codable, Hashable, Sendable {
    public var cameraHeightCm: Double
    public var tiltDegrees: Double
    /// Upright photo pixels per centimetre on the table near the image centre.
    public var pixelsPerCmAtTable: Double
    public var hasDepth: Bool
    public var depthFramesFused: Int
    public var depthCoverage: Double?
}

/// Turns on-device geometry (ARKit plane, optional LiDAR height field) into physical measurements of photo regions.
public struct SceneMeasurer: Sendable {
    public let plane: Plane
    public let photo: PhotoGeometry
    public let heightField: HeightField?
    /// Without depth, rays are intersected with a plane this far above the table (typical food mid-height).
    public let noDepthLift: Double
    public let cellSize: Double
    private let projections: [(u: Double, v: Double)?]

    public init(plane: Plane, photo: PhotoGeometry, heightField: HeightField? = nil, noDepthLift: Double = 0.012) {
        self.plane = plane.oriented(toward: photo.camera.center)
        self.photo = photo
        self.heightField = heightField
        self.noDepthLift = noDepthLift
        self.cellSize = heightField?.cellSize ?? 0.004
        if let field = heightField {
            let cameraFromWorld = photo.camera.worldFromCamera.inverse
            let intrinsics = photo.camera.intrinsics
            let width = Double(intrinsics.width), height = Double(intrinsics.height)
            var projections: [(u: Double, v: Double)?] = []
            projections.reserveCapacity(field.heights.count)
            for row in 0..<field.rows {
                for column in 0..<field.columns {
                    guard let top = field.surfacePoint(column: column, row: row),
                          let pixel = intrinsics.project(cameraFromWorld.apply(top))
                    else { projections.append(nil); continue }
                    projections.append(photo.orientation.upright(fromStored: (pixel.u / width, pixel.v / height)))
                }
            }
            self.projections = projections
        } else {
            self.projections = []
        }
    }

    public func scaleReport() -> ScaleReport? {
        let ray = photo.worldRay(uprightNormalized: (0.5, 0.5))
        guard let t = plane.intersection(origin: ray.origin, direction: ray.direction) else { return nil }
        let focal = (photo.camera.intrinsics.fx + photo.camera.intrinsics.fy) / 2
        let tilt = acos(photo.camera.forward.normalized.dot(-plane.normal).clamped(to: -1...1)) * 180 / .pi
        return ScaleReport(
            cameraHeightCm: plane.height(of: photo.camera.center) * 100,
            tiltDegrees: tilt,
            pixelsPerCmAtTable: focal / (t * 100),
            hasDepth: heightField != nil,
            depthFramesFused: heightField?.framesFused ?? 0,
            depthCoverage: heightField?.measuredFraction
        )
    }

    /// Measures one region. `container` is the plate or bowl holding it; `otherItems` are regions to leave out
    /// when reading the plate floor.
    public func measure(item: RegionMask, container: RegionMask? = nil, otherItems: RegionMask? = nil) -> RegionMeasurement {
        if let field = heightField {
            return measureWithDepth(field: field, item: item, container: container, otherItems: otherItems)
        }
        return measureOnPlane(item: item, container: container)
    }

    private func measureWithDepth(field: HeightField, item: RegionMask, container: RegionMask?, otherItems: RegionMask?) -> RegionMeasurement {
        var itemHeights: [Double] = []
        var measured = 0
        var containerCells: [Int] = []
        var floorHeights: [Double] = []

        for index in field.heights.indices {
            guard let projection = projections[index] else { continue }
            let h = Double(field.heights[index])
            let inItem = item.contains(normalized: projection)
            if inItem {
                itemHeights.append(h)
                if !field.interpolated[index] { measured += 1 }
            }
            if let container, container.contains(normalized: projection) {
                containerCells.append(index)
                if !inItem, otherItems?.contains(normalized: projection) != true {
                    floorHeights.append(h)
                }
            }
        }

        let cellAreaCm2 = field.cellArea * 10_000
        let cellAreaMl = field.cellArea * 1_000_000
        let volumeAboveTable = itemHeights.reduce(0) { $0 + max($1, 0) * cellAreaMl }
        let medianHeight = max(itemHeights.percentile(0.5) ?? 0, 0)
        let topArea = footprint(of: item, on: plane.raised(by: min(medianHeight, 0.05))).area

        var containerMeasurement: ContainerMeasurement?
        var volumeAboveFloor: Double?
        if container != nil, !containerCells.isEmpty {
            let floor = max(floorHeights.percentile(0.25) ?? 0, 0)
            let rim = floorHeights.percentile(0.95)
            volumeAboveFloor = itemHeights.reduce(0) { $0 + max($1 - floor, 0) * cellAreaMl }
            containerMeasurement = ContainerMeasurement(
                diameterCm: extent(of: containerCells.map { field.planeCoordinates(column: $0 % field.columns, row: $0 / field.columns) }) * 100,
                areaCm2: Double(containerCells.count) * cellAreaCm2,
                floorHeightMm: floorHeights.isEmpty ? nil : floor * 1000,
                rimHeightMm: rim.map { $0 * 1000 }
            )
        }

        return RegionMeasurement(
            method: .depth,
            areaCm2: topArea * 10_000,
            volumeAboveTableMl: volumeAboveTable,
            volumeAboveFloorMl: volumeAboveFloor,
            medianHeightMm: itemHeights.isEmpty ? nil : medianHeight * 1000,
            p90HeightMm: itemHeights.percentile(0.9).map { max($0, 0) * 1000 },
            maxHeightMm: itemHeights.max().map { max($0, 0) * 1000 },
            measuredShare: itemHeights.isEmpty ? nil : Double(measured) / Double(itemHeights.count),
            container: containerMeasurement
        )
    }

    private func measureOnPlane(item: RegionMask, container: RegionMask?) -> RegionMeasurement {
        let itemFootprint = footprint(of: item, on: plane.raised(by: noDepthLift))
        var containerMeasurement: ContainerMeasurement?
        if let container {
            let dish = footprint(of: container, on: plane.raised(by: 0.005))
            if dish.area > 0 {
                containerMeasurement = ContainerMeasurement(
                    diameterCm: extent(of: dish.points) * 100,
                    areaCm2: dish.area * 10_000,
                    floorHeightMm: nil,
                    rimHeightMm: nil
                )
            }
        }
        return RegionMeasurement(
            method: .planeProjection,
            areaCm2: itemFootprint.area * 10_000,
            volumeAboveTableMl: nil,
            volumeAboveFloorMl: nil,
            medianHeightMm: nil,
            p90HeightMm: nil,
            maxHeightMm: nil,
            measuredShare: nil,
            container: containerMeasurement
        )
    }

    /// Area on `surface` covered by the mask (each mask pixel's four corners are projected; exact for a plane),
    /// plus the projected corner points in plane coordinates.
    private func footprint(of mask: RegionMask, on surface: Plane) -> (area: Double, points: [(s: Double, t: Double)]) {
        let (axisU, axisV) = surface.basis
        let anchor = surface.anchor
        func corner(_ column: Int, _ row: Int) -> Vec3? {
            let ray = photo.worldRay(uprightNormalized: (Double(column) / Double(mask.width), Double(row) / Double(mask.height)))
            return surface.intersection(origin: ray.origin, direction: ray.direction).map { ray.origin + ray.direction * $0 }
        }
        var area = 0.0
        var points: [(s: Double, t: Double)] = []
        var top = (0...mask.width).map { corner($0, 0) }
        for row in 0..<mask.height {
            let bottom = (0...mask.width).map { corner($0, row + 1) }
            for column in 0..<mask.width where mask.bits[row * mask.width + column] {
                guard let a = top[column], let b = top[column + 1], let c = bottom[column + 1], let d = bottom[column] else { continue }
                area += 0.5 * (c - a).cross(d - b).length
                let local = a - anchor
                points.append((local.dot(axisU), local.dot(axisV)))
            }
            top = bottom
        }
        return (area, points)
    }

    /// Largest width of a point set over four directions, in metres.
    private func extent(of points: [(s: Double, t: Double)]) -> Double {
        guard !points.isEmpty else { return 0 }
        let directions = [(1.0, 0.0), (0.0, 1.0), (0.7071, 0.7071), (0.7071, -0.7071)]
        var best = 0.0
        for (a, b) in directions {
            var low = Double.infinity, high = -Double.infinity
            for point in points {
                let projection = point.s * a + point.t * b
                low = min(low, projection)
                high = max(high, projection)
            }
            best = max(best, high - low)
        }
        return best + cellSize
    }
}
