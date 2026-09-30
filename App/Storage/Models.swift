import Foundation
import LooseweightKit
import SwiftData

enum MealType: String, CaseIterable, Codable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "leaf.fill"
        }
    }

    /// Share of what is left today that a plan for this meal may use (the rest stays for later meals).
    var planShare: Double {
        switch self {
        case .breakfast: 0.35
        case .lunch: 0.5
        case .dinner: 1
        case .snack: 0.25
        }
    }

    static func suggested(for date: Date = Date(), calendar: Calendar = .current) -> MealType {
        switch calendar.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snack
        }
    }
}

@Model
final class MealLog {
    var id = UUID()
    var date = Date()
    var title = ""
    var mealTypeRaw = MealType.lunch.rawValue
    @Attribute(.externalStorage) var photo: Data?
    @Relationship(deleteRule: .cascade, inverse: \FoodLog.meal) var items: [FoodLog] = []
    var confidence = 0.0
    var source = "photo"
    var modelID: String?
    var usedDepth = false

    init(date: Date, title: String, mealType: MealType, photo: Data? = nil, confidence: Double = 0, source: String = "photo", modelID: String? = nil, usedDepth: Bool = false) {
        self.date = date
        self.title = title
        self.mealTypeRaw = mealType.rawValue
        self.photo = photo
        self.confidence = confidence
        self.source = source
        self.modelID = modelID
        self.usedDepth = usedDepth
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var total: Nutrients { items.map(\.nutrients).sum() }
}

@Model
final class FoodLog {
    var id = UUID()
    var name = ""
    var grams = 0.0
    var kcalPer100g = 0.0
    var proteinPer100g = 0.0
    var carbsPer100g = 0.0
    var fatPer100g = 0.0
    var fiberPer100g = 0.0
    var foodID: String?
    var methodRaw = PortionMethod.visualEstimate.rawValue
    var confidence = 0.0
    var meal: MealLog?

    init(name: String, grams: Double, per100g: Nutrients, foodID: String?, method: PortionMethod, confidence: Double) {
        self.name = name
        self.grams = grams
        self.kcalPer100g = per100g.kcal
        self.proteinPer100g = per100g.protein
        self.carbsPer100g = per100g.carbs
        self.fatPer100g = per100g.fat
        self.fiberPer100g = per100g.fiber
        self.foodID = foodID
        self.methodRaw = method.rawValue
        self.confidence = confidence
    }

    var per100g: Nutrients {
        Nutrients(kcal: kcalPer100g, protein: proteinPer100g, carbs: carbsPer100g, fat: fatPer100g, fiber: fiberPer100g)
    }

    var nutrients: Nutrients { per100g.amount(forGrams: grams) }
    var method: PortionMethod { PortionMethod(rawValue: methodRaw) ?? .visualEstimate }

    /// Bites, sips, pieces or a fraction — never grams.
    var portionText: String {
        PortionSizes.profile(name: name, grams: grams, counted: method == .count).describe(grams: grams)
    }
}

@Model
final class WeightLog {
    var id = UUID()
    var date = Date()
    var kg = 0.0

    init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

/// The user's confirmed usual portion per food, sent to the model as a hint.
@Model
final class PortionMemory {
    @Attribute(.unique) var key = ""
    var name = ""
    var typicalGrams = 0.0
    var count = 0
    var updatedAt = Date()

    init(key: String, name: String, grams: Double) {
        self.key = key
        self.name = name
        self.typicalGrams = grams
        self.count = 1
        self.updatedAt = Date()
    }

    func record(grams: Double) {
        typicalGrams += (grams - typicalGrams) / Double(min(count + 1, 8))
        count += 1
        updatedAt = Date()
    }
}

/// A plan made before eating ("Plan"). It waits in the Inbox and counts toward today only once confirmed.
@Model
final class PlannedMealRecord {
    var id = UUID()
    var createdAt = Date()
    var title = ""
    var mealTypeRaw = MealType.lunch.rawValue
    @Attribute(.externalStorage) var photo: Data?
    /// JSON of `PlannedMeal` (the plan and its confirmation) from LooseweightKit.
    var payload = Data()
    var isPending = true
    var confirmedAt: Date?
    var usedDepth = false

    init(planned: PlannedMeal, mealType: MealType, photo: Data?, usedDepth: Bool) {
        self.id = planned.id
        self.createdAt = planned.createdAt
        self.title = planned.plan.title
        self.mealTypeRaw = mealType.rawValue
        self.photo = photo
        self.usedDepth = usedDepth
        self.payload = (try? JSONEncoder().encode(planned)) ?? Data()
        self.isPending = planned.confirmation.isPending
        self.confirmedAt = planned.confirmedAt
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var planned: PlannedMeal? {
        get { try? JSONDecoder().decode(PlannedMeal.self, from: payload) }
        set {
            guard let newValue else { return }
            payload = (try? JSONEncoder().encode(newValue)) ?? payload
            isPending = newValue.confirmation.isPending
            confirmedAt = newValue.confirmedAt
        }
    }
}

enum LooseweightSchema {
    static let models: [any PersistentModel.Type] = [MealLog.self, FoodLog.self, WeightLog.self, PortionMemory.self, PlannedMealRecord.self]
}
