import Foundation

/// How a person naturally counts a food while eating: bites, sips, pieces, servings, or a share of the whole item.
public enum PortionUnit: String, Codable, Hashable, Sendable {
    case bite
    case sip
    case piece
    /// A single item that is shared out as a fraction ("2/3 of the piece", "half the sauce").
    case whole
    /// An everyday serving (food added without a photo).
    case serving
}

/// A food's everyday unit and how many grams one unit is. Grams stay inside the engine; people only
/// ever see bites, sips, pieces, servings, containers and fractions.
public struct PortionProfile: Codable, Hashable, Sendable {
    public var unit: PortionUnit
    /// Grams in one bite / sip / piece / serving. For `.whole`, grams in the whole item.
    public var unitGrams: Double
    /// What one whole item is called ("piece", "sauce", "glass").
    public var wholeNoun: String
    /// What one counted piece is called ("slice", "egg"); nil means "piece".
    public var countNoun: String?
    /// For drinks: the natural container (glass, can, mug...) and the grams one holds.
    public var container: DrinkUnit?
    public var containerGrams: Double?

    public init(unit: PortionUnit, unitGrams: Double, wholeNoun: String = "piece", countNoun: String? = nil,
                container: DrinkUnit? = nil, containerGrams: Double? = nil) {
        self.unit = unit
        self.unitGrams = max(unitGrams, 0.5)
        self.wholeNoun = wholeNoun
        self.countNoun = countNoun
        self.container = container == .sip ? nil : container
        self.containerGrams = containerGrams.map { max($0, 1) }
    }

    enum CodingKeys: String, CodingKey {
        case unit, unitGrams, wholeNoun, countNoun, container, containerGrams
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(unit: try c.decodeIfPresent(PortionUnit.self, forKey: .unit) ?? .bite,
                  unitGrams: try c.decodeIfPresent(Double.self, forKey: .unitGrams) ?? PortionSizes.defaultBiteGrams,
                  wholeNoun: try c.decodeIfPresent(String.self, forKey: .wholeNoun) ?? "piece",
                  countNoun: try c.decodeIfPresent(String.self, forKey: .countNoun),
                  container: try c.decodeIfPresent(DrinkUnit.self, forKey: .container),
                  containerGrams: try c.decodeIfPresent(Double.self, forKey: .containerGrams))
    }

    public var isDrink: Bool { unit == .sip }

    /// Units (bites, sips, pieces, servings, or the fraction of the whole) in `grams`.
    public func count(forGrams grams: Double) -> Double {
        max(grams, 0) / unitGrams
    }

    public func grams(forCount count: Double) -> Double {
        max(count, 0) * unitGrams
    }

    static func plural(_ noun: String) -> String {
        if noun.hasSuffix("s") || noun.hasSuffix("ch") || noun.hasSuffix("sh") { return noun + "es" }
        if noun == "bread" { return "breads" }
        return noun + "s"
    }

    /// Singular / plural noun for the counted unit.
    public func noun(for count: Int) -> String {
        switch unit {
        case .bite: return count == 1 ? "bite" : "bites"
        case .sip: return count == 1 ? "sip" : "sips"
        case .piece:
            let noun = countNoun ?? "piece"
            return count == 1 ? noun : Self.plural(noun)
        case .serving: return count == 1 ? "serving" : "servings"
        case .whole: return wholeNoun
        }
    }

    /// "1 glass", "about 1 1/2 cans" — a drink amount in its container, or nil when under 90% of one container.
    public func containerText(grams: Double) -> String? {
        guard unit == .sip, let container, let size = containerGrams, size > 0 else { return nil }
        let value = max(grams, 0) / size
        guard value >= 0.9 else { return nil }
        let halves = (value * 2).rounded() / 2
        let whole = Int(halves.rounded(.down))
        let number = halves - Double(whole) >= 0.5 ? "\(whole) 1/2" : "\(whole)"
        let prefix = abs(value - halves) > 0.08 ? "about " : ""
        return "\(prefix)\(number) \(container.noun(for: halves))"
    }

