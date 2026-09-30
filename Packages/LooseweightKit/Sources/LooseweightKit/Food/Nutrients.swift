import Foundation

/// Energy and macronutrients. Used both as "per 100 g" values and as absolute amounts.
public struct Nutrients: Codable, Hashable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fiber: Double

    public init(kcal: Double, protein: Double, carbs: Double, fat: Double, fiber: Double = 0) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
    }

    public static let zero = Nutrients(kcal: 0, protein: 0, carbs: 0, fat: 0, fiber: 0)

    public func scaled(by factor: Double) -> Nutrients {
        Nutrients(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor, fiber: fiber * factor)
    }

    /// Treats `self` as per-100 g values and returns the amount in `grams`.
    public func amount(forGrams grams: Double) -> Nutrients {
        scaled(by: max(grams, 0) / 100)
    }

    public static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        Nutrients(
            kcal: lhs.kcal + rhs.kcal,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat,
            fiber: lhs.fiber + rhs.fiber
        )
    }

    public static func += (lhs: inout Nutrients, rhs: Nutrients) {
        lhs = lhs + rhs
    }

    /// Energy implied by the macros (Atwater 4/4/9). Alcohol is not modelled.
    public var atwaterKcal: Double { protein * 4 + carbs * 4 + fat * 9 }
}

extension Sequence where Element == Nutrients {
    public func sum() -> Nutrients { reduce(.zero, +) }
}
