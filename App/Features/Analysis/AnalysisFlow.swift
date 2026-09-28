import Foundation
import LooseweightKit
import Observation
import UIKit

/// Runs one meal analysis: on-device reading and measuring first, then Claude, then the app's own checks.
@MainActor
@Observable
final class AnalysisFlow {
    enum StepState: Equatable {
        case waiting, running, done, skipped, failed
    }

    struct Step: Identifiable, Equatable {
        let id: Int
        var title: String
        var systemImage: String
        var detail: String = ""
        var state: StepState = .waiting
    }

    enum Outcome {
        case success(MealEstimate)
        case failure(String)
    }

    private(set) var steps: [Step] = [
        Step(id: 0, title: "Reading the photo on the iPhone", systemImage: "eye"),
        Step(id: 1, title: "Measuring with ARKit and LiDAR", systemImage: "cube.transparent"),
        Step(id: 2, title: "Identifying each food", systemImage: "sparkles"),
        Step(id: 3, title: "Matching USDA nutrition data", systemImage: "list.bullet.rectangle"),
        Step(id: 4, title: "Checking the numbers", systemImage: "checkmark.seal"),
    ]
    private(set) var outcome: Outcome?
    private(set) var photoForModel: Data?

    private let meal: CapturedMeal
    private let model: AppModel
    private let portionHints: [PortionHint]
    private let mealType: MealType
    private let userNote: String?

    init(meal: CapturedMeal, model: AppModel, portionHints: [PortionHint], mealType: MealType, userNote: String?) {
        self.meal = meal
        self.model = model
        self.portionHints = portionHints
        self.mealType = mealType
        self.userNote = userNote
    }

    private func set(_ id: Int, _ state: StepState, _ detail: String? = nil) {
        steps[id].state = state
        if let detail { steps[id].detail = detail }
    }