    /// Plain words for an amount, e.g. "about 7 bites", "5 sips", "1 glass", "2/3 of the piece". Never grams.
    public func describe(grams: Double, approximate: Bool = true) -> String {
        switch unit {
        case .whole:
            let fraction = count(forGrams: grams)
            return PortionText.fraction(fraction, of: wholeNoun)
        case .serving:
            return AmountFormatter.servingsWords(max(count(forGrams: grams), 0.5))
        default:
            if let text = containerText(grams: grams) { return text }
            let value = count(forGrams: grams)
            if value > 0, value < 0.75 { return "less than 1 \(noun(for: 1))" }
            let rounded = Int(value.rounded())
            return "\(approximate && abs(value - Double(rounded)) > 0.05 ? "about " : "")\(rounded) \(noun(for: rounded))"
        }
    }

    /// The size of one step when a person nudges an amount: one bite/sip/piece, half a serving, or a quarter of the whole.
    public var stepGrams: Double {
        switch unit {
        case .whole: return unitGrams / 4
        case .serving: return unitGrams / 2
        default: return unitGrams
        }
    }

    /// Short name of one step for buttons ("1 bite", "¼").
    public var stepTitle: String {
        switch unit {
        case .bite: return "1 bite"
        case .sip: return "1 sip"
        case .piece: return "1 \(countNoun ?? "piece")"
        case .serving: return "½ serving"
        case .whole: return "¼"
        }
    }
}

/// Fraction words shared by plans and confirmations.
public enum PortionText {
    public static let niceFractions: [(value: Double, text: String)] = [
        (0.25, "1/4"), (1.0 / 3, "1/3"), (0.5, "half"), (2.0 / 3, "2/3"), (0.75, "3/4"),
    ]

    /// "2/3 of the piece", "all of the piece", "1 1/2 pieces"-style words for a fraction of one item.
    public static func fraction(_ value: Double, of noun: String) -> String {
        let value = max(value, 0)
        if value < 0.125 { return "none" }
        if value >= 0.92 && value <= 1.08 { return "all of the \(noun)" }
        let whole = Int(value.rounded(.down))
        let rest = value - Double(whole)
        let nearest = niceFractions.min { abs($0.value - rest) < abs($1.value - rest) }
        if whole == 0, let nearest {
            return nearest.text == "half" ? "half the \(noun)" : "\(nearest.text) of the \(noun)"
        }
        if rest < 0.125 { return "\(whole) × the \(noun)" }
        if rest > 0.875 { return "\(whole + 1) × the \(noun)" }
        let part = nearest.map { $0.text == "half" ? "1/2" : $0.text } ?? ""
        return "\(whole) \(part) × the \(noun)"
    }
}

/// Typical bite, sip and piece sizes by food. A bite is a normal forkful or spoonful; a sip ≈ 20 mL.
public enum PortionSizes {
    public static let defaultBiteGrams = 12.0
    public static let sipMl = 20.0

    private static let drinks = ["juice", "milk", "soda", "cola", "coffee", "tea", "latte", "cappuccino", "smoothie", "water",
                                 "beer", "wine", "shake", "drink", "beverage", "lemonade", "kefir", "ayran", "laban", "espresso",
                                 "americano", "mocha", "frappe", "hot chocolate", "cocoa", "kombucha", "tonic", "sparkling",
                                 "broth", "sprite", "fanta", "pepsi", "iced tea", "mojito", "karak", "chai"]
    private static let sauces = ["mayonnaise", "mayo", "oil", "butter", "dressing", "sauce", "ketchup", "gravy", "syrup", "honey",
                                 "cream cheese", "tahini", "pesto", "vinaigrette", "aioli", "ghee", "jam", "mustard"]

