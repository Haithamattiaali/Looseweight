import Foundation

/// Plane `normal · p + offset = 0`. `height(of:)` is the signed distance along `normal`.
public struct Plane: Hashable, Sendable {
    public var normal: Vec3
    public var offset: Double

    public init(normal: Vec3, offset: Double) {
        let length = normal.length
        self.normal = normal / length
        self.offset = offset / length
    }

    public init(normal: Vec3, through point: Vec3) {
        let unit = normal.normalized
        self.init(normal: unit, offset: -unit.dot(point))
    }

    public func height(of point: Vec3) -> Double { normal.dot(point) + offset }

    /// Closest point on the plane to the origin.
    public var anchor: Vec3 { normal * -offset }

    public func projected(_ point: Vec3) -> Vec3 { point - normal * height(of: point) }

    /// Same plane with the normal flipped when needed so that `point` has positive height.
    public func oriented(toward point: Vec3) -> Plane {
        height(of: point) >= 0 ? self : Plane(normal: -normal, offset: -offset)
    }

    /// Parallel plane raised by `distance` along the normal.
    public func raised(by distance: Double) -> Plane {
        Plane(normal: normal, offset: offset - distance)
    }

    /// Ray parameter where `origin + t · direction` meets the plane, when in front of the origin.
    public func intersection(origin: Vec3, direction: Vec3) -> Double? {
        let denominator = normal.dot(direction)
        guard abs(denominator) > 1e-9 else { return nil }
        let t = -(normal.dot(origin) + offset) / denominator
        return t > 0 ? t : nil
    }

    /// Two unit vectors spanning the plane.
    public var basis: (Vec3, Vec3) {
        let helper = abs(normal.x) < 0.9 ? Vec3(1, 0, 0) : Vec3(0, 1, 0)
        let e1 = normal.cross(helper).normalized
        let e2 = normal.cross(e1).normalized
        return (e1, e2)
    }
}

public enum PlaneFitter {
    /// Least-squares plane through points (normal = smallest-variance direction).
    public static func leastSquares(_ points: [Vec3]) -> Plane? {
        guard points.count >= 3 else { return nil }
        let centroid = points.reduce(Vec3.zero, +) / Double(points.count)
        var xx = 0.0, xy = 0.0, xz = 0.0, yy = 0.0, yz = 0.0, zz = 0.0
        for point in points {
            let d = point - centroid
            xx += d.x * d.x; xy += d.x * d.y; xz += d.x * d.z
            yy += d.y * d.y; yz += d.y * d.z; zz += d.z * d.z
        }
        let covariance = Mat3(rows: Vec3(xx, xy, xz), Vec3(xy, yy, yz), Vec3(xz, yz, zz))
        guard let smallest = SymmetricEigen.decompose(covariance).first, smallest.vector.length > 0.5 else { return nil }
        return Plane(normal: smallest.vector, through: centroid)
    }

    /// Robust dominant plane. With `up`, only planes within `maxTiltDegrees` of horizontal are accepted.
    public static func ransac(
        _ points: [Vec3],
        up: Vec3? = nil,
        maxTiltDegrees: Double = 25,
        inlierThreshold: Double = 0.006,
        iterations: Int = 400,
        seed: UInt64 = 7
    ) -> (plane: Plane, inlierRatio: Double)? {
        guard points.count >= 30 else { return nil }
        var generator = SplitMix64(seed: seed)
        let sample: [Vec3]
        if points.count > 20_000 {
            sample = (0..<20_000).map { _ in points[Int.random(in: 0..<points.count, using: &generator)] }
        } else {
            sample = points
        }
        let cosLimit = cos(maxTiltDegrees * .pi / 180)
        var best: (plane: Plane, count: Int)?

        for _ in 0..<iterations {
            let a = sample[Int.random(in: 0..<sample.count, using: &generator)]
            let b = sample[Int.random(in: 0..<sample.count, using: &generator)]
            let c = sample[Int.random(in: 0..<sample.count, using: &generator)]
            let normal = (b - a).cross(c - a)
            guard normal.length > 1e-9 else { continue }
            let candidate = Plane(normal: normal, through: a)
            if let up, abs(candidate.normal.dot(up.normalized)) < cosLimit { continue }
            var count = 0
            for point in sample where abs(candidate.height(of: point)) < inlierThreshold { count += 1 }
            if count > (best?.count ?? 0) { best = (candidate, count) }
        }
        guard var plane = best?.plane else { return nil }

        for _ in 0..<2 {
            let inliers = sample.filter { abs(plane.height(of: $0)) < inlierThreshold * 1.5 }
            guard let refined = leastSquares(inliers) else { break }
            if let up, abs(refined.normal.dot(up.normalized)) < cosLimit { break }
            plane = refined
        }
        let ratio = Double(sample.filter { abs(plane.height(of: $0)) < inlierThreshold }.count) / Double(sample.count)
        return (plane, ratio)
    }
}
