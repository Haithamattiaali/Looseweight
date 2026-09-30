import Foundation

/// How much of one food to eat, in the food's own everyday unit. Grams are internal.
public struct PlannedPortion: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// What is in front of the person (internal grams).
    public var availableGrams: Double
    /// What the plan says to eat (internal grams, 0 = skip).
    public var plannedGrams: Double
    public var per100g: Nutrients
    public var profile: PortionProfile
    public var food: FoodMatch?

    public init(id: UUID = UUID(), name: String, availableGrams: Double, plannedGrams: Double, per100g: Nutrients,
                profile: PortionProfile, food: FoodMatch? = nil) {
        self.id = id
        self.name = name
        self.availableGrams = max(availableGrams, 0)
        self.plannedGrams = min(max(plannedGrams, 0), max(availableGrams, 0))
        self.per100g = per100g
        self.profile = profile
        self.food = food
    }

    public var isSkipped: Bool { plannedGrams <= 0.5 }
    public var isAll: Bool { availableGrams > 0 && plannedGrams >= availableGrams * 0.97 }
    /// Share of what is on the plate, 0...1.
    public var fractionOfItem: Double { availableGrams > 0 ? plannedGrams / availableGrams : 0 }
    public var nutrients: Nutrients { per100g.amount(forGrams: plannedGrams) }

    /// "6 bites", "2/3 of the piece", "5 sips", "All of it", "Skip".
    public var instruction: String {
        if isSkipped { return "Skip" }
        if isAll { return "All of it" }
        switch profile.unit {
        case .whole:
            let text = PortionText.fraction(fractionOfItem, of: profile.wholeNoun)
            return text.prefix(1).uppercased() + text.dropFirst()
        default:
            let count = max(Int(profile.count(forGrams: plannedGrams).rounded()), 1)
            return "\(count) \(profile.noun(for: count))"
        }
    }

    /// "of about 9" — the size of what is there, in the same unit (nil for fractions).
    public var availableText: String? {
        guard profile.unit != .whole else { return nil }
        let count = max(Int(profile.count(forGrams: availableGrams).rounded()), 1)
        return "of about \(count)"
    }
}

/// The answer to "how much of this should I eat?".
public struct MealPlan: Codable, Hashable, Sendable {
    public var title: String
    public var portions: [PlannedPortion]
    /// What was left for today before this meal.
    public var remainingBefore: Nutrients
    public var createdAt: Date

    public init(title: String, portions: [PlannedPortion], remainingBefore: Nutrients, createdAt: Date = Date()) {
        self.title = title
        self.portions = portions
        self.remainingBefore = remainingBefore
        self.createdAt = createdAt
    }

    public var total: Nutrients { portions.map(\.nutrients).sum() }
    public var plateTotal: Nutrients { portions.map { $0.per100g.amount(forGrams: $0.availableGrams) }.sum() }
    public var remainingAfter: Nutrients {
        let total = total
        return Nutrients(kcal: max(remainingBefore.kcal - total.kcal, 0), protein: max(remainingBefore.protein - total.protein, 0),
                         carbs: max(remainingBefore.carbs - total.carbs, 0), fat: max(remainingBefore.fat - total.fat, 0))
    }
    public var eatsEverything: Bool { portions.allSatisfy { $0.isAll || $0.availableGrams <= 0 } }
    public var skipsEverything: Bool { portions.allSatisfy(\.isSkipped) }

    /// One plain sentence that sums the plan up.
    public var summary: String {
        if remainingBefore.kcal < 1 { return "You have reached today's calories. Skipping this keeps you on track." }
        if skipsEverything { return "Nothing here fits what is left today." }
        if eatsEverything { return "It all fits. Enjoy the whole plate." }
        if remainingBefore.protein > 1 && total.protein >= remainingBefore.protein * 0.9 {
            return "Protein first — this covers the protein you still need."
        }
        return "Protein first, then the rest up to what is left today."
    }
}

/// Splits what is left of today's targets across the foods in front of the person.
///
/// Rules: protein first; never more calories than are left; carbs and fat stay close to what is left;
/// never below zero; each food moves in its own unit (one bite, one sip, one piece, or a nice fraction).
public enum MealPlanner {
    public struct Options: Sendable {
        /// Extra grams of carbs / fat allowed over what is left, so one bite does not flip a food to "skip".
        public var carbsSlackG: Double
        public var fatSlackG: Double
        public init(carbsSlackG: Double = 8, fatSlackG: Double = 4) {
            self.carbsSlackG = carbsSlackG
            self.fatSlackG = fatSlackG
        }
    }

