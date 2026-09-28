import Foundation
import Testing
@testable import LooseweightKit

@Suite("Weight-loss engine")
struct EnergyTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!.addingTimeInterval(Double(day) * 86_400)
    }

    @Test func mifflinStJeor() {
        #expect(EnergyModel.bmr(sex: .male, weightKg: 80, heightCm: 180, age: 30) == 1780)
        #expect(EnergyModel.bmr(sex: .female, weightKg: 70, heightCm: 165, age: 40) == 1370.25)
    }

    @Test func targetsUseDeficitFloorsAndPaceCap() {
        let now = date(0)
        var profile = UserProfile(sex: .male, birthYear: 1996, heightCm: 180, weightKg: 80, goalWeightKg: 72, activity: .moderate, weeklyLossKg: 0.5)
        let maintenance = EnergyModel.maintenance(for: profile, on: now)
        #expect(abs(maintenance - 1780 * 1.55) < 0.01)
        let targets = EnergyModel.targets(for: profile, on: now)
        #expect(targets.kcal == ((maintenance - 550) / 10).rounded() * 10)
        #expect(targets.notes.isEmpty)
        #expect(abs(targets.proteinG - 1.6 * 72) < 1)

        profile.weeklyLossKg = 2
        let capped = EnergyModel.targets(for: profile, on: now)
        #expect(capped.notes.contains { $0.contains("1% of body weight") })
        #expect(capped.kcal == ((maintenance - 0.8 * 7700 / 7) / 10).rounded() * 10)

        let small = UserProfile(sex: .female, birthYear: 1966, heightCm: 155, weightKg: 58, goalWeightKg: 54, activity: .sedentary, weeklyLossKg: 0.5)
        let floored = EnergyModel.targets(for: small, on: now)
        #expect(floored.kcal == 1200)
        #expect(floored.notes.contains { $0.contains("safe minimum") })
    }

    @Test func refusesGoalBelowHealthyWeight() {
        let profile = UserProfile(sex: .female, birthYear: 1990, heightCm: 170, weightKg: 60, goalWeightKg: 50, activity: .light, weeklyLossKg: 0.25)
        let problems = EnergyModel.validate(profile)
        #expect(problems.contains(.goalBelowHealthyWeight(minimumKg: 53.5)))
    }

    @Test func maintainingMeansNoDeficit() {
        let profile = UserProfile(sex: .male, birthYear: 1990, heightCm: 175, weightKg: 70, goalWeightKg: 70, activity: .light, weeklyLossKg: 0.5)
        let targets = EnergyModel.targets(for: profile, on: date(0))
        #expect(abs(targets.kcal - targets.maintenanceKcal) <= 5)
    }

    @Test func daysToGoal() {
        #expect(EnergyModel.daysToGoal(currentKg: 80, goalKg: 75, dailyDeficitKcal: 550) == 70)
        #expect(EnergyModel.daysToGoal(currentKg: 70, goalKg: 75, dailyDeficitKcal: 550) == nil)
    }

    @Test func trendSmoothsNoiseAndFindsTheSlope() throws {
        var samples: [WeightSample] = []
        for day in 0..<42 {
            let noise = (day % 3 == 0 ? 0.6 : day % 3 == 1 ? -0.4 : -0.2)
            samples.append(WeightSample(date: date(day), kg: 90 - 0.5 * Double(day) / 7 + noise))
        }
        let trend = WeightTrend.smoothed(samples)
        #expect(trend.count == 42)
        let slope = try #require(WeightTrend.slopeKgPerDay(trend, days: 21))
        #expect(abs(slope - (-0.5 / 7)) < 0.02)
    }

    @Test func adaptiveMaintenanceLearnsFromData() {
        var intakes: [DailyIntake] = []
        var weights: [WeightSample] = []
        for day in 0..<40 {
            intakes.append(DailyIntake(day: date(day), kcal: 2000))
            weights.append(WeightSample(date: date(day), kg: 90 - 0.5 * Double(day) / 7))
        }
        let estimate = AdaptiveMaintenance.estimate(intakes: intakes, weights: weights, formulaKcal: 2300, now: date(40), calendar: calendar)
        #expect(estimate.source == .blended)
        #expect(estimate.dataWeight == 1)
        // 2000 kcal eaten while losing 0.5 kg/week → maintenance ≈ 2000 + 550.
        #expect(abs(estimate.kcal - 2550) < 60)

        let sparse = AdaptiveMaintenance.estimate(intakes: Array(intakes.prefix(5)), weights: weights, formulaKcal: 2300, now: date(40), calendar: calendar)
        #expect(sparse.source == .formula)
        #expect(sparse.kcal == 2300)
    }
}
