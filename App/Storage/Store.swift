import Foundation
import LooseweightKit
import SwiftData

/// Read and write helpers over SwiftData that the screens share.
@MainActor
enum Store {
    static func meals(on day: Date, in context: ModelContext, calendar: Calendar = .current) -> [MealLog] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<MealLog>(predicate: #Predicate { $0.date >= start && $0.date < end }, sortBy: [SortDescriptor(\.date)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func dailyIntakes(days: Int, in context: ModelContext, now: Date = Date(), calendar: Calendar = .current) -> [DailyIntake] {
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
        let descriptor = FetchDescriptor<MealLog>(predicate: #Predicate { $0.date >= start })
        let meals = (try? context.fetch(descriptor)) ?? []
        let grouped = Dictionary(grouping: meals) { calendar.startOfDay(for: $0.date) }
        return grouped.map { DailyIntake(day: $0.key, kcal: $0.value.map(\.total.kcal).reduce(0, +)) }.sorted { $0.day < $1.day }
    }

    static func weights(in context: ModelContext) -> [WeightLog] {
        (try? context.fetch(FetchDescriptor<WeightLog>(sortBy: [SortDescriptor(\.date)]))) ?? []
    }

    static func portionHints(in context: ModelContext, limit: Int = 12) -> [PortionHint] {
        var descriptor = FetchDescriptor<PortionMemory>(sortBy: [SortDescriptor(\.count, order: .reverse)])
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).map { PortionHint(food: $0.name, typicalGrams: $0.typicalGrams, timesLogged: $0.count) }
    }

    @discardableResult
    static func save(_ estimate: MealEstimate, mealType: MealType, photo: Data?, date: Date = Date(), source: String = "photo", in context: ModelContext) -> MealLog {
        let meal = MealLog(date: date, title: estimate.title, mealType: mealType, photo: photo, confidence: estimate.overallConfidence,
                           source: source, modelID: estimate.modelID, usedDepth: estimate.usedDepth)
        context.insert(meal)
        for item in estimate.items where item.grams > 0 {
            let log = FoodLog(name: item.name, grams: item.grams, per100g: item.per100g, foodID: item.food?.id, method: item.method, confidence: item.confidence)
            log.meal = meal
            meal.items.append(log)
            remember(item, in: context)
        }
        try? context.save()
        return meal
    }

    private static func remember(_ item: EstimatedItem, in context: ModelContext) {
        guard let key = item.food?.id else { return }
        let descriptor = FetchDescriptor<PortionMemory>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            existing.record(grams: item.grams)
        } else {
            context.insert(PortionMemory(key: key, name: item.name, grams: item.grams))
        }
    }

    // MARK: Planned meals (Inbox)

    /// What is left of today's targets from confirmed meals only (plans in the Inbox do not count).
    static func remainingToday(targets: DailyTargets?, in context: ModelContext, now: Date = Date()) -> Nutrients {
        let goal = Nutrients(kcal: targets?.kcal ?? 2_000, protein: targets?.proteinG ?? 120, carbs: targets?.carbsG ?? 200, fat: targets?.fatG ?? 65)
        let eaten = meals(on: now, in: context).map(\.total).sum()
        return MealPlanner.remaining(targets: goal, eaten: eaten)
    }

    static func pendingPlans(in context: ModelContext) -> [PlannedMealRecord] {
        let descriptor = FetchDescriptor<PlannedMealRecord>(predicate: #Predicate { $0.isPending == true }, sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    static func savePlan(_ plan: MealPlan, mealType: MealType, photo: Data?, usedDepth: Bool = false, in context: ModelContext) -> PlannedMealRecord {
        let record = PlannedMealRecord(planned: PlannedMeal(plan: plan), mealType: mealType, photo: photo, usedDepth: usedDepth)
        context.insert(record)
        try? context.save()
        return record
    }

    /// Records what happened. Only the eaten share becomes a logged meal (dated when it was planned).
    @discardableResult
    static func confirm(_ record: PlannedMealRecord, as confirmation: PlanConfirmation, now: Date = Date(), in context: ModelContext) -> MealLog? {
        guard var planned = record.planned, planned.confirmation.isPending else { return nil }
        planned.confirm(confirmation, at: now)
        record.planned = planned
        var logged: MealLog?
        if let estimate = planned.confirmedEstimate {
            logged = save(estimate, mealType: record.mealType, photo: record.photo, date: record.createdAt, source: "plan", in: context)
            logged?.usedDepth = record.usedDepth
        }
        try? context.save()
        return logged
    }

    static func logWeight(_ kg: Double, on date: Date = Date(), in context: ModelContext, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<WeightLog>(predicate: #Predicate { $0.date >= start && $0.date < end })
        if let existing = try? context.fetch(descriptor).first {
            existing.kg = kg
            existing.date = date
        } else {
            context.insert(WeightLog(date: date, kg: kg))
        }
        try? context.save()
    }

    static func deleteEverything(in context: ModelContext) {
        try? context.delete(model: FoodLog.self)
        try? context.delete(model: MealLog.self)
        try? context.delete(model: WeightLog.self)
        try? context.delete(model: PortionMemory.self)
        try? context.delete(model: PlannedMealRecord.self)
        try? context.save()
    }

    static func csvExport(in context: ModelContext, units: UnitsMode = .default) -> String {
        let amounts = AmountFormatter(mode: units)
        let meals = (try? context.fetch(FetchDescriptor<MealLog>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let formatter = ISO8601DateFormatter()
        var lines = [amounts.csvMealHeader]
        for meal in meals {
            for item in meal.items {
                let name = item.name.replacingOccurrences(of: "\"", with: "'")
                lines.append("\(formatter.string(from: meal.date)),\(meal.mealType.rawValue),\"\(name)\",\(amounts.csvMealColumns(portion: item.portionText, grams: item.grams, nutrients: item.nutrients, method: item.method.rawValue))")
            }
        }
        lines.append("")
        lines.append("date,weight_kg")
        for weight in weights(in: context) {
            lines.append("\(formatter.string(from: weight.date)),\(weight.kg.oneDecimal)")
        }
        return lines.joined(separator: "\n")
    }
}
