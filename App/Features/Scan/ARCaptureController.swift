import ARKit
import CoreImage
import LooseweightKit
import Observation
import RealityKit
import UIKit

/// Runs ARKit for the scan screen: finds the table, keeps the last seconds of LiDAR depth, guides the user,
/// and captures a high-resolution photo with its camera pose.
@MainActor
@Observable
final class ARCaptureController: NSObject {
    struct Guidance: Equatable {
        var tracking = false
        var planeFound = false
        var distanceCm: Double?
        var tiltDegrees: Double?
        var steady = false
        var depthFrames = 0

        var ready: Bool {
            guard tracking, planeFound || depthFrames > 0, steady else { return false }
            if let tilt = tiltDegrees, tilt > 25 { return false }
            if let distance = distanceCm, distance < 20 || distance > 75 { return false }
            return true
        }

        var message: String {
            if !tracking { return "Move the phone slowly to start" }
            if !planeFound && depthFrames == 0 { return "Point at the table around the plate" }
            if let tilt = tiltDegrees, tilt > 25 { return "Hold the phone flat above the plate" }
            if let distance = distanceCm, distance > 75 { return "Move a little closer" }
            if let distance = distanceCm, distance < 20 { return "Move back a little" }
            if !steady { return "Hold still…" }
            return "Ready — tap to measure"
        }
    }

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }
    let hasLiDAR = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    private(set) var guidance = Guidance()
    /// Live food check from Vision labels, smoothed by `FoodPresenceDetector`. `.unknown` until a few frames are in.
    private(set) var foodVerdict: FoodPresenceDetector.Verdict = .unknown
    @ObservationIgnored private var foodDetector = FoodPresenceDetector()
    private let foodClassifier = LiveFoodClassifier(interval: 0.5)
    /// 0...1 while the short capture sweep runs (like a Live Photo), nil otherwise.
    private(set) var sweepProgress: Double?

    /// Length of the capture sweep. Depth keeps fusing and extra views are collected during it.
    static let sweepSeconds = 1.8
    private static let sweepInterval = 0.2

    let arView: ARView
    private let depthBuffer = DepthBuffer()
    private let queue = DispatchQueue(label: "looseweight.arkit", qos: .userInitiated)

    override init() {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        super.init()
        arView.renderOptions.insert(.disableMotionBlur)
        arView.session.delegate = self
        arView.session.delegateQueue = queue
    }

    var session: ARSession { arView.session }

    func start() {
        guard Self.isSupported else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }
        if let format = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
            configuration.videoFormat = format
        }
        depthBuffer.reset()
        foodDetector.reset()
        foodVerdict = .unknown
        foodClassifier.reset()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
    }

    fileprivate func ingestFoodLabels(_ labels: [ClassifierLabel]) {
        let verdict = foodDetector.add(labels)
        if verdict != foodVerdict { foodVerdict = verdict }
    }

    enum CaptureError: LocalizedError {
        case noFrame
        var errorDescription: String? { "The camera is not ready yet. Try again in a moment." }
    }

    func capture() async throws -> CapturedMeal {
        let frame: ARFrame
        if let highResolution = await highResolutionFrame() {
            frame = highResolution
        } else if let current = session.currentFrame {
            frame = current
        } else {
            throw CaptureError.noFrame
        }
        let orientation = ImageOrientation.right
        let image = Self.uprightImage(from: frame.capturedImage, orientation: .right)
        let photoCamera = Self.cameraPose(of: frame.camera)
        let photo = PhotoGeometry(camera: photoCamera, orientation: orientation)
        let extraViews = await sweep(main: frame)
        let depthFrames = depthBuffer.recent(seconds: 2.5 + Self.sweepSeconds)

        var plane: Plane?
        var center: Vec3?
        if let hit = tablePoint(in: frame) {
            plane = hit.plane
            center = hit.point
        } else if let latest = depthFrames.last,
                  let fitted = PlaneFitter.ransac(latest.worldPoints(stride: 2), up: Vec3(0, 1, 0)) {
            plane = fitted.plane
            let ray = photo.worldRay(uprightNormalized: (0.5, 0.5))
            center = fitted.plane.intersection(origin: ray.origin, direction: ray.direction).map { ray.origin + ray.direction * $0 }
        }

        var geometry: CaptureGeometry?
        if let plane, let center {
            let oriented = plane.oriented(toward: photoCamera.center)
            let heightField: HeightField? = depthFrames.isEmpty ? nil : await Task.detached(priority: .userInitiated) {
                var builder = HeightFieldBuilder(plane: oriented, center: center, size: 0.6)
                for depthFrame in depthFrames { builder.add(depthFrame) }
                return builder.build()
            }.value
            geometry = CaptureGeometry(photo: photo, plane: oriented, heightField: heightField)
        }
        return CapturedMeal(image: image, geometry: geometry, deviceHasLiDAR: hasLiDAR, source: .camera,
                            extraViews: extraViews, depthFramesFused: depthFrames.count)
    }

    /// Short multi-frame sweep after the main photo: depth keeps fusing from every viewpoint (the delegate keeps
    /// sampling), and the sharpest frames from the most different angles are kept as extra views for the analysis.
    private func sweep(main: ARFrame) async -> [UIImage] {
        // Convert each frame right away so no ARFrame (and its camera buffer) is held during the sweep.
        var views: [(image: UIImage, position: Vec3, forward: Vec3)] = []
        var lastTimestamp: TimeInterval = main.timestamp
        let steps = Int(Self.sweepSeconds / Self.sweepInterval)
        for step in 0..<steps {
            sweepProgress = Double(step + 1) / Double(steps)
            try? await Task.sleep(nanoseconds: UInt64(Self.sweepInterval * 1_000_000_000))
            guard let frame = session.currentFrame, frame.timestamp != lastTimestamp else { continue }
            lastTimestamp = frame.timestamp
            let pose = Self.viewpoint(of: frame)
            views.append((Self.uprightImage(from: frame.capturedImage, orientation: .right), pose.position, pose.forward))
        }
        sweepProgress = nil
        let mainPose = Self.viewpoint(of: main)
        let captured = views
        let picked: [Int] = await Task.detached(priority: .userInitiated) { () -> [Int] in
            var candidates: [SweepCandidate] = []
            for (index, view) in captured.enumerated() {
                guard let cg = view.image.cgImage, let gray = ImageTools.grayscale(cg) else { continue }
                let sharpness = ImageQuality.laplacianVariance(gray: gray.pixels, width: gray.width, height: gray.height)
                candidates.append(SweepCandidate(index: index + 1, sharpness: sharpness, position: view.position, forward: view.forward))
            }
            let main = SweepCandidate(index: 0, sharpness: .infinity, position: mainPose.position, forward: mainPose.forward)
            return SweepSelector.select(candidates, main: main, count: 2)
        }.value
        return picked.compactMap { $0 >= 1 && $0 <= captured.count ? captured[$0 - 1].image : nil }
    }

    nonisolated static func viewpoint(of frame: ARFrame) -> (position: Vec3, forward: Vec3) {
        let t = frame.camera.transform
        let position = Vec3(Double(t.columns.3.x), Double(t.columns.3.y), Double(t.columns.3.z))
        let forward = -Vec3(Double(t.columns.2.x), Double(t.columns.2.y), Double(t.columns.2.z))
        return (position, forward)
    }

    private func highResolutionFrame() async -> ARFrame? {
        await withCheckedContinuation { continuation in
            session.captureHighResolutionFrame { frame, _ in
                continuation.resume(returning: frame)
            }
        }
    }

    /// Table plane under the image centre from ARKit plane detection (or its depth-based estimate).
    private func tablePoint(in frame: ARFrame) -> (plane: Plane, point: Vec3)? {
        for target in [ARRaycastQuery.Target.existingPlaneGeometry, .estimatedPlane] {
            let query = frame.raycastQuery(from: CGPoint(x: 0.5, y: 0.5), allowing: target, alignment: .horizontal)
            if let result = session.raycast(query).first {
                let transform = result.worldTransform
                let point = Vec3(Double(transform.columns.3.x), Double(transform.columns.3.y), Double(transform.columns.3.z))
                let normal = Vec3(Double(transform.columns.1.x), Double(transform.columns.1.y), Double(transform.columns.1.z))
                return (Plane(normal: normal, through: point), point)
            }
        }
        return nil
    }

    // MARK: Conversions

    nonisolated static func cameraPose(of camera: ARCamera) -> CameraPose {
        let k = camera.intrinsics
        let intrinsics = CameraIntrinsics(
            fx: Double(k.columns.0.x), fy: Double(k.columns.1.y),
            cx: Double(k.columns.2.x), cy: Double(k.columns.2.y),
            width: Int(camera.imageResolution.width), height: Int(camera.imageResolution.height)
        )
        let m = camera.transform
        let values = [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] }
        return CameraPose(intrinsics: intrinsics, worldFromCamera: RigidTransform.fromARKitCamera(columnMajor: values))
    }

    nonisolated static func depthFrame(from frame: ARFrame) -> DepthFrame? {
        guard let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }
        let map = sceneDepth.depthMap
        guard CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        var depth = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            let source = base.advanced(by: row * rowBytes).assumingMemoryBound(to: Float32.self)
            for column in 0..<width { depth[row * width + column] = source[column] }
        }

        var confidence: [UInt8]?
        if let confidenceMap = sceneDepth.confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
            if let confidenceBase = CVPixelBufferGetBaseAddress(confidenceMap),
               CVPixelBufferGetWidth(confidenceMap) == width, CVPixelBufferGetHeight(confidenceMap) == height {
                let confidenceRow = CVPixelBufferGetBytesPerRow(confidenceMap)
                var values = [UInt8](repeating: 0, count: width * height)
                for row in 0..<height {
                    let source = confidenceBase.advanced(by: row * confidenceRow).assumingMemoryBound(to: UInt8.self)
                    for column in 0..<width { values[row * width + column] = source[column] }
                }
                confidence = values
            }
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
        }

        var camera = cameraPose(of: frame.camera)
        camera.intrinsics = camera.intrinsics.scaled(toWidth: width, height: height)
        return DepthFrame(width: width, height: height, depth: depth, confidence: confidence, camera: camera)
    }

    nonisolated static func uprightImage(from pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> UIImage {
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return UIImage() }
        return UIImage(cgImage: cgImage)
    }
}

