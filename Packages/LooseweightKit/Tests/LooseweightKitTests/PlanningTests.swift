import Foundation
import Testing
@testable import LooseweightKit

@Suite("Bite, sip and piece sizes")
struct PortionSizeTests {
    @Test func drinksAreSips() {
        let juice = PortionSizes.profile(name: "Orange juice", grams: 250)
        #expect(juice.unit == .sip)
        #expect(Int(juice.count(forGrams: 250).rounded()) == 12)
        #expect(PortionSizes.profile(name: "Watermelon", grams: 150).unit == .bite)
    }

    @Test func singleBigItemsBecomeFractions() {
        let chicken = PortionSizes.profile(name: "Grilled chicken breast", grams: 140)
        #expect(chicken.unit == .whole)
        #expect(chicken.describe(grams: 140 * 2 / 3) == "2/3 of the piece")
        #expect(chicken.describe(grams: 70) == "half the piece")
    }

    @Test func smallCountableItemsArePieces() {
        let tomatoes = PortionSizes.profile(name: "Cherry tomatoes", grams: 60, counted: true)
        #expect(tomatoes.unit == .piece)
        #expect(tomatoes.describe(grams: 60) == "6 pieces")
        #expect(PortionSizes.profile(name: "Pineapple", grams: 120).unit == .bite)
        #expect(PortionSizes.profile(name: "Eggplant stew", grams: 200).unit == .bite)
    }

    @Test func sidesAreBites() {
        let rice = PortionSizes.profile(name: "White rice", grams: 150)
        #expect(rice.unit == .bite)
        #expect(rice.describe(grams: 150) == "10 bites")
        #expect(rice.describe(grams: 5) == "less than 1 bite")
        #expect(PortionSizes.profile(name: "Mayonnaise", grams: 10).unit == .whole)
    }

    @Test func descriptionsNeverMentionGrams() {
        for name in ["Rice", "Orange juice", "Chicken breast", "Cherry tomatoes", "Olive oil", "Lentil soup", "Bread"] {
            let profile = PortionSizes.profile(name: name, grams: 120)
            for grams in [0.0, 8, 40, 120, 300] {
                let text = profile.describe(grams: grams)
                #expect(!text.contains(" g") && !text.contains("gram"), "\(name): \(text)")
            }
        }
    }

    @Test func servingsHaveSensibleSizes() {
        #expect(PortionSizes.servingGrams(name: "Cola") == 250)
        #expect(PortionSizes.servingGrams(name: "Olive oil") == 15)
        #expect(PortionSizes.servingGrams(name: "Egg, whole, boiled") == 50)
    }
}

@Suite("Meal planner")
struct MealPlannerTests {
    static func item(_ name: String, _ grams: Double, kcal: Double, protein: Double, carbs: Double, fat: Double, fiber: Double = 0,
                     method: PortionMethod = .visualEstimate) -> EstimatedItem {
        EstimatedItem(name: name, grams: grams, gramsLow: grams * 0.8, gramsHigh: grams * 1.2,
                      per100g: Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat, fiber: fiber),
                      food: nil, method: method, confidence: 0.8)
    }

    static let plate = MealEstimate(title: "Lunch", items: [
        item("Grilled chicken breast", 150, kcal: 165, protein: 31, carbs: 0, fat: 3.6),
        item("White rice", 180, kcal: 130, protein: 2.7, carbs: 28, fat: 0.3, fiber: 0.4),
        item("Orange juice", 250, kcal: 45, protein: 0.7, carbs: 10.4, fat: 0.2),
        item("Bread", 60, kcal: 265, protein: 9, carbs: 49, fat: 3.2, fiber: 2.7),
        item("Steamed broccoli", 80, kcal: 35, protein: 2.4, carbs: 7, fat: 0.4, fiber: 3.3),
    ], overallConfidence: 0.8)

    func portion(_ plan: MealPlan, _ name: String) -> PlannedPortion {
        plan.portions.first { $0.name == name }!
    }

    @Test func everythingFitsWhenPlentyIsLeft() {
        let plan = MealPlanner.plan(Self.plate, remaining: Nutrients(kcal: 2_000, protein: 150, carbs: 250, fat: 70))
        #expect(plan.eatsEverything)
        #expect(plan.portions.allSatisfy { $0.instruction == "All of it" })
    }

    @Test func proteinComesFirstAndCaloriesAreRespected() {
        let remaining = Nutrients(kcal: 450, protein: 45, carbs: 40, fat: 20)
        let plan = MealPlanner.plan(Self.plate, remaining: remaining)
        #expect(plan.total.kcal <= remaining.kcal + 0.5)
        #expect(portion(plan, "Grilled chicken breast").fractionOfItem >= 0.66)
        #expect(portion(plan, "Grilled chicken breast").fractionOfItem >= portion(plan, "White rice").fractionOfItem)
        #expect(plan.total.carbs <= remaining.carbs + MealPlanner.Options().carbsSlackG)
    }

    @Test func instructionsUseBitesSipsAndFractions() {
        let plan = MealPlanner.plan(Self.plate, remaining: Nutrients(kcal: 520, protein: 40, carbs: 55, fat: 20))
        for portion in plan.portions {
            let text = portion.instruction
            #expect(!text.contains(" g") && !text.lowercased().contains("gram"), "\(text)")
        }
        let rice = portion(plan, "White rice").instruction
        #expect(rice == "Skip" || rice == "All of it" || rice.hasSuffix("bites") || rice.hasSuffix("bite"))
        let juice = portion(plan, "Orange juice").instruction
        #expect(juice == "Skip" || juice == "All of it" || juice.hasSuffix("sips") || juice.hasSuffix("sip"))
        let chicken = portion(plan, "Grilled chicken breast").instruction
        #expect(chicken == "All of it" || chicken.contains("piece"))
    }

    @Test func nothingLeftMeansSkipAndNeverNegative() {
        let plan = MealPlanner.plan(Self.plate, remaining: Nutrients(kcal: -300, protein: -10, carbs: -5, fat: -2))
        #expect(plan.skipsEverything)
        #expect(plan.portions.allSatisfy { $0.plannedGrams == 0 && $0.instruction == "Skip" })
        #expect(plan.remainingBefore.kcal == 0)
        #expect(plan.total.kcal == 0)
    }

    @Test func plannedAmountsStayWithinWhatIsThere() {
        for kcal in stride(from: 0.0, through: 1_500, by: 75) {
            let plan = MealPlanner.plan(Self.plate, remaining: Nutrients(kcal: kcal, protein: kcal / 10, carbs: kcal / 8, fat: kcal / 30))
            #expect(plan.total.kcal <= kcal + 0.5)
            for portion in plan.portions {
                #expect(portion.plannedGrams >= 0 && portion.plannedGrams <= portion.availableGrams + 1e-9)
            }
        }
    }

    @Test func remainingIsClampedAtZero() {
        let left = MealPlanner.remaining(targets: Nutrients(kcal: 2_000, protein: 120, carbs: 200, fat: 60),
                                         eaten: Nutrients(kcal: 2_100, protein: 80, carbs: 250, fat: 30))
        #expect(left.kcal == 0 && left.carbs == 0)
        #expect(left.protein == 40 && left.fat == 30)
    }
}

