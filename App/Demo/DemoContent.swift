import LooseweightKit
import SwiftData
import SwiftUI
import UIKit

/// Offline demo: a real weighed cafeteria plate (Nutrition5k dish 1564773942, 442 g in total) with the
/// portions the scale measured, so the simulator and first-time users see an honest example.
enum DemoContent {
    /// The photo comes from `LW_DEMO_PHOTO` when set (CI downloads the dataset image); otherwise a drawn plate.
    static func photo() -> UIImage {
        if let path = ProcessInfo.processInfo.environment["LW_DEMO_PHOTO"], let image = UIImage(contentsOfFile: path) {
            return image
        }
        return placeholderPlate()
    }

    static var hasRealPhoto: Bool {
        ProcessInfo.processInfo.environment["LW_DEMO_PHOTO"].map { FileManager.default.fileExists(atPath: $0) } ?? false
    }

    private struct DemoItem {
        var name: String
        var query: String
        var grams: Double
        var low: Double
        var high: Double
        var method: PortionMethod
        var volume: Double?
        var density: Double?
        var confidence: Double
        var polygon: [[Double]]
        var hidden = false
        var notes = ""
    }

    private static let items: [DemoItem] = [
        DemoItem(name: "Grilled chicken breast", query: "chicken breast roasted", grams: 106, low: 92, high: 120, method: .depthVolume,
                 volume: 103, density: 1.03, confidence: 0.84,
                 polygon: [[265, 60], [390, 55], [470, 95], [470, 215], [420, 235], [360, 285], [310, 255], [245, 210], [250, 110]],
                 notes: "Diced pieces; volume measured by LiDAR."),
        DemoItem(name: "Pineapple", query: "pineapple raw", grams: 117, low: 100, high: 135, method: .depthVolume,
                 volume: 170, density: 0.69, confidence: 0.8,
                 polygon: [[160, 120], [250, 90], [300, 95], [290, 200], [230, 240], [225, 310], [175, 315], [155, 215]]),
        DemoItem(name: "Salmon fillet", query: "salmon baked", grams: 65, low: 55, high: 78, method: .depthVolume,
                 volume: 63, density: 1.03, confidence: 0.78,
                 polygon: [[430, 270], [500, 260], [555, 285], [560, 350], [520, 410], [470, 425], [435, 400], [425, 330]]),
        DemoItem(name: "Cherry tomatoes", query: "tomatoes cherry raw", grams: 59, low: 52, high: 66, method: .count,
                 volume: nil, density: nil, confidence: 0.9,
                 polygon: [[220, 240], [300, 215], [310, 300], [300, 370], [270, 390], [240, 385], [215, 290]],
                 notes: "6 small tomatoes."),
        DemoItem(name: "Steamed broccoli", query: "broccoli cooked boiled", grams: 58, low: 45, high: 72, method: .depthVolume,
                 volume: 105, density: 0.55, confidence: 0.72,
                 polygon: [[295, 290], [365, 250], [430, 230], [500, 260], [495, 340], [430, 370], [385, 380], [350, 405], [300, 395], [290, 330]]),
        DemoItem(name: "Lentils", query: "lentils cooked", grams: 13, low: 8, high: 20, method: .visualEstimate,
                 volume: nil, density: nil, confidence: 0.5, polygon: []),
        DemoItem(name: "Mayonnaise", query: "mayonnaise", grams: 10, low: 5, high: 15, method: .visualEstimate,
                 volume: nil, density: nil, confidence: 0.55, polygon: [], hidden: true,
                 notes: "Glossy coating on the chicken."),
    ]

    static let groundTruthKcal = 492.0

    static func analysis(database: FoodDatabase) -> AIMealAnalysis {
        AIMealAnalysis(
            mealTitle: "Chicken, salmon and fruit plate",
            items: items.map { item in
                let match = database.search(item.query, limit: 1).first?.record
                let per100g = match?.per100g ?? .zero
                return AIMealAnalysis.Item(
                    name: item.name,
                    foodID: match?.id,
                    grams: item.grams,
                    gramsLow: item.low,
                    gramsHigh: item.high,
                    method: item.method,
                    volumeMl: item.volume,
                    densityGPerMl: item.density,
                    per100g: .init(kcal: per100g.kcal, proteinG: per100g.protein, carbsG: per100g.carbs, fatG: per100g.fat),
                    confidence: item.confidence,
                    regionNumbers: [1],
                    polygon: hasRealPhoto ? item.polygon : [],
                    isHiddenIngredient: item.hidden,
                    notes: item.notes
                )
            },
            overallConfidence: 0.78,
            clarifyingQuestion: "Was the chicken dressed with mayonnaise, or is that shine from oil?",
            warnings: []
        )
    }

