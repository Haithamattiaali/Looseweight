import LooseweightKit
import SwiftData
import SwiftUI

/// Manual add: search the food table, pick how many servings (Everyday: servings, pieces, bites; Precise adds grams).
struct FoodSearchView: View {
    var onPick: ((FoodRecord, Double) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.unitsMode) private var unitsMode
    @State private var query = ""
    @State private var results: [FoodRecord] = []
    @State private var chosen: FoodRecord?
    @State private var servings = 1.0
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
                        .disabled(chosen == nil || servings <= 0)
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
                    servings = 1
                    if !isChosen, let hint = recent.first(where: { $0.food == record.name }) {
                        servings = max(0.5, (hint.typicalGrams / Self.servingGrams(record) * 2).rounded() / 2)
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.name).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                        Text(categoryLine(record)).font(.caption).foregroundStyle(Theme.inkTertiary)
                    }
                    Spacer()
                    Text("\(Int(record.per100g.amount(forGrams: Self.servingGrams(record)).kcal.rounded())) kcal a serving")
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

    private func categoryLine(_ record: FoodRecord) -> String {
        guard let per100 = AmountFormatter(mode: unitsMode).kcalPer100g(record.per100g.kcal) else { return record.category }
        return "\(record.category) · \(per100)"
    }

    private func gramsBinding(_ record: FoodRecord) -> Binding<Double> {
        Binding(
            get: { servings * Self.servingGrams(record) },
            set: { servings = max($0, 1) / Self.servingGrams(record) }
        )
    }

    static func servingGrams(_ record: FoodRecord) -> Double {
        PortionSizes.servingGrams(name: record.name, category: record.category)
    }

    private func grams(for record: FoodRecord) -> Double {
        servings * Self.servingGrams(record)
    }

    private func amountEditor(_ record: FoodRecord) -> some View {
        let profile = PortionSizes.profile(name: record.name, category: record.category, grams: Self.servingGrams(record))
        return VStack(alignment: .leading, spacing: Theme.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AmountFormatter(mode: unitsMode).servings(servings, grams: grams(for: record)))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: servings))
                    if profile.unit != .whole {
                        Text(profile.describe(grams: grams(for: record)))
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                Stepper("Servings", value: $servings, in: 0.5...20, step: 0.5).labelsHidden()
                Spacer()
                Text(record.per100g.amount(forGrams: grams(for: record)).kcal.kcalText)
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

    static func servingsText(_ servings: Double) -> String {
        let whole = servings.rounded(.down)
        let half = servings - whole >= 0.5
        let number: String
        if whole == 0 { number = "½" } else { number = half ? "\(Int(whole))½" : "\(Int(whole))" }
        return "\(number) serving\(servings > 1 ? "s" : "")"
    }

    private func add() {
        guard let chosen, servings > 0 else { return }
        let amount = grams(for: chosen)
        if let onPick {
            onPick(chosen, amount)
        } else {
            let item = EstimatedItem(
                name: chosen.name, grams: amount, gramsLow: amount, gramsHigh: amount, per100g: chosen.per100g,
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