@Suite("Planned meals inbox")
struct PlannedMealTests {
    let plan = MealPlanner.plan(MealPlannerTests.plate, remaining: Nutrients(kcal: 600, protein: 50, carbs: 60, fat: 25),
                                now: Date(timeIntervalSince1970: 1_000_000))

    @Test func pendingPlansCountForNothing() {
        let meal = PlannedMeal(plan: plan)
        #expect(meal.confirmation.isPending)
        #expect(meal.countedNutrients.kcal == 0)
        #expect(meal.confirmedEstimate == nil)
    }

    @Test func confirmationsCountTheRightShare() {
        var meal = PlannedMeal(plan: plan)
        meal.confirm(.ateAsPlanned, at: Date(timeIntervalSince1970: 1_003_600))
        #expect(abs(meal.countedNutrients.kcal - plan.total.kcal) < plan.portions.count.doubleValue)
        #expect(meal.confirmedAt != nil)

        meal.confirm(.atePart(0.5))
        #expect(abs(meal.countedNutrients.kcal - plan.total.kcal / 2) < plan.portions.count.doubleValue)

        meal.confirm(.didNotEat)
        #expect(meal.countedNutrients.kcal == 0)
        #expect(meal.confirmedEstimate == nil)
        #expect(PlanConfirmation.atePart(3).eatenShare == 1)
        #expect(PlanConfirmation.atePart(-1).eatenShare == 0)
    }

    @Test func codableRoundTrip() throws {
        var meal = PlannedMeal(plan: plan)
        meal.confirm(.atePart(0.75))
        let data = try JSONEncoder().encode(meal)
        #expect(try JSONDecoder().decode(PlannedMeal.self, from: data) == meal)
    }

    @Test func remindersAfterAnHourOrAtTheNextOpen() {
        let meal = PlannedMeal(plan: plan)
        let created = plan.createdAt
        #expect(!PlanInbox.needsReminder(meal, now: created.addingTimeInterval(10 * 60)))
        #expect(PlanInbox.needsReminder(meal, now: created.addingTimeInterval(61 * 60)))
        #expect(PlanInbox.needsReminder(meal, now: created.addingTimeInterval(20 * 60), lastAppOpen: created.addingTimeInterval(19 * 60)))
        var done = meal
        done.confirm(.ateAsPlanned)
        #expect(PlanInbox.reminders([meal, done], now: created.addingTimeInterval(2 * 3600)).count == 1)
    }
}

@Suite("Capture sweep")
struct SweepSelectorTests {
    @Test func picksSharpFramesFromNewAngles() {
        let down = Vec3(0, -1, 0)
        let main = SweepCandidate(index: 0, sharpness: 200, position: Vec3(0, 0.4, 0), forward: down)
        let candidates = [
            main,
            SweepCandidate(index: 1, sharpness: 180, position: Vec3(0.005, 0.4, 0), forward: down),
            SweepCandidate(index: 2, sharpness: 20, position: Vec3(0.2, 0.4, 0), forward: down),
            SweepCandidate(index: 3, sharpness: 150, position: Vec3(0.12, 0.38, 0.02), forward: Vec3(-0.3, -1, 0).normalized),
            SweepCandidate(index: 4, sharpness: 160, position: Vec3(-0.1, 0.39, 0), forward: Vec3(0.25, -1, 0).normalized),
        ]
        let picked = SweepSelector.select(candidates, main: main, count: 2)
        #expect(Set(picked) == [3, 4])
        #expect(SweepSelector.select([main, candidates[1]], main: main, count: 2).isEmpty)
    }

    @Test func extraViewsAreSentAfterTheMainPhoto() {
        let message = AnalysisPrompt.userMessage(photoJPEG: Data([1]), overlayJPEG: Data([2]), extraViewJPEGs: [Data([3]), Data([4])],
                                                 insights: CaptureInsights(photoWidth: 10, photoHeight: 10))
        let text = String(describing: message)
        #expect(text.contains("Image 3"))
        #expect(text.contains("Image 4"))
    }
}

extension Int {
    var doubleValue: Double { Double(self) }
}
