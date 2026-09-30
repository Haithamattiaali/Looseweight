import Foundation
import Testing
@testable import LooseweightKit

@Suite("Unit sliders")
struct UnitScaleTests {
    let rice = Nutrients(kcal: 130, protein: 2.7, carbs: 28, fat: 0.3)

    @Test func bitesStepToWhatIsThere() {
        let profile = PortionProfile(unit: .bite, unitGrams: 15)
        let scale = UnitScale(profile: profile, per100g: rice, availableGrams: 150)
        #expect(scale.lastStep == 10)
        #expect(scale.grams(atStep: 3) == 45)
        #expect(scale.label(atStep: 3) == "3 bites")
        #expect(scale.label(atStep: 0) == "None")
        #expect(abs(scale.kcal(atStep: 3) - 58.5) < 0.01)
        #expect(scale.kcalText(atStep: 3) == "= 59 kcal")
        #expect(scale.label(atStep: 3, mode: .precise) == "3 bites · 45 g")
        #expect(scale.step(forGrams: 50) == 3)
        #expect(scale.suggestionText(grams: 60) == "suggested: 4 bites")
        #expect(scale.grams(atStep: 99) == 150)
    }

    @Test func partialLastStepReachesAll() {
        let scale = UnitScale(profile: PortionProfile(unit: .bite, unitGrams: 15), per100g: rice, availableGrams: 100)
        #expect(scale.grams(atStep: scale.lastStep) == 100)
        #expect(scale.stops.allSatisfy { $0 <= 100 })
    }

    @Test func piecesAndSlicesAreNamed() {
        let pizza = PortionSizes.profile(name: "Pizza", grams: 440)
        #expect(pizza.unit == .piece)
        let scale = UnitScale(profile: pizza, per100g: rice, availableGrams: 440)
        #expect(scale.label(atStep: 3) == "3 slices")
        #expect(scale.label(atStep: 1) == "1 slice")
    }

    @Test func drinksUseSipsThenTheirContainer() {
        let glass = PortionSizes.drinkProfile(unit: .glass, mlPerUnit: 250)
        let scale = UnitScale(profile: glass, per100g: Nutrients(kcal: 45, protein: 0.7, carbs: 10, fat: 0.2), availableGrams: 257.5)
        #expect(scale.label(atStep: 5) == "5 sips")
        #expect(scale.label(atStep: scale.lastStep) == "1 glass")
        #expect(scale.label(atStep: 5, mode: .everyday).range(of: #"\d\s?g\b"#, options: .regularExpression) == nil)
    }

    @Test func wholeItemsUseNiceFractions() {
        let chicken = PortionProfile(unit: .whole, unitGrams: 150, wholeNoun: "piece")
        let plan = UnitScale(profile: chicken, per100g: rice, availableGrams: 150)
        #expect(plan.lastStep == 6)
        #expect(plan.label(atStep: 3) == "Half the piece")
        #expect(plan.label(atStep: 4) == "2/3 of the piece")
        #expect(plan.label(atStep: 6) == "All of the piece")
        let log = UnitScale(profile: chicken, per100g: rice, availableGrams: 150, allowMore: true)
        #expect(log.lastStep == 10)
        #expect(log.grams(atStep: 10) == 300)
    }

    @Test func servingsStepInHalves() {
        let profile = PortionProfile(unit: .serving, unitGrams: 100)
        let scale = UnitScale(profile: profile, per100g: rice, availableGrams: 200)
        #expect(scale.lastStep == 4)
        #expect(scale.label(atStep: 3) == "1½ servings")
    }

    @Test func logScaleRunsPastWhatWasSeen() {
        let scale = UnitScale(profile: PortionProfile(unit: .bite, unitGrams: 15), per100g: rice, availableGrams: 150, allowMore: true)
        #expect(scale.grams(atStep: scale.lastStep) >= 240)
        #expect(scale.step(forGrams: 150) == 10)
    }

    @Test func hugeAmountsKeepTheSliderUsable() {
        let scale = UnitScale(profile: PortionProfile(unit: .piece, unitGrams: 1.3), per100g: rice, availableGrams: 500)
        #expect(scale.stops.count <= UnitScale.maxStops + 2)
        #expect(scale.grams(atStep: scale.lastStep) == 500)
    }

    @Test func positionsRoundTrip() {
        let scale = UnitScale(profile: PortionProfile(unit: .bite, unitGrams: 15), per100g: rice, availableGrams: 150)
        for step in 0...scale.lastStep {
            #expect(scale.step(atPosition: scale.position(ofStep: step)) == step)
        }
        #expect(scale.kcalDelta(fromStep: 0) > 0)
        #expect(scale.kcalDelta(fromStep: scale.lastStep) == 0)
    }

    @Test func planEditsAndBudgetFit() {
        let estimate = MealEstimate(title: "t", items: [
            EstimatedItem(name: "White rice", grams: 150, gramsLow: 120, gramsHigh: 180, per100g: rice, food: nil, method: .visualEstimate, confidence: 0.8),
        ], overallConfidence: 0.8)
        let plan = MealPlanner.plan(estimate, remaining: Nutrients(kcal: 100, protein: 10, carbs: 50, fat: 10))
        let portion = plan.portions[0]
        let edited = plan.setting(portion.id, toGrams: portion.unitScale.grams(atStep: 10))
        #expect(edited.portions[0].plannedGrams == 150)
        #expect(edited.budgetFit.isOver)
        #expect(edited.budgetFit.text == "95 kcal over today")
        let fit = BudgetFit(mealKcal: 120, leftBefore: 500)
        #expect(fit.text == "380 kcal left today after this")
        #expect(abs(fit.share - 0.24) < 0.001)
        #expect(plan.setting(portion.id, toGrams: 9_999).portions[0].plannedGrams == 150)
    }
}
