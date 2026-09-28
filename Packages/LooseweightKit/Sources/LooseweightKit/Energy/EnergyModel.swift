import Foundation

public enum BiologicalSex: String, Codable, CaseIterable, Sendable {
    case female
    case male
}

public enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary
    case light
    case moderate
    case active
    case veryActive

    public var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }

    public var title: String {
        switch self {
        case .sedentary: "Mostly sitting"
        case .light: "Light (walks, 1–3 workouts a week)"
        case .moderate: "Moderate (3–5 workouts a week)"
        case .active: "Active (6–7 workouts a week)"
        case .veryActive: "Very active (physical job or twice a day)"
        }
    }
}

public struct UserProfile: Codable, Hashable, Sendable {
    public var sex: BiologicalSex
    public var birthYear: Int
    public var heightCm: Double
    public var weightKg: Double
    public var goalWeightKg: Double
    public var activity: ActivityLevel
    /// Planned loss in kg per week (0 = maintain).
    public var weeklyLossKg: Double

    public init(sex: BiologicalSex, birthYear: Int, heightCm: Double, weightKg: Double, goalWeightKg: Double, activity: ActivityLevel, weeklyLossKg: Double) {
        self.sex = sex
        self.birthYear = birthYear
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.goalWeightKg = goalWeightKg
        self.activity = activity
        self.weeklyLossKg = weeklyLossKg
    }

    public func age(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        max(calendar.component(.year, from: date) - birthYear, 0)
    }
}

public struct DailyTargets: Codable, Hashable, Sendable {
    public var kcal: Double
    public var proteinG: Double
    public var fatG: Double
    public var carbsG: Double
    /// Maintenance energy the target was derived from.
    public var maintenanceKcal: Double
    public var notes: [String]
}

public enum EnergyModel {
    public static let kcalPerKgBodyWeight = 7_700.0
    public static let minimumBMI = 18.5

    public static func minimumIntake(for sex: BiologicalSex) -> Double {
        sex == .female ? 1_200 : 1_500
    }

    /// Mifflin–St Jeor resting energy.
    public static func bmr(sex: BiologicalSex, weightKg: Double, heightCm: Double, age: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return base + (sex == .male ? 5 : -161)
    }

    public static func maintenance(for profile: UserProfile, on date: Date = Date()) -> Double {
        bmr(sex: profile.sex, weightKg: profile.weightKg, heightCm: profile.heightCm, age: profile.age(on: date)) * profile.activity.factor
    }

    public static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let meters = heightCm / 100
        return weightKg / (meters * meters)
    }

    public static func lowestHealthyWeight(heightCm: Double) -> Double {
        let meters = heightCm / 100
        return minimumBMI * meters * meters
    }

    /// Largest weekly loss we allow: 1 % of body weight.
    public static func maximumWeeklyLoss(weightKg: Double) -> Double {
        weightKg * 0.01
    }

    public enum ProfileProblem: Error, Equatable, Sendable {
        case goalBelowHealthyWeight(minimumKg: Double)
        case implausible(String)
    }

    public static func validate(_ profile: UserProfile) -> [ProfileProblem] {
        var problems: [ProfileProblem] = []
        if !(100...250).contains(profile.heightCm) { problems.append(.implausible("height")) }
        if !(30...350).contains(profile.weightKg) { problems.append(.implausible("weight")) }
        if !(13...100).contains(profile.age()) { problems.append(.implausible("age")) }
        let floor = lowestHealthyWeight(heightCm: profile.heightCm)
        if profile.goalWeightKg < floor - 0.05 {
            problems.append(.goalBelowHealthyWeight(minimumKg: (floor * 10).rounded(.up) / 10))
        }
        return problems
    }

    /// Daily targets from a maintenance estimate. `maintenanceOverride` is the adaptive estimate when one exists.
    public static func targets(for profile: UserProfile, maintenanceOverride: Double? = nil, on date: Date = Date()) -> DailyTargets {
        let maintenance = maintenanceOverride ?? maintenance(for: profile, on: date)
        var notes: [String] = []

        var weeklyLoss = max(profile.weeklyLossKg, 0)
        if profile.weightKg <= profile.goalWeightKg { weeklyLoss = 0 }
        let cap = maximumWeeklyLoss(weightKg: profile.weightKg)
        if weeklyLoss > cap {
            weeklyLoss = cap
            notes.append("Pace limited to 1% of body weight per week.")
        }

        let deficit = weeklyLoss * kcalPerKgBodyWeight / 7
        let floor = minimumIntake(for: profile.sex)
        var kcal = maintenance - deficit
        if kcal < floor {
            kcal = min(floor, maintenance)
            notes.append("Target raised to the safe minimum of \(Int(floor)) kcal.")
        }
        kcal = (kcal / 10).rounded() * 10

        let referenceKg = min(profile.weightKg, max(profile.goalWeightKg, lowestHealthyWeight(heightCm: profile.heightCm)))
        let proteinG = 1.6 * referenceKg
        let fatG = kcal * 0.30 / 9
        let carbsG = max(kcal - proteinG * 4 - fatG * 9, 0) / 4
        return DailyTargets(
            kcal: kcal,
            proteinG: proteinG.rounded(),
            fatG: fatG.rounded(),
            carbsG: carbsG.rounded(),
            maintenanceKcal: maintenance.rounded(),
            notes: notes
        )
    }

    /// Days to reach the goal at the given daily deficit, if progress is possible.
    public static func daysToGoal(currentKg: Double, goalKg: Double, dailyDeficitKcal: Double) -> Int? {
        guard currentKg > goalKg, dailyDeficitKcal > 50 else { return nil }
        return Int(((currentKg - goalKg) * kcalPerKgBodyWeight / dailyDeficitKcal).rounded(.up))
    }
}

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
