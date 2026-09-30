import Foundation
@testable import LooseweightKit

/// Tiny ray caster for a table (world y = 0, y up) with simple food-like solids. Used to produce exact
/// depth maps and segmentation masks, the way ARKit + LiDAR + Vision would on a phone.
struct SyntheticScene {
    enum Solid {
        case box(min: Vec3, max: Vec3)
        /// Upper half of a sphere whose flat side rests at `center.y`.
        case dome(center: Vec3, radius: Double)
        /// Upright cylinder standing on `base` (a plate when short).
        case cylinder(base: Vec3, radius: Double, height: Double)
    }

    var solids: [Solid]
    var tableY = 0.0

    /// Nearest hit: ray parameter and the index of the solid (nil = table).
    func cast(origin: Vec3, direction: Vec3) -> (t: Double, solid: Int?)? {
        var best: (t: Double, solid: Int?)?
        if abs(direction.y) > 1e-12 {
            let t = (tableY - origin.y) / direction.y
            if t > 1e-9 { best = (t, nil) }
        }
        for (index, solid) in solids.enumerated() {
            guard let t = intersect(solid, origin: origin, direction: direction) else { continue }
            if t < (best?.t ?? .infinity) { best = (t, index) }
        }
        return best
    }

    private func intersect(_ solid: Solid, origin o: Vec3, direction d: Vec3) -> Double? {
        switch solid {
        case let .box(lo, hi):
            var tNear = -Double.infinity, tFar = Double.infinity
            for axis in 0..<3 {
                if abs(d[axis]) < 1e-12 {
                    if o[axis] < lo[axis] || o[axis] > hi[axis] { return nil }
                } else {
                    var t1 = (lo[axis] - o[axis]) / d[axis]
                    var t2 = (hi[axis] - o[axis]) / d[axis]
                    if t1 > t2 { swap(&t1, &t2) }
                    tNear = max(tNear, t1)
                    tFar = min(tFar, t2)
                }
            }
            return tNear <= tFar && tNear > 1e-9 ? tNear : nil
        case let .dome(center, radius):
            let oc = o - center
            let a = d.dot(d), b = 2 * oc.dot(d), c = oc.dot(oc) - radius * radius
            let discriminant = b * b - 4 * a * c
            guard discriminant >= 0 else { return nil }
            let root = discriminant.squareRoot()
            for t in [(-b - root) / (2 * a), (-b + root) / (2 * a)] where t > 1e-9 {
                if (o + d * t).y >= center.y - 1e-9 { return t }
            }
            return nil
        case let .cylinder(base, radius, height):
            var best: Double?
            if abs(d.y) > 1e-12 {
                let t = (base.y + height - o.y) / d.y
                let p = o + d * t
                if t > 1e-9, (p.x - base.x) * (p.x - base.x) + (p.z - base.z) * (p.z - base.z) <= radius * radius { best = t }
            }
            let ox = o.x - base.x, oz = o.z - base.z
            let a = d.x * d.x + d.z * d.z, b = 2 * (ox * d.x + oz * d.z), c = ox * ox + oz * oz - radius * radius
            let discriminant = b * b - 4 * a * c
            if a > 1e-12, discriminant >= 0 {
                let t = (-b - discriminant.squareRoot()) / (2 * a)
                let y = o.y + d.y * t
                if t > 1e-9, y >= base.y, y <= base.y + height, t < (best ?? .infinity) { best = t }
            }
            return best
        }
    }

    /// Depth map as ARKit would deliver it (metres along the optical axis), with optional noise.
    func depthFrame(camera: CameraPose, noise: Double = 0, seed: UInt64 = 1) -> DepthFrame {
        var generator = SplitMix64(seed: seed)
        let width = camera.intrinsics.width, height = camera.intrinsics.height
        var depth = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let ray = camera.worldRay(u: Double(column) + 0.5, v: Double(row) + 0.5)
                guard let hit = cast(origin: ray.origin, direction: ray.direction) else { continue }
                var z = hit.t
                if noise > 0 {
                    let u1 = max(Double(generator.next() % 1_000_000) / 1_000_000, 1e-9)
                    let u2 = Double(generator.next() % 1_000_000) / 1_000_000
                    z += noise * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
                }
                depth[row * width + column] = Float(z)
            }
        }
        return DepthFrame(width: width, height: height, depth: depth, confidence: [UInt8](repeating: 2, count: width * height), camera: camera)
    }

    /// Exact segmentation of the upright photo: mask of the pixels whose first hit is `solid`.
    func mask(of solids: Set<Int>, photo: PhotoGeometry, width: Int, height: Int) -> RegionMask {
        var bits = [Bool](repeating: false, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let point = ((Double(column) + 0.5) / Double(width), (Double(row) + 0.5) / Double(height))
                let ray = photo.worldRay(uprightNormalized: point)
                if let hit = cast(origin: ray.origin, direction: ray.direction), let solid = hit.solid, solids.contains(solid) {
                    bits[row * width + column] = true
                }
            }
        }
        return RegionMask(width: width, height: height, bits: bits)
    }
}

enum TestCameras {
    /// ARKit-like wide camera looking down at the origin from `height` metres, offset back by `offset`.
    static func overhead(height: Double = 0.40, offset: Double = 0.08, width: Int, imageHeight: Int, focalAt1920: Double = 1582) -> CameraPose {
        let focal = focalAt1920 * Double(width) / 1920
        let intrinsics = CameraIntrinsics(fx: focal, fy: focal, cx: Double(width) / 2, cy: Double(imageHeight) / 2, width: width, height: imageHeight)
        let pose = RigidTransform.lookAt(eye: Vec3(0, height, offset), target: Vec3(0, 0, 0), up: Vec3(0, 1, 0))
        return CameraPose(intrinsics: intrinsics, worldFromCamera: pose)
    }
}
