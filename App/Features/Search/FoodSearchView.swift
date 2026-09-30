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
    @State private var recent: [PortionHint] = []

    init(onPick: ((FoodRecord, Double) -> Void)? = nil) {
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if query.count < 2 {
                        RecentChips(recent: recent) { query = $0 }
                            .padding(.bottom, Theme.m)
                        Text("Type to search \(FoodDatabase.shared.records.count) foods")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    ForEach(results) { record in
                        resultRow(record)
                        Hairline()
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.xl)
            }
            .background { DaylightGround() }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Food, e.g. basmati rice")
            .onChange(of: query) { _, text in
                results = text.count >= 2 ? FoodDatabase.shared.search(text, limit: 25).map(\.record) : []
                if let chosen, !results.contains(where: { $0.id == chosen.id }) { self.chosen = nil }
            }
            .onAppear { recent = Store.portionHints(in: context, limit: 8) }
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .buttonStyle(.glassProminent)
                        .tint(Theme.leaf)
                        .disabled(chosen == nil || grams <= 0)
                }
            }
        }
    }

    private func resultRow(_ record: FoodRecord) -> some View {
        let isChosen = chosen?.id == record.id
        return VStack(alignment: .leading, spacing: Theme.s) {
            Button {
                withAnimation(Theme.settle) {
                    chosen = isChosen ? nil : record
                    if !isChosen, let hint = recent.first(where: { $0.food == record.name }) { grams = hint.typicalGrams.rounded() }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.name).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                        Text(record.category).font(.caption).foregroundStyle(Theme.inkTertiary)
                    }
                    Spacer()
                    Text("\(Int(record.per100g.kcal)) kcal/100 g")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(PressableStyle())
            if isChosen {
                amountEditor(record)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, Theme.s)
        .scrollTransition { content, phase in
            content.opacity(phase.isIdentity ? 1 : 0.4)
        }
    }

    private func amountEditor(_ record: FoodRecord) -> some View {
        VStack(alignment: .leading, spacing: Theme.s) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Grams", value: $grams, format: .number)
                    .keyboardType(.decimalPad)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .frame(maxWidth: 120)
                Text("g").foregroundStyle(Theme.inkSecondary)
                Stepper("Grams", value: $grams, in: 0...5_000, step: 10).labelsHidden()
                Spacer()
                Text(record.per100g.amount(forGrams: grams).kcal.kcalText)
                    .font(.numeric)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            if onPick == nil {
                Picker("Meal", selection: $mealType) {
                    ForEach(MealType.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
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

/// Recently logged foods as glass chips; tap to search for one.
private struct RecentChips: View {
    var recent: [PortionHint]
    var onPick: (String) -> Void

    var body: some View {
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: Theme.xs) {
                LabelText("Recent")
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 20) {
                        HStack(spacing: Theme.xs) {
                            ForEach(recent, id: \.food) { hint in
                                Button(hint.food) { onPick(hint.food) }
                                    .buttonStyle(.glass)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, Theme.s)
        }
    }
}
