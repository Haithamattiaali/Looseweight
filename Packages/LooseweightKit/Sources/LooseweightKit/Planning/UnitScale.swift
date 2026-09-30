import Foundation

/// The stops of a portion slider in a food's natural unit: 0…N bites, sips, pieces, servings, or quarters and thirds of
/// one item. Each stop maps to internal grams and calories; the slider only ever shows unit words.
public struct UnitScale: Hashable, Sendable {
    public let profile: PortionProfile
    public let per100g: Nutrients
    /// What is in front of the person (internal grams).
    public let availableGrams: Double
    /// Grams at each stop, ascending, starting at 0.
    public let stops: [Double]

    /// Fractions of one item offered on the slider.
    public static let wholeFractions: [Double] = [0, 0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1]
    /// Largest number of stops, so a slider stays usable (a big bowl of nuts steps in bigger jumps).
    public static let maxStops = 60

    /// - Parameter allowMore: true when logging (the person may have eaten more than the photo showed):
    ///   the scale then runs past what was seen. Plans never go past what is there.
    public init(profile: PortionProfile, per100g: Nutrients, availableGrams: Double, allowMore: Bool = false) {
        self.profile = profile
        self.per100g = per100g
        let available = max(availableGrams, 0)
        self.availableGrams = available
        var stops: [Double] = [0]
        switch profile.unit {
        case .whole:
            let whole = max(profile.unitGrams, 1)
            var fractions = Self.wholeFractions
            if allowMore { fractions += [1.25, 1.5, 1.75, 2] }
            stops = fractions.map { $0 * whole }
            if !allowMore, available > 0, available < whole { stops = stops.filter { $0 <= available + 0.01 } }
        default:
            let step = max(profile.stepGrams, 0.5)
            let limit = allowMore ? max(available * 1.6, available + step * 3) : available
            let count = max(Int((limit / step).rounded()), 1)
            let stride = max(1, Int((Double(count) / Double(Self.maxStops)).rounded(.up)))
            var index = stride
            while index <= count {
                stops.append(Double(index) * step)
                index += stride
            }
            if !allowMore, available > 0 {
                stops = stops.map { min($0, available) }
                if let last = stops.last, last < available - 0.01, available - last > step * 0.25 { stops.append(available) }
            }
        }
        var unique: [Double] = []
        for stop in stops where unique.last.map({ stop > $0 + 0.01 }) ?? true { unique.append(stop) }
        self.stops = unique.isEmpty ? [0] : unique
    }

    public var lastStep: Int { stops.count - 1 }

    public func clamp(_ step: Int) -> Int { min(max(step, 0), lastStep) }

    public func grams(atStep step: Int) -> Double { stops[clamp(step)] }

    /// The stop nearest to an amount in grams.
    public func step(forGrams grams: Double) -> Int {
        var best = 0
        var distance = Double.infinity
        for (index, stop) in stops.enumerated() where abs(stop - grams) < distance {
            distance = abs(stop - grams)
            best = index
        }
        return best
    }

    public func nutrients(atStep step: Int) -> Nutrients { per100g.amount(forGrams: grams(atStep: step)) }

    public func kcal(atStep step: Int) -> Double { nutrients(atStep: step).kcal }

    /// Calories one more step adds from here (0 at the end).
    public func kcalDelta(fromStep step: Int) -> Double {
        let current = clamp(step)
        guard current < lastStep else { return 0 }
        return kcal(atStep: current + 1) - kcal(atStep: current)
    }

    /// Unit words for a stop: "3 pieces", "5 sips", "1 glass", "Half the piece", "None". Precise adds grams.
    public func label(atStep step: Int, mode: UnitsMode = .everyday) -> String {
        let grams = grams(atStep: step)
        if grams <= 0.5 { return "None" }
        let words: String
        switch profile.unit {
        case .whole:
            let text = PortionText.fraction(grams / max(profile.unitGrams, 1), of: profile.wholeNoun)
            words = text.prefix(1).uppercased() + text.dropFirst()
        case .serving:
            words = AmountFormatter.servingsWords(max(grams / profile.unitGrams, 0.5))
        default:
            if let container = profile.containerText(grams: grams) {
                words = container
            } else {
                let count = max(Int((grams / profile.unitGrams).rounded()), 1)
                words = "\(count) \(profile.noun(for: count))"
            }
        }
        guard let gramsText = AmountFormatter(mode: mode).gramsText(grams) else { return words }
        return "\(words) · \(gramsText)"
    }

    /// "= 120 kcal".
    public func kcalText(atStep step: Int) -> String { "= \(Int(kcal(atStep: step).rounded())) kcal" }

    /// "suggested: 4 bites" for the AI's recommended stop.
    public func suggestionText(grams: Double, mode: UnitsMode = .everyday) -> String {
        "suggested: \(label(atStep: step(forGrams: grams), mode: mode).lowercased())"
    }

    /// Where a stop sits along the slider, 0...1.
    public func position(ofStep step: Int) -> Double {
        lastStep > 0 ? Double(clamp(step)) / Double(lastStep) : 0
    }

    /// The nearest stop for a slider position 0...1.
    public func step(atPosition position: Double) -> Int {
        clamp(Int((min(max(position, 0), 1) * Double(lastStep)).rounded()))
    }
}

/// How a meal fits what is left of today's calories.
public struct BudgetFit: Hashable, Sendable {
    public var mealKcal: Double
    public var leftBefore: Double

    public init(mealKcal: Double, leftBefore: Double) {
        self.mealKcal = max(mealKcal, 0)
        self.leftBefore = max(leftBefore, 0)
    }

    /// Calories left today after this meal (negative when over).
    public var leftAfter: Double { leftBefore - mealKcal }
    public var isOver: Bool { leftAfter < -0.5 }
    /// Share of what was left that this meal uses, 0...∞.
    public var share: Double { leftBefore > 0 ? mealKcal / leftBefore : (mealKcal > 0 ? .infinity : 0) }

    /// "380 kcal left today after this" or "120 kcal over today".
    public var text: String {
        let value = Int(abs(leftAfter).rounded())
        return isOver ? "\(value) kcal over today" : "\(value) kcal left today after this"
    }
}

extension PlannedPortion {
    /// The slider for this portion: only what is there.
    public var unitScale: UnitScale { UnitScale(profile: profile, per100g: per100g, availableGrams: availableGrams) }
}

extension MealPlan {
    /// Sets one portion to a slider stop and returns the updated plan.
    public func setting(_ id: UUID, toGrams grams: Double) -> MealPlan {
        var copy = self
        if let index = copy.portions.firstIndex(where: { $0.id == id }) {
            copy.portions[index].plannedGrams = min(max(grams, 0), copy.portions[index].availableGrams)
        }
        return copy
    }

    public var budgetFit: BudgetFit { BudgetFit(mealKcal: total.kcal, leftBefore: remainingBefore.kcal) }
}