extension ARCaptureController: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Food check about every 0.5 s: only a small copy of the image leaves this call, never the frame.
        foodClassifier.submit(pixelBuffer: frame.capturedImage, timestamp: frame.timestamp) { [weak self] labels in
            Task { @MainActor [weak self] in self?.ingestFoodLabels(labels) }
        }
        guard depthBuffer.shouldSample(at: frame.timestamp, interval: 0.15) else { return }
        if let depth = Self.depthFrame(from: frame) {
            depthBuffer.append(depth, at: frame.timestamp)
        }

        let transform = frame.camera.transform
        let forward = -SIMD3<Double>(Double(transform.columns.2.x), Double(transform.columns.2.y), Double(transform.columns.2.z))
        let tilt = acos(max(-1, min(1, forward.dot(Vec3(0, -1, 0)) / max(forward.length, 1e-9)))) * 180 / .pi
        let position = Vec3(Double(transform.columns.3.x), Double(transform.columns.3.y), Double(transform.columns.3.z))
        let steady = depthBuffer.updateMotion(position: position, forward: forward, timestamp: frame.timestamp)

        var distance: Double?
        var planeFound = false
        for anchor in frame.anchors {
            guard let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal else { continue }
            let height = position.y - Double(plane.transform.columns.3.y)
            if height > 0.05, distance.map({ height < $0 * 100 }) ?? true {
                distance = height * 100
                planeFound = true
            }
        }
        let tracking: Bool
        if case .normal = frame.camera.trackingState { tracking = true } else { tracking = false }
        let depthFrames = depthBuffer.count

        let update = Guidance(tracking: tracking, planeFound: planeFound, distanceCm: distance, tiltDegrees: tilt, steady: steady, depthFrames: depthFrames)
        Task { @MainActor [weak self] in
            if self?.guidance != update { self?.guidance = update }
        }
    }
}

