import Foundation
import LooseweightKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Accuracy check on Nutrition5k plates (overhead RGB-D photos with every ingredient weighed).
// Prepare the data first: python3 scripts/eval/prepare_nutrition5k.py --dishes 40 --out eval-data
//
//   lw-eval depth [--data eval-data]                  depth pipeline only, no API key needed
//   lw-eval ai [--data eval-data] [--dishes 20] [--compare] [--output dir]
//                                                     full analysis with Claude (needs ANTHROPIC_API_KEY)

struct Dish {
    let id: String
    let massG: Double
    let kcal: Double
    let depth: [Float]
    let foodMask: [Bool]
    let photoJPEG: Data
}

/// Nutrition5k's overhead RealSense color stream at 640×480: ~69° horizontal field of view, depth aligned to color.
let focalLength = 462.0

func arguments() -> (mode: String, options: [String: String], flags: Set<String>) {
    var options: [String: String] = [:]
    var flags = Set<String>()
    let raw = Array(CommandLine.arguments.dropFirst())
    var index = 1
    while index < raw.count {
        let item = raw[index]
        if item.hasPrefix("--"), index + 1 < raw.count, !raw[index + 1].hasPrefix("--") {
            options[String(item.dropFirst(2))] = raw[index + 1]
            index += 2
        } else {
            flags.insert(String(item.dropFirst(2)))
            index += 1
        }
    }
    return (raw.first ?? "depth", options, flags)
}

func loadDishes(from directory: URL, limit: Int) throws -> [Dish] {
    let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("dish_") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    return try folders.prefix(limit).map { folder in
        let meta = try JSONValue.parse(Data(contentsOf: folder.appendingPathComponent("meta.json")))
        let depthBytes = try Data(contentsOf: folder.appendingPathComponent("depth.bin"))
        var depth = [Float](repeating: 0, count: depthBytes.count / 2)
        depthBytes.withUnsafeBytes { buffer in
            for index in depth.indices {
                let value = UInt16(littleEndian: buffer.loadUnaligned(fromByteOffset: index * 2, as: UInt16.self))
                depth[index] = value == 0 ? 0 : Float(value) * 1e-4
            }
        }
        let mask = try Data(contentsOf: folder.appendingPathComponent("food_mask.bin")).map { $0 != 0 }
        return Dish(
            id: folder.lastPathComponent,
            massG: meta["mass_g"]?.doubleValue ?? 0,
            kcal: meta["kcal"]?.doubleValue ?? 0,
            depth: depth,
            foodMask: mask,
            photoJPEG: try Data(contentsOf: folder.appendingPathComponent("rgb.jpg"))
        )
    }
}

func measurer(for dish: Dish) -> SceneMeasurer? {
    let camera = CameraPose(intrinsics: CameraIntrinsics(fx: focalLength, fy: focalLength, cx: 320, cy: 240, width: 640, height: 480))
    let frame = DepthFrame(width: 640, height: 480, depth: dish.depth, camera: camera)
    guard let fit = PlaneFitter.ransac(frame.worldPoints(stride: 2), up: Vec3(0, 0, -1), maxTiltDegrees: 5) else { return nil }
    let plane = fit.plane.oriented(toward: .zero)
    let center = plane.intersection(origin: .zero, direction: Vec3(0, 0, 1)).map { Vec3(0, 0, 1) * $0 } ?? Vec3(0, 0, 0.36)
    var builder = HeightFieldBuilder(plane: plane, center: center, size: 0.6)
    builder.add(frame)
    return SceneMeasurer(plane: plane, photo: PhotoGeometry(camera: camera, orientation: .up), heightField: builder.build())
}

func pearson(_ xs: [Double], _ ys: [Double]) -> Double {
    let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
    var sxy = 0.0, sxx = 0.0, syy = 0.0
    for (x, y) in zip(xs, ys) {
        sxy += (x - mx) * (y - my)
        sxx += (x - mx) * (x - mx)
        syy += (y - my) * (y - my)
    }
    return sxy / (sxx * syy).squareRoot()
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted.isEmpty ? .nan : sorted[sorted.count / 2]
}

/// Food pixels: the colour mask, kept only where the depth says the surface is 4 mm–15 cm above the plane.
func heightGatedMask(for dish: Dish, measurer: SceneMeasurer) -> RegionMask {
    let camera = measurer.photo.camera
    var bits = dish.foodMask
    for index in bits.indices where bits[index] {
        let z = Double(dish.depth[index])
        guard z > 0 else { bits[index] = false; continue }
        let point = camera.worldPoint(u: Double(index % 640) + 0.5, v: Double(index / 640) + 0.5, depth: z)
        let height = measurer.plane.height(of: point)
        bits[index] = height > 0.004 && height < 0.15
    }
    return RegionMask(width: 640, height: 480, bits: bits)
}

