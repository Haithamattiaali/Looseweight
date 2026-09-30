import LooseweightKit
import SwiftUI

/// "Slices": the photo with each food outlined, one hero total, and plain rows that expand in place.
struct ReviewView: View {
    let image: UIImage
    @State var estimate: MealEstimate
    /// What is left today before this meal, for the live "fits today" line.
    var leftToday: Nutrients?
    @Binding var mealType: MealType
    var onSave: (MealEstimate) -> Void
    var onRetake: () -> Void

    /// Each food's everyday unit, fixed from what the analysis saw (so "the piece" stays the same piece while editing).
    @State private var profiles: [UUID: PortionProfile]
    /// What the analysis saw, per item: the slider's suggestion marker.
    @State private var suggestions: [UUID: Double]
    @State private var selected: UUID?
    @State private var showingSearch = false
    @State private var appeared = false
    @State private var saved = false

    init(image: UIImage, estimate: MealEstimate, leftToday: Nutrients? = nil, mealType: Binding<MealType>,
         onSave: @escaping (MealEstimate) -> Void, onRetake: @escaping () -> Void) {
        self.image = image
        self.leftToday = leftToday
        _estimate = State(initialValue: estimate)
        _suggestions = State(initialValue: Dictionary(estimate.items.map { ($0.id, $0.grams) }, uniquingKeysWith: { first, _ in first }))
        _profiles = State(initialValue: Dictionary(estimate.items.map { ($0.id, $0.portionProfile) }, uniquingKeysWith: { first, _ in first }))
        _mealType = mealType
        self.onSave = onSave
        self.onRetake = onRetake
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.l) {
                    SlicedPhoto(image: image, items: estimate.items, selected: selected)
                    ReviewTotal(estimate: estimate)
                    if let leftToday {
                        BudgetFitBar(fit: BudgetFit(mealKcal: estimate.total.kcal, leftBefore: leftToday.kcal))
                    }
                    if let question = estimate.clarifyingQuestion {
                        Label(question, systemImage: "questionmark.bubble")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    itemList
                    footnotes
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.xxl)
            }
            .background { DaylightGround() }
            .navigationTitle(estimate.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showingSearch) {
                FoodSearchView { record, grams in
                    let item = EstimatedItem(
                        name: record.name, grams: grams, gramsLow: grams, gramsHigh: grams, per100g: record.per100g,
                        food: FoodMatch(id: record.id, name: record.name, source: record.source), method: .userNote, confidence: 1
                    )
                    profiles[item.id] = item.portionProfile
                    suggestions[item.id] = item.grams
                    estimate.items.append(item)
                }
                .presentationDetents([.medium, .large])
            }
            .sensoryFeedback(.success, trigger: appeared)
            .onAppear { appeared = true }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onRetake) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Retake")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Meal", selection: $mealType) {
                    ForEach(MealType.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
            } label: {
                Text(mealType.title)
            }
            .accessibilityLabel("Meal: \(mealType.title)")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(Theme.snap) { saved = true }
                onSave(estimate)
            } label: {
                Label("Save", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .symbolEffect(.bounce, value: saved)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.leaf)
            .accessibilityLabel("Save to \(mealType.title), \(Int(estimate.total.kcal.rounded())) kcal")
            .accessibilityIdentifier("saveMeal")
        }
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            Hairline()
            ForEach($estimate.items) { $item in
                ItemRow(item: $item, profile: profiles[item.id] ?? item.portionProfile, seenGrams: suggestions[item.id] ?? item.grams,
                        isSelected: selected == item.id) {
                    withAnimation(Theme.settle) { selected = selected == item.id ? nil : item.id }
                }
                Hairline()
            }
            Button {
                showingSearch = true
            } label: {
                Label("Add something the AI missed", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.leaf)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.m)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            ForEach(estimate.warnings, id: \.self) { warning in
                Label(warning, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Text("Estimates, not medical advice. Tap an item to adjust it.")
                .font(.footnote)
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hero total, likely range, confidence and macros — no card.
private struct ReviewTotal: View {
    let estimate: MealEstimate

    private var total: Nutrients { estimate.total }
    private var range: ClosedRange<Double> { estimate.kcalRange }

    var body: some View {
        VStack(spacing: Theme.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Int(total.kcal.rounded()), format: .number)
                    .font(.hero)
                    .tracking(-2)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: total.kcal))
                    .accessibilityIdentifier("reviewTotal")
                LabelText("kcal")
            }
            HStack(spacing: 6) {
                ConfidenceDot(value: estimate.overallConfidence)
                Text("likely \(Int(range.lowerBound))–\(Int(range.upperBound))")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                if estimate.usedDepth {
                    Image(systemName: "cube.transparent")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .accessibilityLabel("Measured in 3D")
                }
            }
            MealMacrosRow(total: total)
            .padding(.top, Theme.xs)
        }
        .frame(maxWidth: .infinity)
        .animation(Theme.snap, value: total.kcal)
    }
}

