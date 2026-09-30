import Foundation

/// Whether an item is eaten or drunk. Drinks are first-class: they are counted in sips and their natural container.
public enum FoodKind: String, Codable, CaseIterable, Hashable, Sendable {
    case food
    case drink
}

/// The natural unit a drink is served or counted in. Millilitres per unit stay inside the engine.
public enum DrinkUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case sip
    case cup
    case glass
    case can
    case bottle
    case mug

    /// Typical volume of one unit in mL.
    public var defaultMl: Double {
        switch self {
        case .sip: 20
        case .cup: 240
        case .glass: 250
        case .can: 330
        case .bottle: 500
        case .mug: 300
        }
    }

    public func noun(for count: Double) -> String {
        let plural = abs(count - 1) > 0.01 && count > 0
        switch self {
        case .sip: return plural ? "sips" : "sip"
        case .cup: return plural ? "cups" : "cup"
        case .glass: return plural ? "glasses" : "glass"
        case .can: return plural ? "cans" : "can"
        case .bottle: return plural ? "bottles" : "bottle"
        case .mug: return plural ? "mugs" : "mug"
        }
    }
}

/// Recognises drinks by name and picks their natural container.
public enum DrinkCatalog {
    /// Drink density used to turn mL into grams (most drinks are close to water).
    public static let densityGPerMl = 1.03

    /// The natural container for a drink name ("Cola" → can, "Latte" → mug, "Orange juice" → glass).
    public static func naturalUnit(name: String) -> DrinkUnit {
        let text = name.lowercased()
        func has(_ keys: [String]) -> Bool { PortionSizes.matches(text, keys) }
        if has(["cola", "soda", "energy drink", "sparkling", "beer", "tonic", "sprite", "fanta", "pepsi"]) { return .can }
        if has(["coffee", "latte", "cappuccino", "flat white", "americano", "espresso", "tea", "hot chocolate", "cocoa", "mocha"]) { return .mug }
        if has(["smoothie", "shake", "milkshake", "soup", "broth", "frappe", "yogurt drink"]) { return .cup }
        if has(["water"]) && has(["bottle", "bottled"]) { return .bottle }
        return .glass
    }

    /// True for drinks, including soups served to be drunk.
    public static func isDrink(name: String, category: String = "") -> Bool {
        PortionSizes.isDrink(name: name, category: category)
    }
}
