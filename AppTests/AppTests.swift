import LooseweightKit
import SwiftData
import XCTest
@testable import Looseweight

@MainActor
final class AppTests: XCTestCase {
    func testDemoEstimateUsesTheDatabaseAndMatchesTheScale() throws {
        let estimate = DemoContent.estimate()
        XCTAssertEqual(estimate.items.count, 7)
        XCTAssertEqual(estimate.items.filter { $0.food != nil }.count, 7, "every demo food should match the table")
        // The plate was weighed at 492 kcal (Nutrition5k). Different nutrition tables differ a little.
        XCTAssertEqual(estimate.total.kcal, DemoContent.groundTruthKcal, accuracy: DemoContent.groundTruthKcal * 0.25)
        XCTAssertTrue(estimate.kcalRange.contains(estimate.total.kcal))
    }

    func testModelImageSizeStaysInsideTheLimits() {
        let size = ImageTools.sizeForModel(width: 3024, height: 4032)
        XCTAssertLessThanOrEqual(size.width * size.height, ImageTools.modelMaxPixels)
        XCTAssertLessThanOrEqual(max(size.width, size.height), ImageTools.modelMaxLongEdge)
        XCTAssertEqual(size.width / size.height, 3024.0 / 4032.0, accuracy: 0.01)
        XCTAssertEqual(ImageTools.sizeForModel(width: 640, height: 480), CGSize(width: 640, height: 480))
    }

    func testSavingAMealStoresNutritionAndPortionMemory() throws {
        let container = try ModelContainer(for: Schema(LooseweightSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let estimate = DemoContent.estimate()
        let meal = Store.save(estimate, mealType: .lunch, photo: nil, in: context)
        XCTAssertEqual(meal.items.count, estimate.items.count)
        XCTAssertEqual(meal.total.kcal, estimate.total.kcal, accuracy: 0.5)
        XCTAssertEqual(Store.meals(on: Date(), in: context).count, 1)
        XCTAssertFalse(Store.portionHints(in: context).isEmpty)
        XCTAssertEqual(Store.dailyIntakes(days: 3, in: context).last?.kcal ?? 0, estimate.total.kcal, accuracy: 0.5)

        Store.save(estimate, mealType: .dinner, photo: nil, in: context)
        let chicken = try XCTUnwrap(Store.portionHints(in: context).first { $0.food == "Grilled chicken breast" })
        XCTAssertEqual(chicken.timesLogged, 2)
    }

    func testPlansCountOnlyOnceConfirmed() throws {
        let container = try ModelContainer(for: Schema(LooseweightSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let plan = MealPlanner.plan(DemoContent.estimate(), remaining: Nutrients(kcal: 300, protein: 40, carbs: 30, fat: 12))
        XCTAssertLessThanOrEqual(plan.total.kcal, 300.5)
        XCTAssertFalse(plan.portions.contains { $0.instruction.contains(" g") })
        let record = Store.savePlan(plan, mealType: .lunch, photo: nil, in: context)
        XCTAssertEqual(Store.pendingPlans(in: context).count, 1)
        XCTAssertTrue(Store.meals(on: Date(), in: context).isEmpty, "a pending plan must not count")

        Store.confirm(record, as: .atePart(0.5), in: context)
        XCTAssertTrue(Store.pendingPlans(in: context).isEmpty)
        let eaten = Store.meals(on: Date(), in: context).map(\.total.kcal).reduce(0, +)
        XCTAssertEqual(eaten, plan.total.kcal / 2, accuracy: 10)
    }

    func testWeightLogKeepsOneEntryPerDay() throws {
        let container = try ModelContainer(for: Schema(LooseweightSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        Store.logWeight(82.4, in: context)
        Store.logWeight(82.1, in: context)
        let weights = Store.weights(in: context)
        XCTAssertEqual(weights.count, 1)
        XCTAssertEqual(weights.first?.kg ?? 0, 82.1, accuracy: 0.001)
    }

    func testOverlayAndOnDeviceVisionRunOnTheDemoPhoto() async throws {
        let photo = try XCTUnwrap(ImageTools.cgImage(DemoContent.photo()))
        let result = await OnDeviceVision.analyze(photo)
        let regions = result.regions.enumerated().map { OnDeviceRegion(number: $0.offset + 1, mask: $0.element) }
        let overlay = OverlayRenderer.render(photo: photo, regions: regions, pixelsPerCmAtFullSize: 12, fullWidth: photo.width)
        XCTAssertNotNil(overlay)
        XCTAssertNotNil(ImageTools.jpeg(try XCTUnwrap(overlay)))
    }
}
