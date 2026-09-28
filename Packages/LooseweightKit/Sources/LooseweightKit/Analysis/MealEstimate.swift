import Foundation

/// The model's answer, decoded from the structured-output JSON.
public struct AIMealAnalysis: Codable, Hashable, Sendable {
    public struct Per100g: Codable, Hashable, Sendable {
        public var kcal: Double
        public var proteinG: Double
        public var carbsG: Double
        public var fatG: Double

        enum CodingKeys: String, CodingKey {
            case kcal
            case proteinG = "protein_g"
            case carbsG = "carbs_g"
            case fatG = "fat_g"
        }

        public init(kcal: Double, proteinG: Double, carbsG: Double, fatG: Double) {
            self.kcal = kcal
            self.proteinG = proteinG
            self.carbsG = carbsG
            self.fatG = fatG
        }
    }

    public struct Item: Codable, Hashable, Sendable {
        public var name: String
        public var foodID: String?
        public var grams: Double
        public var gramsLow: Double
        public var gramsHigh: Double
        public var method: PortionMethod
        public var volumeMl: Double?
        public var densityGPerMl: Double?
        public var per100g: Per100g
        public var confidence: Double
        public var regionNumbers: [Int]
        public var polygon: [[Double]]
        public var isHiddenIngredient: Bool
        public var notes: String

        enum CodingKeys: String, CodingKey {
            case name
            case foodID = "food_id"
            case grams
            case gramsLow = "grams_low"
            case gramsHigh = "grams_high"
            case method
            case volumeMl = "volume_ml"
            case densityGPerMl = "density_g_per_ml"
            case per100g = "per_100g"
            case confidence
            case regionNumbers = "region_numbers"
            case polygon
            case isHiddenIngredient = "is_hidden_ingredient"
            case notes
        }

        public init(name: String, foodID: String?, grams: Double, gramsLow: Double, gramsHigh: Double, method: PortionMethod,
                    volumeMl: Double? = nil, densityGPerMl: Double? = nil, per100g: Per100g, confidence: Double,
                    regionNumbers: [Int] = [], polygon: [[Double]] = [], isHiddenIngredient: Bool = false, notes: String = "") {
            self.name = name
            self.foodID = foodID
            self.grams = grams
            self.gramsLow = gramsLow
            self.gramsHigh = gramsHigh
            self.method = method
            self.volumeMl = volumeMl
            self.densityGPerMl = densityGPerMl
            self.per100g = per100g
            self.confidence = confidence
            self.regionNumbers = regionNumbers
            self.polygon = polygon
            self.isHiddenIngredient = isHiddenIngredient
            self.notes = notes
        }
    }

    public var mealTitle: String
    public var items: [Item]
    public var overallConfidence: Double
    public var clarifyingQuestion: String?
    public var warnings: [String]

    enum CodingKeys: String, CodingKey {
        case mealTitle = "meal_title"
        case items
        case overallConfidence = "overall_confidence"
        case clarifyingQuestion = "clarifying_question"
        case warnings
    }

    public init(mealTitle: String, items: [Item], overallConfidence: Double, clarifyingQuestion: String? = nil, warnings: [String] = []) {
        self.mealTitle = mealTitle
        self.items = items
        self.overallConfidence = overallConfidence
        self.clarifyingQuestion = clarifyingQuestion
        self.warnings = warnings
    }

    /// Decodes the model's text, tolerating stray prose around the JSON object.
    public static func decode(from text: String) throws -> AIMealAnalysis {
        let decoder = JSONDecoder()
        if let data = text.data(using: .utf8), let value = try? decoder.decode(AIMealAnalysis.self, from: data) {
            return value
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8)
        else { throw ClaudeError.invalidResponse("no JSON object in the answer") }
        do {
            return try decoder.decode(AIMealAnalysis.self, from: data)
        } catch {
            throw ClaudeError.invalidResponse("answer does not match the schema: \(error)")
        }
    }
}

public enum ItemFlag: String, Codable, Hashable, Sendable {
    /// Nutrients are the model's own estimate (no database match).
    case aiEstimate
    /// Model and database energy disagree strongly; the match should be checked.
    case checkMatch
    /// Grams were recomputed from measured volume × density.
    case gramsRecomputed
    case hiddenIngredient
}

public struct FoodMatch: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var source: FoodRecord.Source

    public init(id: String, name: String, source: FoodRecord.Source) {
        self.id = id
        self.name = name
        self.source = source
    }
}

