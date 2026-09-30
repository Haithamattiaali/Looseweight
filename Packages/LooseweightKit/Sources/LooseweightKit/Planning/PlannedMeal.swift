import Foundation

/// What the person said happened to a planned meal. Only confirmed amounts count toward today.
public enum PlanConfirmation: Codable, Hashable, Sendable {
    case pending
    case ateAsPlanned
    /// Ate this share of the plan (0...1), from the quick chips.
    case atePart(Double)
    case didNotEat

    /// Quick chips offered for "Ate part".
    public static let partChoices: [(value: Double, title: String)] = [(0.25, "1/4"), (0.5, "Half"), (0.75, "3/4")]

    /// Share of the planned amounts that was eaten.
    public var eatenShare: Double {
        switch self {
        case .pending, .didNotEat: 0
        case .ateAsPlanned: 1
        case let .atePart(share): min(max(share, 0), 1)
        }
    }

    public var isPending: Bool { self == .pending }

    public var title: String {
        switch self {
        case .pending: "Waiting for you"
        case .ateAsPlanned: "Ate it all as planned"
        case let .atePart(share): "Ate \(PortionText.fraction(share, of: "plan"))"
        case .didNotEat: "Didn't eat"
        }
    }
}

/// A plan the person made before eating, waiting in the inbox until they say what happened.
public struct PlannedMeal: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var plan: MealPlan
    public var confirmation: PlanConfirmation
    public var confirmedAt: Date?

    public init(id: UUID = UUID(), plan: MealPlan, confirmation: PlanConfirmation = .pending, confirmedAt: Date? = nil) {
        self.id = id
        self.plan = plan
        self.confirmation = confirmation
        self.confirmedAt = confirmedAt
    }

    public var createdAt: Date { plan.createdAt }

    public mutating func confirm(_ confirmation: PlanConfirmation, at date: Date = Date()) {
        self.confirmation = confirmation
        confirmedAt = confirmation.isPending ? nil : date
    }

    /// What was actually eaten, as loggable items (empty until confirmed, or when nothing was eaten).
    public var eatenItems: [EstimatedItem] {
        let share = confirmation.eatenShare
        guard share > 0 else { return [] }
        return plan.portions.compactMap { portion in
            let grams = portion.plannedGrams * share
            guard grams > 0.5 else { return nil }
            return EstimatedItem(id: portion.id, name: portion.name, grams: grams.rounded(), gramsLow: grams.rounded(), gramsHigh: grams.rounded(),
                                 per100g: portion.per100g, food: portion.food, method: .userNote, confidence: 1)
        }
    }

    /// Nutrients that count toward today — zero while pending.
    public var countedNutrients: Nutrients { eatenItems.map(\.nutrients).sum() }

    /// The confirmed meal as an estimate, ready to be logged. Nil while pending or when nothing was eaten.
    public var confirmedEstimate: MealEstimate? {
        let items = eatenItems
        guard !items.isEmpty else { return nil }
        return MealEstimate(title: plan.title, items: items, overallConfidence: 1, warnings: [], modelID: nil, usedDepth: false)
    }
}

/// Inbox rules: what is waiting, and when to nudge.
public enum PlanInbox {
    /// Plans older than this get a gentle reminder.
    public static let reminderDelay: TimeInterval = 60 * 60

    public static func pending(_ meals: [PlannedMeal]) -> [PlannedMeal] {
        meals.filter { $0.confirmation.isPending }.sorted { $0.createdAt < $1.createdAt }
    }

    /// True when a pending plan should be brought up: at least `reminderDelay` old, or planned before `appOpen`
    /// by some minutes (the next time the app is opened).
    public static func needsReminder(_ meal: PlannedMeal, now: Date = Date(), lastAppOpen: Date? = nil, minimumAge: TimeInterval = 15 * 60) -> Bool {
        guard meal.confirmation.isPending else { return false }
        let age = now.timeIntervalSince(meal.createdAt)
        if age >= reminderDelay { return true }
        if let lastAppOpen, meal.createdAt < lastAppOpen, age >= minimumAge { return true }
        return false
    }

    public static func reminders(_ meals: [PlannedMeal], now: Date = Date(), lastAppOpen: Date? = nil) -> [PlannedMeal] {
        pending(meals).filter { needsReminder($0, now: now, lastAppOpen: lastAppOpen) }
    }
}
