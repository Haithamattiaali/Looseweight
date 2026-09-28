import Foundation
import Testing
@testable import LooseweightKit

@Suite("On-device geometry")
struct GeometryTests {
    let box = SyntheticScene.Solid.box(min: Vec3(-0.09, 0, -0.03), max: Vec3(-0.03, 0.03, 0.03))
    let dome = SyntheticScene.Solid.dome(center: Vec3(0.06, 0, 0.0), radius: 0.04)
    let boxVolumeMl = 108.0
    let domeVolumeMl = 2.0 / 3.0 * Double.pi * pow(4.0, 3)

    @Test(arguments: ImageOrientation.allCases)
    func orientationRoundTrip(orientation: ImageOrientation) {
        for point in [(0.1, 0.2), (0.9, 0.35), (0.5, 0.5), (0.0, 1.0)] {
            let upright = orientation.upright(fromStored: point)
            let back = orientation.stored(fromUpright: upright)
            #expect(abs(back.u - point.0) < 1e-12 && abs(back.v - point.1) < 1e-12)
        }
    }

    @Test func rightOrientationRotatesClockwise() {
        // Top-left of the stored landscape image ends up at the top-right of the upright portrait image.
        let upright = ImageOrientation.right.upright(fromStored: (0, 0))
        #expect(upright.u == 1 && upright.v == 0)
        #expect(ImageOrientation.right.uprightSize(storedWidth: 1920, storedHeight: 1440) == (1440, 1920))
    }

    @Test func arkitCameraConversion() {
        let cv = RigidTransform.lookAt(eye: Vec3(0.1, 0.4, 0.2), target: .zero, up: Vec3(0, 1, 0))
        let (x, y, z) = cv.rotation.columns
        // ARKit stores the camera's right, up and back axes as columns.
        let arkit = [x.x, x.y, x.z, 0, -y.x, -y.y, -y.z, 0, -z.x, -z.y, -z.z, 0, 0.1, 0.4, 0.2, 1]
        let converted = RigidTransform.fromARKitCamera(columnMajor: arkit)
        let probe = Vec3(0.01, -0.02, 0.35)
        #expect((converted.apply(probe) - cv.apply(probe)).length < 1e-12)
    }

    @Test func eigenSolverFindsPlaneNormal() throws {
        var generator = SplitMix64(seed: 3)
        var points: [Vec3] = []
        for _ in 0..<500 {
            let x = Double(generator.next() % 1000) / 1000 - 0.5
            let z = Double(generator.next() % 1000) / 1000 - 0.5
            points.append(Vec3(x, 0.2 * x + 0.1 * z + 0.05, z))
        }
        let plane = try #require(PlaneFitter.leastSquares(points))
        let expected = Vec3(-0.2, 1, -0.1).normalized
        #expect(abs(abs(plane.normal.dot(expected)) - 1) < 1e-9)
    }

    @Test func ransacIgnoresFoodAndOutliers() throws {
        let scene = SyntheticScene(solids: [box, dome])
        let frame = scene.depthFrame(camera: TestCameras.overhead(width: 256, imageHeight: 192), noise: 0.002)
        let result = try #require(PlaneFitter.ransac(frame.worldPoints(), up: Vec3(0, 1, 0)))
        #expect(abs(abs(result.plane.normal.y) - 1) < 0.01)
        #expect(abs(result.plane.oriented(toward: Vec3(0, 1, 0)).height(of: .zero)) < 0.002)
        #expect(result.inlierRatio > 0.6)
    }

    private func measurer(scene: SyntheticScene, frames: Int, noise: Double, jitter: Double, orientation: ImageOrientation = .right) -> (SceneMeasurer, PhotoGeometry) {
        let table = Plane(normal: Vec3(0, 1, 0), through: .zero)
        var builder = HeightFieldBuilder(plane: table, center: .zero, size: 0.5)
        var generator = SplitMix64(seed: 11)
        func wobble() -> Double { (Double(generator.next() % 2001) / 1000 - 1) * jitter }
        for index in 0..<frames {
            var camera = TestCameras.overhead(width: 256, imageHeight: 192)
            camera.worldFromCamera = RigidTransform.lookAt(
                eye: Vec3(wobble(), 0.40 + wobble(), 0.08 + wobble()),
                target: Vec3(wobble(), 0, wobble()),
                up: Vec3(0, 1, 0)
            )
            builder.add(scene.depthFrame(camera: camera, noise: noise, seed: UInt64(index + 1)))
        }
        let photo = PhotoGeometry(camera: TestCameras.overhead(width: 1920, imageHeight: 1440), orientation: orientation)
        return (SceneMeasurer(plane: table, photo: photo, heightField: builder.build()), photo)
    }