/// One line of the meal after the app's own checks. Editing `grams` updates the nutrients.
public struct EstimatedItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var grams: Double
    public var gramsLow: Double
    public var gramsHigh: Double
    public var per100g: Nutrients
    public var food: FoodMatch?
    public var method: PortionMethod
    public var confidence: Double
    public var flags: [ItemFlag]
    public var polygon: [[Double]]
    public var notes: String

    public init(id: UUID = UUID(), name: String, grams: Double, gramsLow: Double, gramsHigh: Double, per100g: Nutrients,
                food: FoodMatch?, method: PortionMethod, confidence: Double, flags: [ItemFlag] = [], polygon: [[Double]] = [], notes: String = "") {
        self.id = id
        self.name = name
        self.grams = grams
        self.gramsLow = gramsLow
        self.gramsHigh = gramsHigh
        self.per100g = per100g
        self.food = food
        self.method = method
        self.confidence = confidence
        self.flags = flags
        self.polygon = polygon
        self.notes = notes
    }

    public var nutrients: Nutrients { per100g.amount(forGrams: grams) }
    public var kcalRange: ClosedRange<Double> {
        (per100g.kcal * gramsLow / 100)...(per100g.kcal * gramsHigh / 100)
    }
}

public struct MealEstimate: Codable, Hashable, Sendable {
    public var title: String
    public var items: [EstimatedItem]
    public var overallConfidence: Double
    public var clarifyingQuestion: String?
    public var warnings: [String]
    public var modelID: String?
    public var usedDepth: Bool

    public init(title: String, items: [EstimatedItem], overallConfidence: Double, clarifyingQuestion: String? = nil,
                warnings: [String] = [], modelID: String? = nil, usedDepth: Bool = false) {
        self.title = title
        self.items = items
        self.overallConfidence = overallConfidence
        self.clarifyingQuestion = clarifyingQuestion
        self.warnings = warnings
        self.modelID = modelID
        self.usedDepth = usedDepth
    }

    public var total: Nutrients { items.map(\.nutrients).sum() }

    /// Sum of item ranges (a conservative envelope).
    public var kcalRange: ClosedRange<Double> {
        let low = items.map(\.kcalRange.lowerBound).reduce(0, +)
        let high = items.map(\.kcalRange.upperBound).reduce(0, +)
        return low...max(low, high)
    }
}

/// Deterministic checks on the model's answer: database nutrients, energy ranges and the volume × density arithmetic.
public enum NutritionResolver {
    public static let matchDisagreementThreshold = 0.4
    public static let recomputeThreshold = 0.1

    public static func resolve(_ analysis: AIMealAnalysis, database: FoodDatabase, extraFoods: [FoodRecord] = [], modelID: String? = nil, usedDepth: Bool = false) -> MealEstimate {
        let extras = Dictionary(extraFoods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items = analysis.items.compactMap { item -> EstimatedItem? in
            guard item.grams.isFinite, item.grams > 0 else { return nil }
            var flags: [ItemFlag] = item.isHiddenIngredient ? [.hiddenIngredient] : []

            var grams = item.grams
            var low = item.gramsLow.isFinite && item.gramsLow > 0 ? item.gramsLow : grams * 0.75
            var high = item.gramsHigh.isFinite && item.gramsHigh > 0 ? item.gramsHigh : grams * 1.25
            if item.method == .depthVolume, let volume = item.volumeMl, let density = item.densityGPerMl, volume > 0, density > 0 {
                let computed = volume * density
                if abs(computed - grams) / computed > recomputeThreshold {
                    let factor = computed / grams
                    grams = computed
                    low *= factor
                    high *= factor
                    flags.append(.gramsRecomputed)
                }
            }
            low = min(low, grams)
            high = max(high, grams)

            let model = Nutrients(kcal: item.per100g.kcal, protein: item.per100g.proteinG, carbs: item.per100g.carbsG, fat: item.per100g.fatG)
            var per100g = model
            var match: FoodMatch?
            if let id = item.foodID, let record = extras[id] ?? database.record(id: id) {
                match = FoodMatch(id: record.id, name: record.name, source: record.source)
                per100g = record.per100g
                if let range = record.kcalRange, record.per100g.kcal > 0 {
                    let chosen = model.kcal > 0 ? model.kcal.clamped(to: range) : record.per100g.kcal
                    per100g = record.per100g.scaled(by: chosen / record.per100g.kcal)
                } else if model.kcal > 0, record.per100g.kcal > 0,
                          abs(model.kcal - record.per100g.kcal) / max(model.kcal, record.per100g.kcal) > matchDisagreementThreshold {
                    flags.append(.checkMatch)
                }
            } else {
                flags.append(.aiEstimate)
            }

            return EstimatedItem(
                name: item.name,
                grams: grams.rounded(),
                gramsLow: low.rounded(),
                gramsHigh: high.rounded(),
                per100g: per100g,
                food: match,
                method: item.method,
                confidence: item.confidence.clamped(to: 0...1),
                flags: flags,
                polygon: item.polygon,
                notes: item.notes
            )
        }
        return MealEstimate(
            title: analysis.mealTitle,
            items: items,
            overallConfidence: analysis.overallConfidence.clamped(to: 0...1),
            clarifyingQuestion: analysis.clarifyingQuestion,
            warnings: analysis.warnings,
            modelID: modelID,
            usedDepth: usedDepth
        )
    }
}
