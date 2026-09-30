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
        /// Food or drink. Missing in older answers: decoded as food, and the resolver checks the name.
        public var kind: FoodKind
        /// For drinks: the natural unit (glass, can, mug...) and its volume.
        public var drinkUnit: DrinkUnit?
        public var mlPerUnit: Double?

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
            case kind
            case drinkUnit = "drink_unit"
            case mlPerUnit = "ml_per_unit"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            foodID = try c.decodeIfPresent(String.self, forKey: .foodID)
            grams = try c.decode(Double.self, forKey: .grams)
            gramsLow = try c.decodeIfPresent(Double.self, forKey: .gramsLow) ?? 0
            gramsHigh = try c.decodeIfPresent(Double.self, forKey: .gramsHigh) ?? 0
            method = (try? c.decode(PortionMethod.self, forKey: .method)) ?? .visualEstimate
            volumeMl = try c.decodeIfPresent(Double.self, forKey: .volumeMl)
            densityGPerMl = try c.decodeIfPresent(Double.self, forKey: .densityGPerMl)
            per100g = try c.decode(Per100g.self, forKey: .per100g)
            confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.5
            regionNumbers = try c.decodeIfPresent([Int].self, forKey: .regionNumbers) ?? []
            polygon = try c.decodeIfPresent([[Double]].self, forKey: .polygon) ?? []
            isHiddenIngredient = try c.decodeIfPresent(Bool.self, forKey: .isHiddenIngredient) ?? false
            notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
            kind = (try? c.decodeIfPresent(FoodKind.self, forKey: .kind)) ?? .food
            drinkUnit = try? c.decodeIfPresent(DrinkUnit.self, forKey: .drinkUnit)
            mlPerUnit = try c.decodeIfPresent(Double.self, forKey: .mlPerUnit)
        }

        public init(name: String, foodID: String?, grams: Double, gramsLow: Double, gramsHigh: Double, method: PortionMethod,
                    volumeMl: Double? = nil, densityGPerMl: Double? = nil, per100g: Per100g, confidence: Double,
                    regionNumbers: [Int] = [], polygon: [[Double]] = [], isHiddenIngredient: Bool = false, notes: String = "",
                    kind: FoodKind = .food, drinkUnit: DrinkUnit? = nil, mlPerUnit: Double? = nil) {
            self.kind = kind
            self.drinkUnit = drinkUnit
            self.mlPerUnit = mlPerUnit
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
    /// True when the photo shows no food or drink at all.
    public var noFood: Bool
    /// Short plain-English reason when `noFood` is true (what the photo shows instead).
    public var noFoodReason: String?

    enum CodingKeys: String, CodingKey {
        case mealTitle = "meal_title"
        case items
        case overallConfidence = "overall_confidence"
        case clarifyingQuestion = "clarifying_question"
        case warnings
        case noFood = "no_food"
        case noFoodReason = "no_food_reason"
    }

    public init(mealTitle: String, items: [Item], overallConfidence: Double, clarifyingQuestion: String? = nil, warnings: [String] = [],
                noFood: Bool = false, noFoodReason: String? = nil) {
        self.mealTitle = mealTitle
        self.items = items
        self.overallConfidence = overallConfidence
        self.clarifyingQuestion = clarifyingQuestion
        self.warnings = warnings
        self.noFood = noFood
        self.noFoodReason = noFoodReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mealTitle = try container.decodeIfPresent(String.self, forKey: .mealTitle) ?? ""
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        overallConfidence = try container.decodeIfPresent(Double.self, forKey: .overallConfidence) ?? 0
        clarifyingQuestion = try container.decodeIfPresent(String.self, forKey: .clarifyingQuestion)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        noFood = try container.decodeIfPresent(Bool.self, forKey: .noFood) ?? false
        noFoodReason = try container.decodeIfPresent(String.self, forKey: .noFoodReason)
    }

    /// True when the answer holds nothing to log: flagged as no food, or no items at all.
    public var hasNoFood: Bool { noFood || items.isEmpty }

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
    public var kind: FoodKind
    /// For drinks: the natural unit and mL in one unit (internal).
    public var drinkUnit: DrinkUnit?
    public var mlPerUnit: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, grams, gramsLow, gramsHigh, per100g, food, method, confidence, flags, polygon, notes, kind, drinkUnit, mlPerUnit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        grams = try c.decode(Double.self, forKey: .grams)
        gramsLow = try c.decodeIfPresent(Double.self, forKey: .gramsLow) ?? grams
        gramsHigh = try c.decodeIfPresent(Double.self, forKey: .gramsHigh) ?? grams
        per100g = try c.decode(Nutrients.self, forKey: .per100g)
        food = try c.decodeIfPresent(FoodMatch.self, forKey: .food)
        method = (try? c.decode(PortionMethod.self, forKey: .method)) ?? .visualEstimate
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.5
        flags = (try? c.decodeIfPresent([ItemFlag].self, forKey: .flags)) ?? []
        polygon = try c.decodeIfPresent([[Double]].self, forKey: .polygon) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        kind = (try? c.decodeIfPresent(FoodKind.self, forKey: .kind)) ?? (PortionSizes.isDrink(name: name) ? .drink : .food)
        drinkUnit = try? c.decodeIfPresent(DrinkUnit.self, forKey: .drinkUnit)
        mlPerUnit = try c.decodeIfPresent(Double.self, forKey: .mlPerUnit)
    }

    public init(id: UUID = UUID(), name: String, grams: Double, gramsLow: Double, gramsHigh: Double, per100g: Nutrients,
                food: FoodMatch?, method: PortionMethod, confidence: Double, flags: [ItemFlag] = [], polygon: [[Double]] = [], notes: String = "",
                kind: FoodKind? = nil, drinkUnit: DrinkUnit? = nil, mlPerUnit: Double? = nil) {
        let resolvedKind = kind ?? (PortionSizes.isDrink(name: name) ? .drink : .food)
        self.kind = resolvedKind
        self.drinkUnit = resolvedKind == .drink ? (drinkUnit ?? DrinkCatalog.naturalUnit(name: name)) : nil
        self.mlPerUnit = resolvedKind == .drink ? mlPerUnit : nil
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
    public var isDrink: Bool { kind == .drink }
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
    public var drinks: [EstimatedItem] { items.filter(\.isDrink) }

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

            // Drinks: trust the answer's kind, and catch drinks it labelled as food by name.
            let kind: FoodKind = item.kind == .drink || PortionSizes.isDrink(name: item.name) ? .drink : .food
            var drinkUnit: DrinkUnit?
            var mlPerUnit: Double?
            if kind == .drink {
                let unit = item.drinkUnit ?? DrinkCatalog.naturalUnit(name: item.name)
                drinkUnit = unit
                if let ml = item.mlPerUnit, ml.isFinite, ml >= 5, ml <= 2_000 { mlPerUnit = ml } else { mlPerUnit = unit.defaultMl }
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
                notes: item.notes,
                kind: kind,
                drinkUnit: drinkUnit,
                mlPerUnit: mlPerUnit
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