/// Thread-safe ring buffer of recent depth frames plus the motion check, shared with the ARKit queue.
final class DepthBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [(time: TimeInterval, frame: DepthFrame)] = []
    private var lastSample: TimeInterval = 0
    private var lastPose: (position: Vec3, forward: Vec3, time: TimeInterval)?
    private var stillSince: TimeInterval?

    var count: Int { lock.withLock { frames.count } }

    func reset() {
        lock.withLock {
            frames.removeAll()
            lastSample = 0
            lastPose = nil
            stillSince = nil
        }
    }

    func shouldSample(at time: TimeInterval, interval: TimeInterval) -> Bool {
        lock.withLock {
            guard time - lastSample >= interval else { return false }
            lastSample = time
            return true
        }
    }

    func append(_ frame: DepthFrame, at time: TimeInterval) {
        lock.withLock {
            frames.append((time, frame))
            frames.removeAll { time - $0.time > 4 }
        }
    }

    func recent(seconds: TimeInterval) -> [DepthFrame] {
        lock.withLock {
            guard let newest = frames.last?.time else { return [] }
            return frames.filter { newest - $0.time <= seconds }.map(\.frame)
        }
    }

    /// True once the phone has moved less than ~2 cm/s and ~6°/s for half a second.
    func updateMotion(position: Vec3, forward: Vec3, timestamp: TimeInterval) -> Bool {
        lock.withLock {
            defer { lastPose = (position, forward, timestamp) }
            guard let last = lastPose, timestamp > last.time else { return false }
            let dt = timestamp - last.time
            let speed = (position - last.position).length / dt
            let cosine = max(-1, min(1, forward.normalized.dot(last.forward.normalized)))
            let turn = acos(cosine) * 180 / .pi / dt
            if speed < 0.02 && turn < 6 {
                if stillSince == nil { stillSince = timestamp }
            } else {
                stillSince = nil
            }
            return stillSince.map { timestamp - $0 >= 0.5 } ?? false
        }
    }
}