    /// Nice fraction steps for a single item.
    static let wholeSteps: [Double] = [0, 0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1]

    /// What is left of today's targets, never below zero.
    public static func remaining(targets: Nutrients, eaten: Nutrients) -> Nutrients {
        Nutrients(kcal: max(targets.kcal - eaten.kcal, 0), protein: max(targets.protein - eaten.protein, 0),
                  carbs: max(targets.carbs - eaten.carbs, 0), fat: max(targets.fat - eaten.fat, 0))
    }

    public static func plan(_ estimate: MealEstimate, remaining: Nutrients, options: Options = Options(), now: Date = Date()) -> MealPlan {
        let foods = estimate.items.map { item in
            (item: item, profile: item.portionProfile)
        }
        let portions = allocate(foods.map { ($0.item.id, $0.item.name, $0.item.grams, $0.item.per100g, $0.profile, $0.item.food) },
                                remaining: remaining, options: options)
        return MealPlan(title: estimate.title, portions: portions, remainingBefore: clamp(remaining), createdAt: now)
    }

    static func clamp(_ n: Nutrients) -> Nutrients {
        Nutrients(kcal: max(n.kcal, 0), protein: max(n.protein, 0), carbs: max(n.carbs, 0), fat: max(n.fat, 0), fiber: max(n.fiber, 0))
    }

    /// Step levels (fractions of what is there) for one food.
    static func levels(grams: Double, profile: PortionProfile) -> [Double] {
        guard grams > 0 else { return [0] }
        if profile.unit == .whole { return wholeSteps }
        let count = max(Int(profile.count(forGrams: grams).rounded()), 1)
        if count > 200 { return (0...100).map { Double($0) / 100 } }
        return (0...count).map { Double($0) / Double(count) }
    }

    typealias Food = (id: UUID, name: String, grams: Double, per100g: Nutrients, profile: PortionProfile, food: FoodMatch?)

    static func allocate(_ foods: [Food], remaining: Nutrients, options: Options) -> [PlannedPortion] {
        let left = clamp(remaining)
        let steps = foods.map { levels(grams: $0.grams, profile: $0.profile) }
        var level = Array(repeating: 0, count: foods.count)
        var total = Nutrients.zero

        func amount(_ index: Int, at step: Int) -> Nutrients {
            foods[index].per100g.amount(forGrams: foods[index].grams * steps[index][step])
        }

        while true {
            var best: (index: Int, score: Double)?
            for index in foods.indices where level[index] + 1 < steps[index].count {
                let next = amount(index, at: level[index] + 1)
                let current = amount(index, at: level[index])
                let delta = Nutrients(kcal: next.kcal - current.kcal, protein: next.protein - current.protein,
                                      carbs: next.carbs - current.carbs, fat: next.fat - current.fat, fiber: next.fiber - current.fiber)
                guard total.kcal + delta.kcal <= left.kcal + 0.5 else { continue }
                if delta.carbs > 0.5, total.carbs + delta.carbs > left.carbs + options.carbsSlackG { continue }
                if delta.fat > 0.5, total.fat + delta.fat > left.fat + options.fatSlackG { continue }
                let proteinStillNeeded = max(left.protein - total.protein, 0)
                let proteinValue = min(delta.protein, proteinStillNeeded) * 4 * 3
                let value = proteinValue + delta.kcal * 0.5 + delta.fiber * 8
                let score = value / max(delta.kcal, 1)
                if best.map({ score > $0.score + 1e-9 }) ?? true { best = (index, score) }
            }
            guard let chosen = best else { break }
            level[chosen.index] += 1
            total = foods.indices.map { amount($0, at: level[$0]) }.sum()
        }

        return foods.indices.map { index in
            let food = foods[index]
            return PlannedPortion(id: food.id, name: food.name, availableGrams: food.grams,
                                  plannedGrams: food.grams * steps[index][level[index]], per100g: food.per100g,
                                  profile: food.profile, food: food.food)
        }
    }
}