    func run() async {
        guard let fullImage = ImageTools.cgImage(meal.image) else {
            outcome = .failure("The photo could not be read.")
            return
        }
        if model.aiMode == .demo || meal.source == .demo {
            await runDemo(fullImage: fullImage)
            return
        }
        guard let connection = model.connection else {
            outcome = .failure(model.connectionProblem ?? "Connect the AI in Settings.")
            return
        }

        // 1. Read the photo on the device.
        set(0, .running)
        let modelSize = ImageTools.sizeForModel(width: fullImage.width, height: fullImage.height)
        guard let modelImage = ImageTools.resized(fullImage, to: modelSize), let photoJPEG = ImageTools.jpeg(modelImage) else {
            outcome = .failure("The photo could not be prepared.")
            return
        }
        photoForModel = photoJPEG
        let vision = await OnDeviceVision.analyze(modelImage)
        var warnings: [String] = []
        if let gray = ImageTools.grayscale(modelImage) {
            warnings = ImageQuality.warnings(gray: gray.pixels, width: gray.width, height: gray.height)
        }
        var barcodes: [BarcodeFinding] = []
        for code in vision.barcodes.prefix(3) {
            let product: FoodRecord? = (try? await OpenFoodFactsClient().product(barcode: code)) ?? nil
            barcodes.append(BarcodeFinding(payload: code, product: product))
        }
        set(0, .done, summary(vision))

        // 2. Measure with the phone's own geometry.
        set(1, .running)
        let measurer = meal.geometry?.measurer
        let scale = measurer?.scaleReport()
        var regions: [OnDeviceRegion] = []
        for (index, mask) in vision.regions.prefix(8).enumerated() {
            var region = OnDeviceRegion(number: index + 1, mask: mask)
            region.measurement = measurer?.measure(item: mask, container: mask)
            regions.append(region)
        }
        if let scale {
            set(1, .done, scale.hasDepth
                ? "LiDAR: \(scale.depthFramesFused) depth frames, camera \(Int(scale.cameraHeightCm)) cm above the table"
                : "Table found, camera \(Int(scale.cameraHeightCm)) cm above it (no LiDAR on this shot)")
        } else {
            set(1, .skipped, meal.source == .library ? "Library photo: no 3D data" : "No table found; using visual scale")
        }
        let overlayJPEG = OverlayRenderer.render(
            photo: modelImage,
            regions: regions,
            pixelsPerCmAtFullSize: scale.map { $0.pixelsPerCmAtTable * Double(modelImage.width) / Double(fullImage.width) },
            fullWidth: modelImage.width
        ).flatMap { ImageTools.jpeg($0, quality: 0.8) }

        // 3–5. Claude with tools, then the app's checks.
        set(2, .running)
        let insights = CaptureInsights(
            photoWidth: modelImage.width,
            photoHeight: modelImage.height,
            deviceHasLiDAR: meal.deviceHasLiDAR,
            scale: scale,
            regions: regions,
            classifierLabels: vision.labels,
            recognizedText: vision.text,
            barcodes: barcodes,
            qualityWarnings: warnings,
            mealName: mealType.rawValue,
            localTime: meal.capturedAt.formatted(date: .omitted, time: .shortened),
            userNote: userNote,
            portionHints: portionHints,
            cuisineHint: model.cuisineHint.isEmpty ? nil : model.cuisineHint
        )
        let request = AnalysisRequest(
            photoJPEG: photoJPEG,
            overlayJPEG: regions.isEmpty && scale == nil ? nil : overlayJPEG,
            insights: insights,
            measurement: measurer.map { MeasurementContext(measurer: $0, regions: regions) },
            zoomer: PhotoZoomer(fullImage: fullImage, modelSize: CGSize(width: modelImage.width, height: modelImage.height)),
            effort: model.effort
        )
        let client = ClaudeClient(connection: connection)
        do {
            let modelID = try await model.resolveModel(client: client)
            let analyzer = MealAnalyzer(client: client, database: .shared)
            let result = try await analyzer.analyze(request, model: modelID) { [weak self] stage in
                Task { @MainActor in self?.show(stage) }
            }
            set(2, .done, "\(result.estimate.items.count) items found")
            set(3, .done, "\(result.estimate.items.filter { $0.food != nil }.count) matched in the database")
            set(4, .done, "\(result.turns) steps with the AI")
            outcome = .success(result.estimate)
        } catch let error as ClaudeError {
            fail(error.userMessage)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func show(_ stage: AnalysisStage) {
        switch stage {
        case .thinking:
            if steps[2].state != .done { set(2, .running) }
        case let .searching(query):
            set(2, .done)
            set(3, .running, "Searching “\(query)”")
        case let .measuring(count):
            set(1, .done)
            set(2, .running, "Measuring \(count) food\(count == 1 ? "" : "s") on the plate")
        case .zooming:
            set(2, .running, "Looking closer at a detail")
        case .checking:
            set(3, .done)
            set(4, .running)
        }
    }

    private func fail(_ message: String) {
        for index in steps.indices where steps[index].state == .running { steps[index].state = .failed }
        outcome = .failure(message)
    }

    private func summary(_ vision: OnDeviceVisionResult) -> String {
        var parts: [String] = []
        parts.append("\(vision.regions.count) object\(vision.regions.count == 1 ? "" : "s")")
        if let label = vision.labels.first { parts.append("looks like \(label.label)") }
        if !vision.text.isEmpty { parts.append("text found") }
        if !vision.barcodes.isEmpty { parts.append("barcode found") }
        return parts.joined(separator: " · ")
    }

    private func runDemo(fullImage: CGImage) async {
        photoForModel = ImageTools.jpeg(fullImage, quality: 0.8)
        let pause: UInt64 = model.isUITest ? 450_000_000 : 650_000_000
        let details = [
            "3 objects · looks like salad",
            "LiDAR: 15 depth frames, camera 36 cm above the table",
            "7 items found",
            "7 matched in the database",
            "Demo result (no AI call)",
        ]
        for index in steps.indices {
            set(index, .running)
            try? await Task.sleep(nanoseconds: pause)
            set(index, .done, details[index])
        }
        outcome = .success(DemoContent.estimate())
    }
}
