import Foundation

public struct WeightSample: Hashable, Sendable {
    public var date: Date
    public var kg: Double

    public init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

public struct TrendPoint: Hashable, Sendable {
    public var date: Date
    public var kg: Double
}

public struct DailyIntake: Hashable, Sendable {
    public var day: Date
    public var kcal: Double

    public init(day: Date, kcal: Double) {
        self.day = day
        self.kcal = kcal
    }
}

public enum WeightTrend {
    /// Gap-aware exponential moving average: a sample after `n` days moves the trend by `1 − (1 − α)^n`.
    public static func smoothed(_ samples: [WeightSample], alphaPerDay alpha: Double = 0.1) -> [TrendPoint] {
        let ordered = samples.sorted { $0.date < $1.date }
        guard let first = ordered.first else { return [] }
        var trend = first.kg
        var lastDate = first.date
        var points = [TrendPoint(date: first.date, kg: trend)]
        for sample in ordered.dropFirst() {
            let days = max(sample.date.timeIntervalSince(lastDate) / 86_400, 0)
            let weight = 1 - pow(1 - alpha, max(days, 0.25))
            trend += weight * (sample.kg - trend)
            lastDate = sample.date
            points.append(TrendPoint(date: sample.date, kg: trend))
        }
        return points
    }

    /// Least-squares slope (kg per day) of the trend over the last `days`.
    public static func slopeKgPerDay(_ trend: [TrendPoint], days: Double = 21, now: Date? = nil) -> Double? {
        guard let end = now ?? trend.last?.date else { return nil }
        let window = trend.filter { $0.date <= end && end.timeIntervalSince($0.date) <= days * 86_400 }
        guard window.count >= 3,
              let firstDate = window.first?.date,
              let lastDate = window.last?.date,
              lastDate.timeIntervalSince(firstDate) >= 7 * 86_400
        else { return nil }
        let xs = window.map { $0.date.timeIntervalSince(firstDate) / 86_400 }
        let ys = window.map(\.kg)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0, denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        return denominator > 0 ? numerator / denominator : nil
    }
}

public struct MaintenanceEstimate: Hashable, Sendable {
    public enum Source: String, Sendable { case formula, blended }

    public var kcal: Double
    /// Share of the estimate that comes from the user's own data (0 = formula only).
    public var dataWeight: Double
    public var loggedDays: Int
    public var source: Source
}

public enum AdaptiveMaintenance {
    /// A day counts as logged when it holds at least this much energy.
    public static let loggedDayThreshold = 600.0

    /// Learns real maintenance from logged intake and the weight trend:
    /// maintenance ≈ average intake − trend slope × 7,700 kcal/kg.
    public static func estimate(
        intakes: [DailyIntake],
        weights: [WeightSample],
        formulaKcal: Double,
        windowDays: Int = 28,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MaintenanceEstimate {
        let formulaOnly = MaintenanceEstimate(kcal: formulaKcal, dataWeight: 0, loggedDays: 0, source: .formula)
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: today) else { return formulaOnly }

        let logged = intakes.filter { $0.day >= windowStart && $0.day < today && $0.kcal >= loggedDayThreshold }
        let recentWeights = weights.filter { $0.date >= windowStart && $0.date <= now }
        guard logged.count >= 10, recentWeights.count >= 4,
              let first = recentWeights.map(\.date).min(), let last = recentWeights.map(\.date).max(),
              last.timeIntervalSince(first) >= 14 * 86_400
        else { return MaintenanceEstimate(kcal: formulaKcal, dataWeight: 0, loggedDays: logged.count, source: .formula) }

        let trend = WeightTrend.smoothed(weights.filter { $0.date <= now })
        guard let slope = WeightTrend.slopeKgPerDay(trend, days: Double(windowDays), now: now) else {
            return MaintenanceEstimate(kcal: formulaKcal, dataWeight: 0, loggedDays: logged.count, source: .formula)
        }
        let averageIntake = logged.map(\.kcal).reduce(0, +) / Double(logged.count)
        let adaptive = (averageIntake - slope * EnergyModel.kcalPerKgBodyWeight)
            .clamped(to: (formulaKcal * 0.6)...(formulaKcal * 1.5))
        var weight = min(1, Double(logged.count) / Double(windowDays))
        if recentWeights.count < 8 { weight *= 0.7 }
        let blended = weight * adaptive + (1 - weight) * formulaKcal
        return MaintenanceEstimate(kcal: blended.rounded(), dataWeight: weight, loggedDays: logged.count, source: .blended)
    }
}
