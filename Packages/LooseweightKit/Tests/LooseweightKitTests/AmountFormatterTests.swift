import Foundation
import Testing
@testable import LooseweightKit

@Suite("Units modes and the amount formatter")
struct AmountFormatterTests {
    let everyday = AmountFormatter(mode: .everyday)
    let precise = AmountFormatter(mode: .precise)
    let rice = PortionProfile(unit: .bite, unitGrams: 15)
    let chicken = PortionProfile(unit: .whole, unitGrams: 150, wholeNoun: "piece")
    let per100 = Nutrients(kcal: 130, protein: 2.7, carbs: 28, fat: 0.3)

    /// No digit followed by " g" and no "gram" anywhere.
    private func hasNoGrams(_ text: String) -> Bool {
        text.range(of: #"\d\s?g\b"#, options: .regularExpression) == nil && !text.lowercased().contains("gram")
    }

    @Test func defaultIsEveryday() {
        #expect(UnitsMode.default == .everyday)
        #expect(AmountFormatter().mode == .everyday)
        #expect(!UnitsMode.everyday.showsGrams)
        #expect(UnitsMode.precise.showsGrams)
    }

    @Test func amountsInBothModes() {
        #expect(everyday.amount(grams: 90, profile: rice) == "6 bites")
        #expect(precise.amount(grams: 90, profile: rice) == "6 bites · 90 g")
        #expect(everyday.amount(grams: 100, profile: chicken) == "2/3 of the piece")
        #expect(precise.amount(grams: 100, profile: chicken) == "2/3 of the piece · 100 g")
        #expect(everyday.gramsText(90) == nil)
        #expect(precise.gramsText(89.6) == "90 g")
    }

    @Test func rangesAndServings() {
        #expect(everyday.range(low: 60, high: 120, profile: rice) == "likely 4 bites to 8 bites")
        #expect(precise.range(low: 60, high: 120, profile: rice) == "likely 4 bites to 8 bites · 60–120 g")
        #expect(everyday.servings(1.5, grams: 225) == "1½ servings")
        #expect(precise.servings(1.5, grams: 225) == "1½ servings · 225 g")
        #expect(AmountFormatter.servingsWords(0.5) == "½ serving")
        #expect(AmountFormatter.servingsWords(2) == "2 servings")
    }

    @Test func plannedPortions() {
        let portion = PlannedPortion(name: "Rice", availableGrams: 150, plannedGrams: 90, per100g: per100, profile: rice)
        #expect(everyday.instruction(portion) == "6 bites")
        #expect(precise.instruction(portion) == "6 bites · 90 g")
        let skipped = PlannedPortion(name: "Bread", availableGrams: 60, plannedGrams: 0, per100g: per100, profile: rice)
        #expect(precise.instruction(skipped) == "Skip")
    }

    @Test func macrosNeverShowGramsInEveryday() {
        #expect(everyday.macroProgress(110, target: 120) == "on track")
        #expect(everyday.macroProgress(80, target: 120) == "a little short")
        #expect(everyday.macroProgress(20, target: 120) == "short")
        #expect(everyday.macroProgress(160, target: 120) == "over")
        #expect(precise.macroProgress(110, target: 120) == "110 of 120 g · on track")
        #expect(everyday.macroShare(24, dailyTarget: 120) == "20% of your day")
        #expect(precise.macroShare(24, dailyTarget: 120) == "24 g · 20% of your day")
        #expect(precise.macroShare(24, dailyTarget: nil) == "24 g")
        #expect(everyday.macroTarget(grams: 100, kcalPerGram: 4, dailyKcal: 2000) == "20% of calories")
        #expect(precise.macroTarget(grams: 100, kcalPerGram: 4, dailyKcal: 2000) == "100 g")
        for text in [everyday.macroProgress(33, target: 120), everyday.macroShare(33, dailyTarget: 120), everyday.macroShare(33, dailyTarget: nil)] {
            #expect(hasNoGrams(text))
        }
    }

    @Test func per100gOnlyInPrecise() {
        #expect(everyday.kcalPer100g(130) == nil)
        #expect(precise.kcalPer100g(130) == "130 kcal per 100 g")
    }

    @Test func csvColumnsFollowTheMode() {
        let n = per100.amount(forGrams: 90)
        #expect(everyday.csvMealHeader == "date,meal,food,portion,kcal,method")
        #expect(everyday.csvMealColumns(portion: "6 bites", grams: 90, nutrients: n, method: "depth") == "\"6 bites\",117,depth")
        #expect(precise.csvMealHeader.contains("protein_g"))
        #expect(precise.csvMealColumns(portion: "6 bites", grams: 90, nutrients: n, method: "depth") == "\"6 bites\",90,117,2.4,25.2,0.3,depth")
        #expect(precise.csvMealHeader.split(separator: ",").count == 10)
    }

    @Test func everydayOutputIsGramFree() {
        for grams in [5.0, 40, 90, 150, 400] {
            #expect(hasNoGrams(everyday.amount(grams: grams, profile: rice)))
            #expect(hasNoGrams(everyday.amount(grams: grams, profile: chicken)))
            #expect(hasNoGrams(everyday.range(low: grams, high: grams * 2, profile: rice)))
            #expect(hasNoGrams(everyday.servings(grams / 100, grams: grams)))
        }
    }
}
