import Foundation

/// One depth map (metres along the optical axis) with the camera that captured it.
/// `camera.intrinsics` must describe the depth map's own resolution.
public struct DepthFrame: Sendable {
    public var width: Int
    public var height: Int
    /// Row-major depth in metres; 0, NaN or infinity mean "no reading".
    public var depth: [Float]
    /// Optional per-pixel confidence (ARKit: 0 low, 1 medium, 2 high).
    public var confidence: [UInt8]?
    public var camera: CameraPose

    public init(width: Int, height: Int, depth: [Float], confidence: [UInt8]? = nil, camera: CameraPose) {
        precondition(depth.count == width * height, "depth size mismatch")
        precondition(confidence == nil || confidence!.count == width * height, "confidence size mismatch")
        self.width = width
        self.height = height
        self.depth = depth
        self.confidence = confidence
        self.camera = camera
    }

    /// Valid world points, sampling every `stride` pixels.
    public func worldPoints(stride: Int = 1, minimumConfidence: UInt8 = 1, range: ClosedRange<Double> = 0.08...3.0) -> [Vec3] {
        var points: [Vec3] = []
        points.reserveCapacity((width / max(stride, 1)) * (height / max(stride, 1)))
        forEachValidPixel(stride: stride, minimumConfidence: minimumConfidence, range: range) { _, _, point in
            points.append(point)
        }
        return points
    }

    func forEachValidPixel(stride: Int, minimumConfidence: UInt8, range: ClosedRange<Double>, _ body: (Int, Int, Vec3) -> Void) {
        let step = max(stride, 1)
        let transform = camera.worldFromCamera
        let intrinsics = camera.intrinsics
        for row in Swift.stride(from: 0, to: height, by: step) {
            for column in Swift.stride(from: 0, to: width, by: step) {
                let index = row * width + column
                if let confidence, confidence[index] < minimumConfidence { continue }
                let z = Double(depth[index])
                guard z.isFinite, range.contains(z) else { continue }
                let ray = intrinsics.ray(u: Double(column) + 0.5, v: Double(row) + 0.5)
                body(column, row, transform.apply(ray * z))
            }
        }
    }
}