    static func estimate(database: FoodDatabase = .shared) -> MealEstimate {
        NutritionResolver.resolve(analysis(database: database), database: database, modelID: "demo", usedDepth: true)
    }

    /// Profile, 5 weeks of weigh-ins and a few meals, so every screen has content in UI tests.
    @MainActor
    static func seed(into context: ModelContext, model: AppModel, calendar: Calendar = .current) {
        Store.deleteEverything(in: context)
        model.profile = UserProfile(sex: .male, birthYear: 1988, heightCm: 176, weightKg: 88, goalWeightKg: 78, activity: .light, weeklyLossKg: 0.5)
        let now = Date()
        for day in stride(from: 35, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -day, to: now) else { continue }
            if day % 2 == 0 || day < 5 {
                let wobble = [0.35, -0.25, 0.1, -0.4, 0.2][day % 5]
                context.insert(WeightLog(date: date, kg: 90.2 - Double(35 - day) * 0.075 + wobble))
            }
            if day > 0 {
                let meal = MealLog(date: calendar.date(bySettingHour: 13, minute: 0, second: 0, of: date) ?? date, title: "Logged day", mealType: .lunch, source: "seed")
                context.insert(meal)
                let log = FoodLog(name: "Day total", grams: 100, per100g: Nutrients(kcal: 1_900 + Double((day * 37) % 250), protein: 120, carbs: 190, fat: 65), foodID: nil, method: .userNote, confidence: 1)
                log.meal = meal
                meal.items.append(log)
            }
        }
        let breakfast = MealEstimate(
            title: "Greek yogurt with berries",
            items: [
                EstimatedItem(name: "Greek yogurt", grams: 170, gramsLow: 160, gramsHigh: 180, per100g: Nutrients(kcal: 97, protein: 9, carbs: 3.9, fat: 5), food: nil, method: .label, confidence: 0.95),
                EstimatedItem(name: "Blueberries", grams: 80, gramsLow: 65, gramsHigh: 95, per100g: Nutrients(kcal: 57, protein: 0.7, carbs: 14.5, fat: 0.3), food: nil, method: .visualEstimate, confidence: 0.7),
            ],
            overallConfidence: 0.85, clarifyingQuestion: nil, warnings: [], modelID: "demo", usedDepth: false
        )
        Store.save(breakfast, mealType: .breakfast, photo: nil, date: calendar.date(bySettingHour: 8, minute: 15, second: 0, of: now) ?? now, source: "seed", in: context)
        try? context.save()
    }

    private static func placeholderPlate() -> UIImage {
        let size = CGSize(width: 1200, height: 900)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            UIColor(red: 0.84, green: 0.80, blue: 0.74, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.97, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 180, y: 60, width: 840, height: 780))
            UIColor(white: 0.92, alpha: 1).setStroke()
            cg.setLineWidth(10)
            cg.strokeEllipse(in: CGRect(x: 250, y: 130, width: 700, height: 640))
            let blobs: [(CGRect, UIColor)] = [
                (CGRect(x: 330, y: 190, width: 330, height: 250), UIColor(red: 0.93, green: 0.86, blue: 0.72, alpha: 1)),
                (CGRect(x: 640, y: 220, width: 230, height: 200), UIColor(red: 0.98, green: 0.78, blue: 0.25, alpha: 1)),
                (CGRect(x: 360, y: 460, width: 280, height: 220), UIColor(red: 0.20, green: 0.52, blue: 0.22, alpha: 1)),
                (CGRect(x: 650, y: 450, width: 210, height: 190), UIColor(red: 0.85, green: 0.45, blue: 0.30, alpha: 1)),
            ]
            for (rect, color) in blobs {
                color.setFill()
                cg.fillEllipse(in: rect)
            }
        }
    }
}