func runDepthCheck(dishes: [Dish]) {
    var volumes: [Double] = [], masses: [Double] = []
    print("dish                     mass_g  volume_ml  g_per_ml  camera_cm  tilt")
    for dish in dishes {
        guard let measurer = measurer(for: dish), let scale = measurer.scaleReport() else {
            print("\(dish.id)  no plane found")
            continue
        }
        // Nutrition5k plates sit on a raised scale platform; when the counter below it dominates the view the
        // fitted plane is the counter, which a phone held over a plate on a table does not see. Those shots are listed, not scored.
        guard scale.cameraHeightCm < 38 else {
            print("\(dish.id)  plane is the counter under the scale platform (rig-specific) — not scored")
            continue
        }
        let result = measurer.measure(item: heightGatedMask(for: dish, measurer: measurer))
        let volume = result.volumeAboveTableMl ?? 0
        volumes.append(volume)
        masses.append(dish.massG)
        print(String(format: "%@  %6.0f  %9.0f  %8.2f  %9.1f  %4.1f", dish.id, dish.massG, volume, dish.massG / max(volume, 1), scale.cameraHeightCm, scale.tiltDegrees))
    }
    guard volumes.count >= 3 else { return }
    print(String(format: "\n%d plates scored · correlation(volume, weighed mass) r = %.2f · median density %.2f g/mL",
                 volumes.count, pearson(volumes, masses), median(zip(masses, volumes).map { $0 / max($1, 1) })))
}

func runAICheck(dishes: [Dish], compare: Bool, output: URL?) async throws {
    guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
        print("Set ANTHROPIC_API_KEY to run the AI check.")
        exit(2)
    }
    let client = ClaudeClient(connection: .anthropic(apiKey: key))
    let model = try await ModelSelector().modelID(client: client)
    let analyzer = MealAnalyzer(client: client, database: .shared)
    print("model: \(model)")

    struct Row: Codable {
        var dish: String
        var trueKcal: Double
        var trueMassG: Double
        var measuredKcal: Double?
        var measuredMassG: Double?
        var photoOnlyKcal: Double?
        var error: String?
    }
    var rows: [Row] = []
    for dish in dishes {
        var row = Row(dish: dish.id, trueKcal: dish.kcal, trueMassG: dish.massG)
        let insights: CaptureInsights
        let context = measurer(for: dish).map { MeasurementContext(measurer: $0, regions: []) }
        insights = CaptureInsights(photoWidth: 640, photoHeight: 480, deviceHasLiDAR: true, scale: context?.measurer.scaleReport())
        do {
            let measured = try await analyzer.analyze(AnalysisRequest(photoJPEG: dish.photoJPEG, insights: insights, measurement: context), model: model)
            row.measuredKcal = measured.estimate.total.kcal
            row.measuredMassG = measured.estimate.items.map(\.grams).reduce(0, +)
            if compare {
                let plain = CaptureInsights(photoWidth: 640, photoHeight: 480)
                let photoOnly = try await analyzer.analyze(AnalysisRequest(photoJPEG: dish.photoJPEG, insights: plain), model: model)
                row.photoOnlyKcal = photoOnly.estimate.total.kcal
            }
        } catch {
            row.error = "\(error)"
        }
        rows.append(row)
        print(String(format: "%@  true %4.0f kcal  measured %@  photo-only %@", dish.id, dish.kcal,
                     row.measuredKcal.map { String(format: "%4.0f", $0) } ?? "   –",
                     row.photoOnlyKcal.map { String(format: "%4.0f", $0) } ?? "   –"))
    }

    func summary(_ name: String, _ pairs: [(Double, Double)]) -> String {
        guard !pairs.isEmpty else { return "\(name): no results" }
        let absolute = pairs.map { abs($0.0 - $0.1) }
        let percent = pairs.map { abs($0.0 - $0.1) / max($0.1, 1) }
        let within20 = Double(percent.filter { $0 <= 0.2 }.count) / Double(percent.count)
        return String(format: "%@: mean error %.0f kcal (%.0f%%), within 20%%: %.0f%% of plates (n=%d)",
                      name, absolute.reduce(0, +) / Double(absolute.count), 100 * percent.reduce(0, +) / Double(percent.count), 100 * within20, pairs.count)
    }
    let measuredPairs = rows.compactMap { row in row.measuredKcal.map { ($0, row.trueKcal) } }
    let photoPairs = rows.compactMap { row in row.photoOnlyKcal.map { ($0, row.trueKcal) } }
    var report = [summary("With on-device measurements", measuredPairs)]
    if compare { report.append(summary("Photo only", photoPairs)) }
    print("\n" + report.joined(separator: "\n"))

    if let output {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rows).write(to: output.appendingPathComponent("results.json"))
        try (["# Nutrition5k accuracy check", "", "Model: \(model)", ""] + report.map { "- " + $0 })
            .joined(separator: "\n").write(to: output.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
    }
}

let (mode, options, flags) = arguments()
let data = URL(fileURLWithPath: options["data"] ?? "eval-data")
let limit = Int(options["dishes"] ?? "") ?? 40
do {
    let dishes = try loadDishes(from: data, limit: limit)
    guard !dishes.isEmpty else {
        print("No dishes in \(data.path). Run scripts/eval/prepare_nutrition5k.py first.")
        exit(1)
    }
    switch mode {
    case "ai":
        try await runAICheck(dishes: dishes, compare: flags.contains("compare"), output: options["output"].map { URL(fileURLWithPath: $0) })
    default:
        runDepthCheck(dishes: dishes)
    }
} catch {
    print("lw-eval failed: \(error)")
    exit(1)
}
