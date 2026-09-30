import Foundation

/// Pinhole intrinsics in pixels of an image `width × height`. Pixel coordinates are continuous with the origin
/// at the top-left corner; pixel `(i, j)` has its centre at `(i + 0.5, j + 0.5)`.
public struct CameraIntrinsics: Codable, Hashable, Sendable {
    public var fx: Double
    public var fy: Double
    public var cx: Double
    public var cy: Double
    public var width: Int
    public var height: Int

    public init(fx: Double, fy: Double, cx: Double, cy: Double, width: Int, height: Int) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.width = width
        self.height = height
    }

    /// Same camera described for another resolution of the same field of view.
    public func scaled(toWidth newWidth: Int, height newHeight: Int) -> CameraIntrinsics {
        let sx = Double(newWidth) / Double(width)
        let sy = Double(newHeight) / Double(height)
        return CameraIntrinsics(fx: fx * sx, fy: fy * sy, cx: cx * sx, cy: cy * sy, width: newWidth, height: newHeight)
    }

    /// Direction through a pixel position in camera coordinates (x right, y down, z forward), with z = 1.
    public func ray(u: Double, v: Double) -> Vec3 {
        Vec3((u - cx) / fx, (v - cy) / fy, 1)
    }

    /// Pixel position of a camera-space point, or nil when it is behind the camera.
    public func project(_ point: Vec3) -> (u: Double, v: Double)? {
        guard point.z > 1e-6 else { return nil }
        return (fx * point.x / point.z + cx, fy * point.y / point.z + cy)
    }
}

/// A camera with its pose. `worldFromCamera` uses the computer-vision camera convention.
public struct CameraPose: Hashable, Sendable {
    public var intrinsics: CameraIntrinsics
    public var worldFromCamera: RigidTransform

    public init(intrinsics: CameraIntrinsics, worldFromCamera: RigidTransform = .identity) {
        self.intrinsics = intrinsics
        self.worldFromCamera = worldFromCamera
    }

    public var center: Vec3 { worldFromCamera.translation }

    /// Viewing direction (camera +z) in world coordinates.
    public var forward: Vec3 { worldFromCamera.applyToDirection(Vec3(0, 0, 1)) }

    /// World point seen at pixel `(u, v)` with depth `z` along the optical axis.
    public func worldPoint(u: Double, v: Double, depth z: Double) -> Vec3 {
        worldFromCamera.apply(intrinsics.ray(u: u, v: v) * z)
    }

    /// World-space ray (origin, unnormalised direction) through a pixel.
    public func worldRay(u: Double, v: Double) -> (origin: Vec3, direction: Vec3) {
        (center, worldFromCamera.applyToDirection(intrinsics.ray(u: u, v: v)))
    }

    public func project(world point: Vec3) -> (u: Double, v: Double)? {
        intrinsics.project(worldFromCamera.inverse.apply(point))
    }
}

/// EXIF orientation: how the stored (sensor) image must be transformed to look upright.
public enum ImageOrientation: Int, Codable, Sendable, CaseIterable {
    case up = 1, upMirrored, down, downMirrored, leftMirrored, right, rightMirrored, left

    public var swapsAxes: Bool { rawValue >= 5 }

    public func uprightSize(storedWidth: Int, storedHeight: Int) -> (width: Int, height: Int) {
        swapsAxes ? (storedHeight, storedWidth) : (storedWidth, storedHeight)
    }

    /// Normalised stored coordinates → normalised upright coordinates.
    public func upright(fromStored point: (u: Double, v: Double)) -> (u: Double, v: Double) {
        let (u, v) = point
        switch self {
        case .up: return (u, v)
        case .upMirrored: return (1 - u, v)
        case .down: return (1 - u, 1 - v)
        case .downMirrored: return (u, 1 - v)
        case .leftMirrored: return (v, u)
        case .right: return (1 - v, u)
        case .rightMirrored: return (1 - v, 1 - u)
        case .left: return (v, 1 - u)
        }
    }

    /// Normalised upright coordinates → normalised stored coordinates.
    public func stored(fromUpright point: (u: Double, v: Double)) -> (u: Double, v: Double) {
        let (u, v) = point
        switch self {
        case .up: return (u, v)
        case .upMirrored: return (1 - u, v)
        case .down: return (1 - u, 1 - v)
        case .downMirrored: return (u, 1 - v)
        case .leftMirrored: return (v, u)
        case .right: return (v, 1 - u)
        case .rightMirrored: return (1 - v, 1 - u)
        case .left: return (1 - v, u)
        }
    }
}

/// The photo the model sees: an upright image of `uprightWidth × uprightHeight` pixels taken by `camera`,
/// whose intrinsics describe the stored (sensor-oriented) image.
public struct PhotoGeometry: Hashable, Sendable {
    public var camera: CameraPose
    public var orientation: ImageOrientation

    public init(camera: CameraPose, orientation: ImageOrientation) {
        self.camera = camera
        self.orientation = orientation
    }

    public var uprightSize: (width: Int, height: Int) {
        orientation.uprightSize(storedWidth: camera.intrinsics.width, storedHeight: camera.intrinsics.height)
    }

    /// Normalised upright coordinates (0...1) of a world point, or nil when behind the camera.
    public func uprightNormalized(ofWorld point: Vec3) -> (u: Double, v: Double)? {
        guard let pixel = camera.project(world: point) else { return nil }
        let stored = (pixel.u / Double(camera.intrinsics.width), pixel.v / Double(camera.intrinsics.height))
        return orientation.upright(fromStored: stored)
    }

    /// World ray through a normalised upright position.
    public func worldRay(uprightNormalized point: (u: Double, v: Double)) -> (origin: Vec3, direction: Vec3) {
        let stored = orientation.stored(fromUpright: point)
        return camera.worldRay(u: stored.u * Double(camera.intrinsics.width), v: stored.v * Double(camera.intrinsics.height))
    }
}
