import Foundation

/// How amounts are shown. One user setting, one source of truth for every screen.
public enum UnitsMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Bites, sips, pieces, fractions of the item and servings. No grams anywhere, not even for macros.
    case everyday
    /// Everything Everyday shows, plus grams for food and macros and kcal per 100 g.
    case precise

    public static let `default`: UnitsMode = .everyday

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .everyday: "Everyday (bites, sips, pieces)"
        case .precise: "Precise (grams)"
        }
    }

    public var explanation: String {
        switch self {
        case .everyday: "Amounts in bites, sips, pieces and servings. Protein, carbs and fat show as progress."
        case .precise: "Adds grams for food and macros, gram entry, and kcal per 100 g."
        }
    }

    public var showsGrams: Bool { self == .precise }
}

/// How a macro is doing against its daily target, in plain words.
public enum MacroStatus: String, Sendable {
    case short
    case littleShort
    case onTrack
    case over

    public var text: String {
        switch self {
        case .short: "short"
        case .littleShort: "a little short"
        case .onTrack: "on track"
        case .over: "over"
        }
    }

    /// `fraction` is eaten ÷ target.
    public static func of(fraction: Double) -> MacroStatus {
        if fraction > 1.15 { return .over }
        if fraction >= 0.85 { return .onTrack }
        if fraction >= 0.6 { return .littleShort }
        return .short
    }
}

/// Turns an item's internal grams into the text people see, for either units mode.
/// Every screen and the CSV export go through this; Everyday output never contains grams.
public struct AmountFormatter: Sendable {
    public var mode: UnitsMode

    public init(mode: UnitsMode = .default) {
        self.mode = mode
    }

    /// "84 g" in Precise, nil in Everyday.
    public func gramsText(_ grams: Double) -> String? {
        guard mode.showsGrams else { return nil }
        return "\(Int(max(grams, 0).rounded())) g"
    }

    private func adding(_ text: String, grams: Double) -> String {
        guard let g = gramsText(grams) else { return text }
        return "\(text) · \(g)"
    }

    /// "about 7 bites" (Everyday) or "about 7 bites · 84 g" (Precise).
    public func amount(grams: Double, profile: PortionProfile, approximate: Bool = true) -> String {
        adding(profile.describe(grams: grams, approximate: approximate), grams: grams)
    }

    /// "likely 5 bites to 9 bites" (+ " · 60–108 g" in Precise).
    public func range(low: Double, high: Double, profile: PortionProfile) -> String {
        let words = "likely \(profile.describe(grams: low, approximate: false)) to \(profile.describe(grams: high, approximate: false))"
        guard mode.showsGrams else { return words }
        return "\(words) · \(Int(max(low, 0).rounded()))–\(Int(max(high, 0).rounded())) g"
    }

    /// "1½ servings" (+ " · 150 g" in Precise).
    public func servings(_ count: Double, grams: Double) -> String {
        adding(Self.servingsWords(count), grams: grams)
    }

    public static func servingsWords(_ servings: Double) -> String {
        let whole = servings.rounded(.down)
        let half = servings - whole >= 0.5
        let number: String
        if whole == 0 { number = "½" } else { number = half ? "\(Int(whole))½" : "\(Int(whole))" }
        return "\(number) serving\(servings > 1 ? "s" : "")"
    }

    /// A planned portion: "6 bites", "2/3 of the piece", "Skip" (+ " · 90 g" in Precise, not for Skip).
    public func instruction(_ portion: PlannedPortion) -> String {
        portion.isSkipped ? portion.instruction : adding(portion.instruction, grams: portion.plannedGrams)
    }

    /// Share of a daily macro target, 0...∞.
    public static func fraction(_ value: Double, of target: Double) -> Double {
        target > 0 ? max(value, 0) / target : 0
    }

    /// A macro inside one meal: "18% of your day" (+ "32 g · " in front in Precise).
    /// Without a target, Everyday shows nothing and Precise shows grams.
    public func macroShare(_ value: Double, dailyTarget: Double?) -> String {
        var parts: [String] = []
        if let g = gramsText(value) { parts.append(g) }
        if let target = dailyTarget, target > 0 {
            let percent = Int((Self.fraction(value, of: target) * 100).rounded())
            parts.append("\(percent)% of your day")
        }
        return parts.isEmpty ? "in this meal" : parts.joined(separator: " · ")
    }

    /// A day's macro: "on track" (Everyday) or "62 of 120 g · on track" (Precise).
    public func macroProgress(_ eaten: Double, target: Double) -> String {
        let status = MacroStatus.of(fraction: Self.fraction(eaten, of: target)).text
        guard mode.showsGrams else { return status }
        return "\(Int(max(eaten, 0).rounded())) of \(Int(max(target, 0).rounded())) g · \(status)"
    }

    /// A daily macro target on its own: "about 30% of calories" style words in Everyday, "120 g" in Precise.
    public func macroTarget(grams: Double, kcalPerGram: Double, dailyKcal: Double) -> String {
        if let g = gramsText(grams) { return g }
        guard dailyKcal > 0 else { return "set" }
        let percent = Int((grams * kcalPerGram / dailyKcal * 100).rounded())
        return "\(percent)% of calories"
    }

    /// "52 kcal per 100 g" in Precise, nil in Everyday.
    public func kcalPer100g(_ kcal: Double) -> String? {
        guard mode.showsGrams else { return nil }
        return "\(Int(max(kcal, 0).rounded())) kcal per 100 g"
    }

    // MARK: CSV

    /// Header of the meals table. Everyday has no gram columns.
    public var csvMealHeader: String {
        mode.showsGrams
            ? "date,meal,food,portion,grams,kcal,protein_g,carbs_g,fat_g,method"
            : "date,meal,food,portion,kcal,method"
    }

    /// The columns after date, meal and food, matching `csvMealHeader`.
    public func csvMealColumns(portion: String, grams: Double, nutrients: Nutrients, method: String) -> String {
        let quoted = "\"\(portion.replacingOccurrences(of: "\"", with: "'"))\""
        if mode.showsGrams {
            let fmt = { (v: Double) in String(format: "%.1f", v) }
            return "\(quoted),\(Int(grams.rounded())),\(Int(nutrients.kcal.rounded())),\(fmt(nutrients.protein)),\(fmt(nutrients.carbs)),\(fmt(nutrients.fat)),\(method)"
        }
        return "\(quoted),\(Int(nutrients.kcal.rounded())),\(method)"
    }
}
