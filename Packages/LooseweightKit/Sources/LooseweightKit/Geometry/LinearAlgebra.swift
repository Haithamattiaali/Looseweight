import Foundation

public typealias Vec3 = SIMD3<Double>

extension SIMD3 where Scalar == Double {
    public func dot(_ other: Vec3) -> Double { (self * other).sum() }

    public func cross(_ other: Vec3) -> Vec3 {
        Vec3(y * other.z - z * other.y, z * other.x - x * other.z, x * other.y - y * other.x)
    }

    public var length: Double { dot(self).squareRoot() }

    public var normalized: Vec3 {
        let magnitude = length
        return magnitude > 0 ? self / magnitude : self
    }
}

/// Row-major 3×3 matrix.
public struct Mat3: Hashable, Sendable {
    public var r0: Vec3
    public var r1: Vec3
    public var r2: Vec3

    public init(rows r0: Vec3, _ r1: Vec3, _ r2: Vec3) {
        self.r0 = r0
        self.r1 = r1
        self.r2 = r2
    }

    public init(columns c0: Vec3, _ c1: Vec3, _ c2: Vec3) {
        self.init(rows: Vec3(c0.x, c1.x, c2.x), Vec3(c0.y, c1.y, c2.y), Vec3(c0.z, c1.z, c2.z))
    }

    public static let identity = Mat3(rows: Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1))

    public var transposed: Mat3 { Mat3(columns: r0, r1, r2) }

    public var columns: (Vec3, Vec3, Vec3) {
        (Vec3(r0.x, r1.x, r2.x), Vec3(r0.y, r1.y, r2.y), Vec3(r0.z, r1.z, r2.z))
    }

    public static func * (lhs: Mat3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.r0.dot(rhs), lhs.r1.dot(rhs), lhs.r2.dot(rhs))
    }

    public static func * (lhs: Mat3, rhs: Mat3) -> Mat3 {
        let (c0, c1, c2) = rhs.columns
        return Mat3(columns: lhs * c0, lhs * c1, lhs * c2)
    }

    /// Rotation about a unit axis (right-hand rule).
    public static func rotation(axis: Vec3, angle: Double) -> Mat3 {
        let a = axis.normalized
        let c = cos(angle), s = sin(angle), t = 1 - c
        return Mat3(
            rows: Vec3(t * a.x * a.x + c, t * a.x * a.y - s * a.z, t * a.x * a.z + s * a.y),
            Vec3(t * a.x * a.y + s * a.z, t * a.y * a.y + c, t * a.y * a.z - s * a.x),
            Vec3(t * a.x * a.z - s * a.y, t * a.y * a.z + s * a.x, t * a.z * a.z + c)
        )
    }
}

/// Maps points from one frame to another: `p' = rotation · p + translation`.
public struct RigidTransform: Hashable, Sendable {
    public var rotation: Mat3
    public var translation: Vec3

    public init(rotation: Mat3, translation: Vec3) {
        self.rotation = rotation
        self.translation = translation
    }

    public static let identity = RigidTransform(rotation: .identity, translation: .zero)

    public func apply(_ point: Vec3) -> Vec3 { rotation * point + translation }

    public func applyToDirection(_ direction: Vec3) -> Vec3 { rotation * direction }

    public var inverse: RigidTransform {
        let rt = rotation.transposed
        return RigidTransform(rotation: rt, translation: -(rt * translation))
    }

    public static func * (lhs: RigidTransform, rhs: RigidTransform) -> RigidTransform {
        RigidTransform(rotation: lhs.rotation * rhs.rotation, translation: lhs.rotation * rhs.translation + lhs.translation)
    }

    /// Camera pose in the computer-vision convention (x right, y down, z forward) looking from `eye` at `target`.
    public static func lookAt(eye: Vec3, target: Vec3, up: Vec3) -> RigidTransform {
        let z = (target - eye).normalized
        var x = z.cross(up)
        if x.length < 1e-9 { x = z.cross(Vec3(0, 0, -1)) }
        x = x.normalized
        let y = z.cross(x).normalized
        return RigidTransform(rotation: Mat3(columns: x, y, z), translation: eye)
    }

    /// Converts an ARKit camera transform (column-major 4×4; camera looks along −z with y up)
    /// into a world-from-camera transform in the computer-vision convention used by this package.
    public static func fromARKitCamera(columnMajor m: [Double]) -> RigidTransform {
        precondition(m.count == 16, "expects 16 values")
        let right = Vec3(m[0], m[1], m[2])
        let up = Vec3(m[4], m[5], m[6])
        let back = Vec3(m[8], m[9], m[10])
        return RigidTransform(rotation: Mat3(columns: right, -up, -back), translation: Vec3(m[12], m[13], m[14]))
    }
}

enum SymmetricEigen {
    /// Eigen decomposition of a symmetric 3×3 matrix with the cyclic Jacobi method.
    /// Returns eigenvalues ascending with matching unit eigenvectors.
    static func decompose(_ matrix: Mat3) -> [(value: Double, vector: Vec3)] {
        var a = [[matrix.r0.x, matrix.r0.y, matrix.r0.z],
                 [matrix.r1.x, matrix.r1.y, matrix.r1.z],
                 [matrix.r2.x, matrix.r2.y, matrix.r2.z]]
        var v = [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]]
        for _ in 0..<50 {
            let off = a[0][1] * a[0][1] + a[0][2] * a[0][2] + a[1][2] * a[1][2]
            if off < 1e-22 { break }
            for (p, q) in [(0, 1), (0, 2), (1, 2)] where abs(a[p][q]) > 1e-300 {
                let theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
                let t = (theta >= 0 ? 1.0 : -1.0) / (abs(theta) + (theta * theta + 1).squareRoot())
                let c = 1 / (t * t + 1).squareRoot()
                let s = t * c
                for k in 0..<3 {
                    let akp = a[k][p], akq = a[k][q]
                    a[k][p] = c * akp - s * akq
                    a[k][q] = s * akp + c * akq
                }
                for k in 0..<3 {
                    let apk = a[p][k], aqk = a[q][k]
                    a[p][k] = c * apk - s * aqk
                    a[q][k] = s * apk + c * aqk
                }
                for k in 0..<3 {
                    let vkp = v[k][p], vkq = v[k][q]
                    v[k][p] = c * vkp - s * vkq
                    v[k][q] = s * vkp + c * vkq
                }
            }
        }
        return (0..<3)
            .map { (value: a[$0][$0], vector: Vec3(v[0][$0], v[1][$0], v[2][$0]).normalized) }
            .sorted { $0.value < $1.value }
    }
}

/// Small deterministic generator so geometry results are reproducible.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Array where Element == Double {
    /// Linear-interpolated percentile, `fraction` in 0...1. Returns nil when empty.
    func percentile(_ fraction: Double) -> Double? {
        guard !isEmpty else { return nil }
        let sortedValues = sorted()
        let position = fraction.clamped(to: 0...1) * Double(sortedValues.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Swift.min(lower + 1, sortedValues.count - 1)
        let weight = position - Double(lower)
        return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight
    }
}

extension Array where Element == Float {
    func percentile(_ fraction: Double) -> Double? {
        map(Double.init).percentile(fraction)
    }
}