/// The photo with every food outlined. The selected slice brightens, the others dim.
private struct SlicedPhoto: View {
    let image: UIImage
    let items: [EstimatedItem]
    let selected: UUID?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { proxy in
                    ForEach(items) { item in
                        if item.polygon.count >= 3 {
                            slice(item, in: proxy.size)
                        }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: Theme.controlRadius, style: .continuous))
            .frame(maxHeight: 340)
            .animation(Theme.settle, value: selected)
            .accessibilityHidden(true)
    }

    private func slice(_ item: EstimatedItem, in size: CGSize) -> some View {
        let isSelected = selected == item.id
        let dimmed = selected != nil && !isSelected
        let path = outline(item.polygon, in: size)
        return ZStack {
            path.fill(Theme.leaf.opacity(isSelected ? 0.25 : 0))
            path.stroke(isSelected ? Theme.leaf : Color.white, style: StrokeStyle(lineWidth: isSelected ? 4 : 2, lineJoin: .round))
        }
        .opacity(dimmed ? 0.3 : 1)
        .shadow(color: .black.opacity(0.35), radius: 3)
    }

    /// Polygons are in the pixels of the image the model saw, which keeps the photo's aspect ratio.
    private func outline(_ points: [[Double]], in size: CGSize) -> Path {
        let referenceWidth = ImageTools.sizeForModel(width: Int(image.size.width), height: Int(image.size.height)).width
        let scale = size.width / max(referenceWidth, 1)
        var path = Path()
        for (index, point) in points.enumerated() where point.count >= 2 {
            let location = CGPoint(x: point[0] * scale, y: point[1] * scale)
            if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
        }
        path.closeSubpath()
        return path
    }
}

/// One food: confidence dot, name, amount in bites/sips/pieces, kcal. Tap expands the portion controls in place.
private struct ItemRow: View {
    @Binding var item: EstimatedItem
    var profile: PortionProfile
    var seenGrams: Double
    var isSelected: Bool
    var onTap: () -> Void
    @Environment(\.unitsMode) private var unitsMode

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s) {
            summary
                .contentShape(.rect)
                .onTapGesture(perform: onTap)
            if isSelected {
                PortionEditor(item: $item, profile: profile, seenGrams: seenGrams)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, Theme.s)
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: Theme.xs) {
            ConfidenceDot(value: item.confidence)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                if !flagText.isEmpty {
                    Text(flagText)
                        .font(.caption)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            Spacer(minLength: Theme.xs)
            Text(AmountFormatter(mode: unitsMode).amount(grams: item.grams, profile: profile))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
            Text(Int(item.nutrients.kcal.rounded()), format: .number)
                .font(.numeric)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(value: item.nutrients.kcal))
                .frame(minWidth: 48, alignment: .trailing)
        }
    }

    private var flagText: String {
        var parts = [item.method.title]
        if item.flags.contains(.aiEstimate) { parts.append("AI estimate") }
        if item.flags.contains(.checkMatch) { parts.append("Check the match") }
        if item.flags.contains(.hiddenIngredient) { parts.append("Hidden ingredient") }
        return parts.joined(separator: " · ")
    }
}

/// Slider over a tinted band that shows the likely range — the uncertainty stays visible. The amount reads in
/// bites, sips, pieces or a share of the item; grams stay internal.
private struct PortionEditor: View {
    @Binding var item: EstimatedItem
    var profile: PortionProfile
    var seenGrams: Double
    @Environment(\.unitsMode) private var unitsMode

    private var amounts: AmountFormatter { AmountFormatter(mode: unitsMode) }

    private var scale: UnitScale {
        UnitScale(profile: profile, per100g: item.per100g, availableGrams: max(seenGrams, item.gramsHigh), allowMore: true)
    }

    private var stepTitle: String { profile.stepTitle }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s) {
            UnitSlider(name: item.name, scale: scale, grams: $item.grams, suggestedGrams: seenGrams)
            HStack {
                Text(amounts.range(low: item.gramsLow, high: item.gramsHigh, profile: profile))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                if let match = item.food {
                    Text(match.name)
                        .font(.caption)
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                }
            }
            stepButtons
            if unitsMode.showsGrams {
                GramEntryField(grams: $item.grams)
            }
            if !item.notes.isEmpty {
                Text(item.notes)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var stepButtons: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: Theme.xs) {
                Button("− \(stepTitle)") {
                    withAnimation(Theme.snap) { item.grams = max(0, item.grams - profile.stepGrams) }
                }
                .buttonStyle(.glass)
                .accessibilityLabel("One \(profile.unit == .whole ? "quarter" : profile.noun(for: 1)) less")
                Button("+ \(stepTitle)") {
                    withAnimation(Theme.snap) { item.grams += profile.stepGrams }
                }
                .buttonStyle(.glass)
                .accessibilityLabel("One \(profile.unit == .whole ? "quarter" : profile.noun(for: 1)) more")
                if profile.unit != .whole {
                    Button("Half") {
                        withAnimation(Theme.snap) { item.grams = (item.grams / 2).rounded() }
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Half of it")
                }
            }
            .font(.caption.weight(.semibold))
        }
    }
}