    /// Named pieces with a typical weight. Checked in order, first match wins.
    private static let pieces: [(keys: [String], grams: Double, noun: String)] = [
        (["cherry tomato", "grape tomato"], 10, "piece"),
        (["grape"], 5, "piece"),
        (["strawberr"], 12, "piece"),
        (["date"], 8, "piece"),
        (["olive"], 4, "piece"),
        (["almond", "cashew", "walnut", "peanut", "pistachio"], 1.3, "piece"),
        (["nugget"], 18, "piece"),
        (["falafel"], 17, "piece"),
        (["meatball", "kofta"], 30, "piece"),
        (["dumpling", "gyoza", "momo"], 25, "piece"),
        (["sushi", "maki", "nigiri"], 30, "piece"),
        (["cookie", "biscuit"], 15, "piece"),
        (["wing"], 35, "piece"),
        (["drumstick"], 75, "piece"),
        (["thigh"], 90, "piece"),
        (["egg"], 50, "egg"),
        (["samosa"], 50, "piece"),
        (["croissant"], 60, "croissant"),
        (["muffin", "cupcake"], 110, "muffin"),
        (["pizza"], 110, "slice"),
        (["toast", "bread", "slice"], 30, "slice"),
        (["pita", "tortilla", "wrap", "naan", "flatbread"], 60, "bread"),
        (["burger", "sandwich", "shawarma", "hot dog", "burrito"], 220, "sandwich"),
        (["banana"], 118, "banana"),
        (["apple"], 180, "apple"),
        (["orange"], 130, "orange"),
        (["salmon", "fish fillet", "fillet", "cod", "tilapia"], 120, "piece"),
        (["steak", "pork chop", "lamb chop"], 200, "piece"),
        (["chicken breast", "grilled chicken", "chicken"], 150, "piece"),
    ]

    /// Bite sizes for foods eaten by the forkful or spoonful.
    private static let bites: [(keys: [String], grams: Double)] = [
        (["soup", "stew", "curry", "lentil", "dal", "beans", "chili", "porridge", "oat", "yogurt", "yoghurt", "hummus", "labneh"], 15),
        (["rice", "pasta", "noodle", "couscous", "quinoa", "bulgur", "freekeh", "spaghetti", "macaroni", "potato", "fries", "mash"], 15),
        (["beef", "lamb", "pork", "meat", "turkey", "tuna", "shrimp", "prawn", "tofu", "cheese"], 15),
        (["salad", "lettuce", "spinach", "greens", "broccoli", "cauliflower", "carrot", "cucumber", "pepper", "vegetable", "tomato", "zucchini"], 12),
        (["pineapple", "melon", "watermelon", "mango", "berries", "blueberr", "fruit", "papaya"], 15),
        (["cake", "pie", "dessert", "ice cream", "pudding", "brownie"], 15),
        (["nut", "seed", "granola", "cereal", "chips", "crisps"], 8),
    ]

    /// Words that start with a key but are something else ("watermelon" is not water, "eggplant" is not an egg).
    private static let exceptions = ["watermelon", "eggplant", "pineapple", "chopped", "teriyaki", "buttermilk", "butternut",
                                     "peanut butter", "milk chocolate", "teaspoon", "tearing"]

