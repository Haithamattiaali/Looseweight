import Foundation

/// Decides "food or not" from on-device image-classifier labels (Apple Vision's taxonomy), smoothed over the last
/// few camera frames so the verdict does not flicker. Pure logic: the app feeds it labels.
public struct FoodPresenceDetector: Sendable {
    public enum Verdict: String, Sendable, Equatable {
        /// Not enough frames yet; treat as food (never block on a guess).
        case unknown
        case food
        case notFood
    }

    /// Words that mark a classifier label as food or drink. Matched against whole words of the label.
    public static let foodWords: Set<String> = [
        "food", "foods", "meal", "dish", "dishes", "cuisine", "fruit", "fruits", "vegetable", "vegetables", "produce",
        "bread", "baked", "goods", "pastry", "croissant", "bagel", "toast", "sandwich", "burger", "hamburger", "hotdog",
        "pizza", "pasta", "noodles", "spaghetti", "rice", "sushi", "salad", "soup", "stew", "curry", "meat", "steak",
        "chicken", "beef", "pork", "lamb", "sausage", "bacon", "seafood", "fish", "shrimp", "egg", "eggs", "cheese",
        "dessert", "cake", "cookie", "cookies", "biscuit", "muffin", "cupcake", "pie", "donut", "doughnut", "chocolate",
        "candy", "icecream", "ice", "cream", "yogurt", "pudding", "snack", "fries", "chips", "popcorn", "nut", "nuts",
        "cereal", "oatmeal", "porridge", "pancake", "waffle", "taco", "burrito", "dumpling", "kebab", "falafel",
        "hummus", "sauce", "dip", "drink", "drinks", "beverage", "beverages", "coffee", "tea", "juice", "smoothie",
        "milk", "milkshake", "wine", "beer", "cocktail", "soda", "water", "apple", "banana", "orange", "citrus",
        "berry", "berries", "grape", "grapes", "strawberry", "tomato", "potato", "carrot", "broccoli", "lettuce",
        "mushroom", "corn", "avocado", "melon", "watermelon", "pineapple", "mango", "date", "dates", "breakfast",
        "lunch", "dinner", "brunch", "barbecue", "grill", "kabsa", "biryani",
        // Drinks and what they come in.
        "cup", "cups", "mug", "mugs", "teacup", "glass", "glasses", "wineglass", "tumbler", "bottle", "bottles",
        "can", "cans", "carton", "jug", "pitcher", "latte", "cappuccino", "espresso", "lemonade", "shake", "cola",
        "kombucha", "broth", "cocoa", "drinking", "straw", "thermos", "flask", "teapot",
    ]

    /// Labels that contain a food word but are not food.
    public static let excludedLabels: Set<String> = [
        "food processor", "food truck", "food court", "ice skating", "ice hockey", "ice rink", "orange sky",
        "water body", "waterfall", "water sport", "underwater", "grill appliance", "date palm", "fish tank", "aquarium",
        "coffee table", "coffee maker", "tea kettle", "wine rack", "beer tap", "ice", "water", "cream colored",
        "glass window", "stained glass", "glass building", "can opener", "trash can", "garbage can", "kettle",
        "straw hat", "shake hands", "eye glasses", "eyeglasses", "sunglasses", "glasses frame",
    ]

    /// A frame counts as food when its strongest food label reaches this confidence.
    public var foodThreshold: Double
    /// Below this smoothed score the verdict turns to not-food (hysteresis between the two).
    public var notFoodThreshold: Double
    /// Number of recent frames averaged.
    public var window: Int
    /// Frames needed before a not-food verdict is allowed.
    public var minimumFrames: Int

    public private(set) var verdict: Verdict = .unknown
    private var scores: [Double] = []

    public init(foodThreshold: Double = 0.3, notFoodThreshold: Double = 0.15, window: Int = 4, minimumFrames: Int = 3) {
        self.foodThreshold = foodThreshold
        self.notFoodThreshold = min(notFoodThreshold, foodThreshold)
        self.window = max(1, window)
        self.minimumFrames = max(1, min(minimumFrames, max(1, window)))
    }

    /// Normalised label: lower case, underscores and dashes as spaces.
    static func normalized(_ label: String) -> String {
        label.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    public static func isFoodLabel(_ label: String) -> Bool {
        let text = normalized(label)
        if text.isEmpty || excludedLabels.contains(text) { return false }
        let words = text.split(separator: " ").map(String.init)
        return words.contains { foodWords.contains($0) }
    }

    /// Strongest food-label confidence in one frame, 0...1.
    public static func foodScore(_ labels: [ClassifierLabel]) -> Double {
        labels.filter { isFoodLabel($0.label) }.map { min(max($0.confidence, 0), 1) }.max() ?? 0
    }

    /// One-shot check for a single photo (library pick).
    public static func looksLikeFood(_ labels: [ClassifierLabel], threshold: Double = 0.3) -> Bool {
        foodScore(labels) >= threshold
    }

    /// Mean score over the window.
    public var smoothedScore: Double {
        scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }

    /// Adds one frame's labels and returns the updated verdict.
    @discardableResult
    public mutating func add(_ labels: [ClassifierLabel]) -> Verdict {
        scores.append(Self.foodScore(labels))
        if scores.count > window { scores.removeFirst(scores.count - window) }
        let score = smoothedScore
        if score >= foodThreshold {
            verdict = .food
        } else if score < notFoodThreshold, scores.count >= minimumFrames {
            verdict = .notFood
        } else if verdict == .unknown, scores.count >= minimumFrames, score < foodThreshold {
            // Between the thresholds with no earlier verdict: give the benefit of the doubt.
            verdict = .food
        }
        return verdict
    }

    public mutating func reset() {
        scores.removeAll()
        verdict = .unknown
    }
}
