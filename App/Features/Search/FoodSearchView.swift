import LooseweightKit
import SwiftData
import SwiftUI

/// Manual add: search the food table, set grams (a kitchen scale is the most accurate tool there is).
struct FoodSearchView: View {
    var onPick: ((FoodRecord, Double) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var results: [FoodRecord] = []
    @State private var chosen: FoodRecord?
    @State private var grams = 100.0
    @State private var mealType = MealType.suggested()

    init(onPick: ((FoodRecord, Double) -> Void)? = nil) {
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            List {
                if let chosen {
                    Section("Amount") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(chosen.name).font(.rounded(.headline, weight: .semibold))
                            HStack {
                                TextField("Grams", value: $grams, format: .number)
                                    .keyboardType(.decimalPad)
                                    .font(.rounded(.title2, weight: .bold))
                                    .frame(maxWidth: 140)
                                Text("g").foregroundStyle(.secondary)
                                Spacer()
                                Text(chosen.per100g.amount(forGrams: grams).kcal.kcalText)
                                    .font(.rounded(.title3, weight: .bold))
                                    .foregroundStyle(Theme.teal)
                            }
                            if onPick == nil {
                                Picker("Meal", selection: $mealType) {
                                    ForEach(MealType.allCases) { Text($0.title).tag($0) }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }
                }
                Section(results.isEmpty ? "Type to search \(FoodDatabase.shared.records.count) foods" : "Results") {
                    ForEach(results) { record in
                        Button {
                            withAnimation(Theme.spring) { chosen = record }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.name).font(.rounded(.subheadline, weight: .medium)).foregroundStyle(.primary)
                                    Text(record.category).font(.rounded(.caption)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Int(record.per100g.kcal)) kcal/100 g")
                                    .font(.rounded(.caption, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground() }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Food, e.g. basmati rice")
            .onChange(of: query) { _, text in
                results = text.count >= 2 ? FoodDatabase.shared.search(text, limit: 25).map(\.record) : []
            }
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add).disabled(chosen == nil || grams <= 0)
                }
            }
        }
    }

    private func add() {
        guard let chosen, grams > 0 else { return }
        if let onPick {
            onPick(chosen, grams)
        } else {
            let item = EstimatedItem(
                name: chosen.name, grams: grams, gramsLow: grams, gramsHigh: grams, per100g: chosen.per100g,
                food: FoodMatch(id: chosen.id, name: chosen.name, source: chosen.source), method: .userNote, confidence: 1
            )
            let estimate = MealEstimate(title: chosen.name, items: [item], overallConfidence: 1, clarifyingQuestion: nil, warnings: [], modelID: nil, usedDepth: false)
            Store.save(estimate, mealType: mealType, photo: nil, source: "search", in: context)
        }
        dismiss()
    }
}
