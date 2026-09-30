import Foundation
import Testing
@testable import LooseweightKit

struct FoodPresenceDetectorTests {
    private func labels(_ pairs: [(String, Double)]) -> [ClassifierLabel] {
        pairs.map { ClassifierLabel(label: $0.0, confidence: $0.1) }
    }

    @Test func recognisesFoodLabels() {
        for label in ["food", "Fruit", "baked_goods", "ice_cream", "salad", "drink", "beverage", "dessert", "bread", "meal"] {
            #expect(FoodPresenceDetector.isFoodLabel(label), "\(label)")
        }
        for label in ["laptop", "dog", "people", "food_processor", "coffee_table", "plate", "structure", "ice", ""] {
            #expect(!FoodPresenceDetector.isFoodLabel(label), "\(label)")
        }
    }

    @Test func scoreIsStrongestFoodLabel() {
        let frame = labels([("structure", 0.9), ("food", 0.62), ("fruit", 0.4)])
        #expect(FoodPresenceDetector.foodScore(frame) == 0.62)
        #expect(FoodPresenceDetector.foodScore(labels([("laptop", 0.95)])) == 0)
        #expect(FoodPresenceDetector.looksLikeFood(frame))
        #expect(!FoodPresenceDetector.looksLikeFood(labels([("food", 0.1), ("screen", 0.9)])))
    }

    @Test func staysUnknownUntilEnoughFramesThenTurnsNotFood() {
        var detector = FoodPresenceDetector()
        let desk = labels([("laptop", 0.9)])
        #expect(detector.add(desk) == .unknown)
        #expect(detector.add(desk) == .unknown)
        #expect(detector.add(desk) == .notFood)
    }

    @Test func foodIsImmediateAndOneMissDoesNotFlicker() {
        var detector = FoodPresenceDetector()
        let meal = labels([("food", 0.8)])
        let miss = labels([("table", 0.7)])
        #expect(detector.add(meal) == .food)
        #expect(detector.add(meal) == .food)
        #expect(detector.add(meal) == .food)
        #expect(detector.add(miss) == .food) // mean 0.6
        #expect(detector.add(miss) == .food) // mean 0.4
        #expect(detector.add(miss) == .food) // mean 0.2 — between thresholds, keeps food
        #expect(detector.add(miss) == .notFood) // mean 0
        #expect(detector.add(meal) == .notFood) // mean 0.2 — hysteresis holds
        #expect(detector.add(meal) == .food) // mean 0.4
    }

    @Test func weakFoodSignalGetsBenefitOfTheDoubt() {
        var detector = FoodPresenceDetector()
        let weak = labels([("food", 0.2)])
        detector.add(weak); detector.add(weak)
        #expect(detector.add(weak) == .food)
        detector.reset()
        #expect(detector.verdict == .unknown)
    }
}

struct NoFoodAnalysisTests {
    @Test func decodesNoFoodFlag() throws {
        let text = #"{"meal_title":"","items":[],"overall_confidence":0,"clarifying_question":null,"warnings":[],"no_food":true,"no_food_reason":"a laptop on a desk"}"#
        let analysis = try AIMealAnalysis.decode(from: text)
        #expect(analysis.noFood)
        #expect(analysis.noFoodReason == "a laptop on a desk")
        #expect(analysis.hasNoFood)
    }

    @Test func missingFlagDefaultsToFood() throws {
        let text = #"{"meal_title":"x","items":[],"overall_confidence":0.5,"clarifying_question":null,"warnings":[]}"#
        let analysis = try AIMealAnalysis.decode(from: text)
        #expect(!analysis.noFood)
        #expect(analysis.hasNoFood) // zero items is still nothing to log
    }

    @Test func schemaRequiresNoFood() {
        guard case let .array(required)? = AnalysisPrompt.outputSchema["required"] else {
            Issue.record("schema shape"); return
        }
        #expect(required.contains(.string("no_food")))
        #expect(required.contains(.string("no_food_reason")))
    }

    private func analyzer(answer: String) -> MealAnalyzer {
        let body = #"{"id":"m","type":"message","role":"assistant","model":"x","stop_reason":"end_turn","content":[{"type":"text","text":"# + jsonString(answer) + #"}],"usage":{}}"#
        let transport = MockTransport { _, _ in HTTPResponse(status: 200, body: Fixtures.json(body)) }
        var client = ClaudeClient(connection: .anthropic(apiKey: "k"), transport: transport)
        client.backoff = { _ in }
        return MealAnalyzer(client: client, database: .shared)
    }

    private func jsonString(_ text: String) -> String {
        let data = try! JSONEncoder().encode(text)
        return String(decoding: data, as: UTF8.self)
    }

    private var request: AnalysisRequest { AnalysisRequest(photoJPEG: Data([1]), insights: CaptureInsights(photoWidth: 10, photoHeight: 10)) }

    @Test func analyzerThrowsNoFood() async {
        let answer = #"{"meal_title":"","items":[],"overall_confidence":0,"clarifying_question":null,"warnings":[],"no_food":true,"no_food_reason":"a cat"}"#
        let analyzer = analyzer(answer: answer)
        await #expect(throws: ClaudeError.noFood(reason: "a cat")) {
            _ = try await analyzer.analyze(request, model: "m")
        }
        #expect(ClaudeError.noFood(reason: nil).userMessage.hasPrefix("No food found in this photo"))
    }

    @Test func analyzerThrowsNoFoodForEmptyItems() async {
        let answer = #"{"meal_title":"Meal","items":[],"overall_confidence":0.5,"clarifying_question":null,"warnings":[],"no_food":false,"no_food_reason":null}"#
        let analyzer = analyzer(answer: answer)
        await #expect(throws: ClaudeError.noFood(reason: nil)) {
            _ = try await analyzer.analyze(request, model: "m")
        }
    }
}

struct DrinkGateTests {
    @Test func drinksAndTheirContainersPassTheGate() {
        for label in ["cup", "Coffee", "tea", "mug", "wine_glass", "glass", "bottle", "water_bottle", "juice", "smoothie", "milk", "soda", "can", "drinking_glass", "latte"] {
            #expect(FoodPresenceDetector.isFoodLabel(label), "\(label)")
        }
        for label in ["trash_can", "sunglasses", "eyeglasses", "stained_glass", "water", "coffee_table"] {
            #expect(!FoodPresenceDetector.isFoodLabel(label), "\(label)")
        }
    }
}