    @Test func singleFrameVolumesAreAccurate() {
        let scene = SyntheticScene(solids: [box, dome])
        let (measurer, photo) = measurer(scene: scene, frames: 1, noise: 0, jitter: 0)
        let boxMask = scene.mask(of: [0], photo: photo, width: 360, height: 480)
        let domeMask = scene.mask(of: [1], photo: photo, width: 360, height: 480)
        let boxResult = measurer.measure(item: boxMask)
        let domeResult = measurer.measure(item: domeMask)
        #expect(boxResult.method == .depth)
        #expect(abs((boxResult.volumeAboveTableMl ?? 0) - boxVolumeMl) / boxVolumeMl < 0.06, "box \(boxResult.volumeAboveTableMl ?? -1)")
        #expect(abs((domeResult.volumeAboveTableMl ?? 0) - domeVolumeMl) / domeVolumeMl < 0.06, "dome \(domeResult.volumeAboveTableMl ?? -1)")
        #expect(abs((boxResult.maxHeightMm ?? 0) - 30) < 3)
        #expect(abs((domeResult.maxHeightMm ?? 0) - 40) < 3)
        #expect(abs(boxResult.areaCm2 - 36) / 36 < 0.12, "box area \(boxResult.areaCm2)")
    }

    @Test func fusedNoisyFramesStayAccurate() {
        let scene = SyntheticScene(solids: [box, dome])
        let (measurer, photo) = measurer(scene: scene, frames: 12, noise: 0.003, jitter: 0.006)
        let domeResult = measurer.measure(item: scene.mask(of: [1], photo: photo, width: 360, height: 480))
        let boxResult = measurer.measure(item: scene.mask(of: [0], photo: photo, width: 360, height: 480))
        #expect(abs((domeResult.volumeAboveTableMl ?? 0) - domeVolumeMl) / domeVolumeMl < 0.08, "dome \(domeResult.volumeAboveTableMl ?? -1)")
        #expect(abs((boxResult.volumeAboveTableMl ?? 0) - boxVolumeMl) / boxVolumeMl < 0.08, "box \(boxResult.volumeAboveTableMl ?? -1)")
        #expect((domeResult.measuredShare ?? 0) > 0.8)
    }

    @Test func foodOnAPlateUsesThePlateFloor() throws {
        let plate = SyntheticScene.Solid.cylinder(base: Vec3(0, 0, 0), radius: 0.12, height: 0.012)
        let mound = SyntheticScene.Solid.dome(center: Vec3(0.01, 0.012, 0), radius: 0.05)
        let scene = SyntheticScene(solids: [plate, mound])
        let (measurer, photo) = measurer(scene: scene, frames: 6, noise: 0.002, jitter: 0.004)
        let food = scene.mask(of: [1], photo: photo, width: 360, height: 480)
        let dish = scene.mask(of: [0, 1], photo: photo, width: 360, height: 480)
        let result = measurer.measure(item: food, container: dish)
        let expected = 2.0 / 3.0 * Double.pi * pow(5.0, 3)
        let container = try #require(result.container)
        #expect(abs((result.volumeAboveFloorMl ?? 0) - expected) / expected < 0.08, "above floor \(result.volumeAboveFloorMl ?? -1)")
        #expect(abs((container.floorHeightMm ?? 0) - 12) < 2.5, "floor \(container.floorHeightMm ?? -1)")
        #expect(abs(container.diameterCm - 24) < 1.2, "diameter \(container.diameterCm)")
        #expect((result.volumeAboveTableMl ?? 0) > (result.volumeAboveFloorMl ?? 0))
    }

    @Test func planeOnlyGivesTrueArea() throws {
        // No LiDAR: a flat 10 cm disc of food (2 mm thick) measured from the ARKit plane alone.
        let disc = SyntheticScene.Solid.cylinder(base: Vec3(0.02, 0, -0.01), radius: 0.05, height: 0.002)
        let scene = SyntheticScene(solids: [disc])
        let photo = PhotoGeometry(camera: TestCameras.overhead(width: 1920, imageHeight: 1440), orientation: .right)
        let measurer = SceneMeasurer(plane: Plane(normal: Vec3(0, 1, 0), through: .zero), photo: photo, heightField: nil, noDepthLift: 0.001)
        let result = measurer.measure(item: scene.mask(of: [0], photo: photo, width: 480, height: 640))
        let expected = Double.pi * 25
        #expect(result.method == .planeProjection)
        #expect(result.volumeAboveTableMl == nil)
        #expect(abs(result.areaCm2 - expected) / expected < 0.1, "area \(result.areaCm2)")
    }

    @Test func scaleReportMatchesCameraGeometry() throws {
        let photo = PhotoGeometry(camera: TestCameras.overhead(width: 1920, imageHeight: 1440), orientation: .right)
        let measurer = SceneMeasurer(plane: Plane(normal: Vec3(0, 1, 0), through: .zero), photo: photo)
        let report = try #require(measurer.scaleReport())
        #expect(abs(report.cameraHeightCm - 40) < 0.01)
        #expect(abs(report.tiltDegrees - atan(0.08 / 0.40) * 180 / .pi) < 0.01)
        let distance = (0.40 * 0.40 + 0.08 * 0.08).squareRoot()
        #expect(abs(report.pixelsPerCmAtTable - 1582 / (distance * 100)) < 0.01)
        #expect(report.hasDepth == false)
    }

    @Test func polygonMaskMatchesArea() {
        let mask = RegionMask(polygon: [(100, 100), (300, 100), (300, 200), (100, 200)], photoWidth: 400, photoHeight: 400, resolution: 400)
        #expect(abs(mask.coverage - 0.125) < 0.005)
        #expect(mask.contains(normalized: (0.5, 0.375)))
        #expect(!mask.contains(normalized: (0.9, 0.9)))
    }
}