    /// True when a key appears at the start of a word ("apple" matches "apple slices", not "pineapple").
    static func matches(_ text: String, _ keys: [String]) -> Bool {
        var padded = " " + text.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : " " }.joined() + " "
        for exception in exceptions where !keys.contains(exception) {
            padded = padded.replacingOccurrences(of: " " + exception, with: " _")
        }
        return keys.contains { padded.contains(" " + $0) }
    }

    public static func isDrink(name: String, category: String = "") -> Bool {
        matches(name, drinks) || matches(category, ["beverage", "beverages"])
    }

    static func isSauce(name: String) -> Bool {
        matches(name, sauces)
    }

    /// Chooses the unit people use for a food and the grams in one unit.
    /// - Parameters:
    ///   - grams: the amount in front of the person (used to decide "pieces" vs "fraction of the piece").
    ///   - counted: true when the analysis counted items (cherry tomatoes, nuggets).
    public static func profile(name: String, category: String = "", grams: Double, counted: Bool = false) -> PortionProfile {
        let text = "\(name) \(category)".lowercased()
        if isDrink(name: name, category: category) {
            return drinkProfile(unit: DrinkCatalog.naturalUnit(name: name), mlPerUnit: nil)
        }
        if isSauce(name: name) {
            return PortionProfile(unit: .whole, unitGrams: max(grams, 1), wholeNoun: matches(name, ["oil", "butter", "ghee"]) ? "portion" : "sauce")
        }
        if let piece = pieces.first(where: { matches(text, $0.keys) }) {
            let count = grams / piece.grams
            if piece.grams >= 45 && count < 1.5 {
                // One big item: share it out as a fraction of itself.
                return PortionProfile(unit: .whole, unitGrams: max(grams, 1), wholeNoun: piece.noun)
            }
            if piece.grams < 45 || counted {
                return PortionProfile(unit: .piece, unitGrams: max(grams / max(count.rounded(), 1), 0.5), countNoun: countNoun(piece.noun))
            }
            return PortionProfile(unit: .piece, unitGrams: piece.grams, countNoun: countNoun(piece.noun))
        }
        if counted {
            return PortionProfile(unit: .piece, unitGrams: 10)
        }
        let bite = bites.first { matches(text, $0.keys) }?.grams ?? defaultBiteGrams
        return PortionProfile(unit: .bite, unitGrams: bite)
    }

    /// Counted nouns worth showing ("slice", "egg"); generic ones stay "piece".
    static func countNoun(_ noun: String) -> String? {
        ["slice", "egg"].contains(noun) ? noun : nil
    }

    /// Sips of a drink, with its natural container for whole amounts ("1 glass", "5 sips").
    public static func drinkProfile(unit: DrinkUnit, mlPerUnit: Double?) -> PortionProfile {
        let ml = (mlPerUnit ?? 0) > 0 ? mlPerUnit! : unit.defaultMl
        return PortionProfile(unit: .sip, unitGrams: sipMl * DrinkCatalog.densityGPerMl,
                              container: unit, containerGrams: ml * DrinkCatalog.densityGPerMl)
    }

    /// One everyday serving of a food, for adding food without a photo (no scale needed).
    public static func servingGrams(name: String, category: String = "") -> Double {
        let text = "\(name) \(category)".lowercased()
        if isDrink(name: name, category: category) { return 250 }
        if isSauce(name: name) { return 15 }
        if let piece = pieces.first(where: { matches(text, $0.keys) }) {
            return piece.grams < 20 ? piece.grams * 5 : piece.grams
        }
        if matches(text, ["soup", "stew", "curry"]) { return 250 }
        if matches(text, ["rice", "pasta", "noodle", "couscous", "quinoa", "potato", "fries"]) { return 150 }
        if matches(text, ["salad", "vegetable", "broccoli", "spinach"]) { return 85 }
        if matches(text, ["nut", "seed", "chips", "crisps", "granola", "cereal"]) { return 30 }
        if matches(text, ["beef", "lamb", "pork", "meat", "turkey", "tuna", "fish", "shrimp", "tofu"]) { return 120 }
        if matches(text, ["cheese"]) { return 30 }
        if matches(text, ["yogurt", "yoghurt"]) { return 170 }
        return 100
    }
}

extension EstimatedItem {
    /// The everyday unit for this item, sized from what the analysis saw. Drinks count in sips and their container.
    public var portionProfile: PortionProfile {
        if kind == .drink {
            return PortionSizes.drinkProfile(unit: drinkUnit ?? DrinkCatalog.naturalUnit(name: name), mlPerUnit: mlPerUnit)
        }
        return PortionSizes.profile(name: name, category: food?.name ?? "", grams: grams, counted: method == .count)
    }
}
