import LooseweightKit
import SwiftUI

struct ReviewView: View {
    let image: UIImage
    @State var estimate: MealEstimate
    @Binding var mealType: MealType
    var onSave: (MealEstimate) -> Void
    var onRetake: () -> Void

    @State private var selected: UUID?
    @State private var showingSearch = false

    init(image: UIImage, estimate: MealEstimate, mealType: Binding<MealType>, onSave: @escaping (MealEstimate) -> Void, onRetake: @escaping () -> Void) {
        self.image = image
        _estimate = State(initialValue: estimate)
        _mealType = mealType
        self.onSave = onSave
        self.onRetake = onRetake
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    photo
                    totalCard
                    if let question = estimate.clarifyingQuestion {
                        GlassCard(tint: Theme.sky, padding: 14) {
                            Label(question, systemImage: "questionmark.bubble")
                                .font(.rounded(.footnote, weight: .medium))
                        }
                    }
                    VStack(spacing: 12) {
                        SectionTitle(text: "What's on the plate", systemImage: "fork.knife")
                        ForEach($estimate.items) { $item in
                            ItemCard(item: $item, isSelected: selected == item.id)
                                .onTapGesture { withAnimation(Theme.spring) { selected = selected == item.id ? nil : item.id } }
                        }
                        Button {
                            showingSearch = true
                        } label: {
                            Label("Add something the AI missed", systemImage: "plus")
                                .font(.rounded(.subheadline, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                    ForEach(estimate.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle").font(.rounded(.caption)).foregroundStyle(.secondary)
                    }
                    Text("Estimates, not medical advice. Tap an item to adjust it.")
                        .font(.rounded(.caption2))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .background { AmbientBackground() }
            .navigationTitle(estimate.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Retake", action: onRetake)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Meal", selection: $mealType) {
                            ForEach(MealType.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                        }
                    } label: {
                        Label(mealType.title, systemImage: mealType.systemImage)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onSave(estimate)
                } label: {
                    Label("Save to \(mealType.title) · \(Int(estimate.total.kcal.rounded())) kcal", systemImage: "checkmark")
                        .font(.rounded(.headline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .accessibilityIdentifier("saveMeal")
            }
            .sheet(isPresented: $showingSearch) {
                FoodSearchView { record, grams in
                    estimate.items.append(EstimatedItem(
                        name: record.name, grams: grams, gramsLow: grams, gramsHigh: grams, per100g: record.per100g,
                        food: FoodMatch(id: record.id, name: record.name, source: record.source), method: .userNote, confidence: 1
                    ))
                }
            }
        }
    }

    private var photo: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { proxy in
                    ForEach(estimate.items) { item in
                        if item.polygon.count >= 3 {
                            outline(item.polygon, in: proxy.size)
                                .stroke(selected == item.id ? Theme.sun : .white, style: StrokeStyle(lineWidth: selected == item.id ? 4 : 2, lineJoin: .round))
                                .shadow(color: .black.opacity(0.35), radius: 3)
                        }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: Theme.cardRadius))
            .frame(maxHeight: 340)
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

    private var totalCard: some View {
        let total = estimate.total
        let range = estimate.kcalRange
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(total.kcal.rounded()))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .monospacedDigit()
                        .accessibilityIdentifier("reviewTotal")
                    Text("kcal").font(.rounded(.title3, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("likely \(Int(range.lowerBound))–\(Int(range.upperBound))")
                            .font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            if estimate.usedDepth { Badge(text: "LiDAR", systemImage: "cube.transparent", color: Theme.teal) }
                            Badge(text: "\(Int(estimate.overallConfidence * 100))% sure", systemImage: "gauge.medium", color: Theme.confidenceColor(estimate.overallConfidence))
                        }
                    }
                }
                HStack(spacing: 12) {
                    macro("Protein", total.protein, Theme.protein)
                    macro("Carbs", total.carbs, Theme.carbs)
                    macro("Fat", total.fat, Theme.fat)
                }
            }
        }
        .animation(Theme.spring, value: total.kcal)
    }

    private func macro(_ title: String, _ grams: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.rounded(.caption, weight: .medium)).foregroundStyle(.secondary)
            Text(grams.gramsText).font(.rounded(.headline, weight: .bold)).foregroundStyle(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ItemCard: View {
    @Binding var item: EstimatedItem
    var isSelected: Bool

    var body: some View {
        GlassCard(tint: isSelected ? Theme.teal : nil, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.rounded(.headline, weight: .semibold))
                        HStack(spacing: 6) {
                            Badge(text: item.method.title, systemImage: methodIcon, color: item.method == .depthVolume ? Theme.teal : .secondary)
                            if item.flags.contains(.aiEstimate) { Badge(text: "AI estimate", systemImage: "sparkles", color: Theme.sun) }
                            if item.flags.contains(.checkMatch) { Badge(text: "Check", systemImage: "exclamationmark.triangle", color: Theme.coral) }
                            if item.flags.contains(.hiddenIngredient) { Badge(text: "Hidden", systemImage: "drop", color: Theme.sky) }
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(item.nutrients.kcal.rounded()))")
                            .font(.rounded(.title3, weight: .bold))
                            .contentTransition(.numericText())
                            .monospacedDigit()
                        Text("kcal").font(.rounded(.caption2)).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    Circle().fill(Theme.confidenceColor(item.confidence)).frame(width: 8, height: 8)
                    Text("\(Int(item.grams)) g")
                        .font(.rounded(.subheadline, weight: .semibold))
                        .monospacedDigit()
                    Text("range \(Int(item.gramsLow))–\(Int(item.gramsHigh)) g")
                        .font(.rounded(.caption))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let match = item.food {
                        Text(match.name).font(.rounded(.caption2)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                if isSelected {
                    VStack(spacing: 10) {
                        Slider(value: $item.grams, in: sliderRange, step: 1)
                            .tint(Theme.teal)
                        HStack {
                            ForEach([-25.0, -10.0, 10.0, 25.0], id: \.self) { delta in
                                Button(delta > 0 ? "+\(Int(delta)) g" : "\(Int(delta)) g") {
                                    item.grams = max(0, item.grams + delta)
                                }
                                .buttonStyle(.glass)
                                .font(.rounded(.caption, weight: .semibold))
                            }
                        }
                        if !item.notes.isEmpty {
                            Text(item.notes).font(.rounded(.caption)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .contentShape(.rect)
    }

    private var sliderRange: ClosedRange<Double> {
        let low = max(0, min(item.gramsLow, item.grams) * 0.5)
        let high = max(item.gramsHigh, item.grams) * 1.6 + 10
        return low...high
    }

    private var methodIcon: String {
        switch item.method {
        case .depthVolume: "cube.transparent"
        case .areaThickness: "square.dashed"
        case .visualEstimate: "eye"
        case .count: "number"
        case .label: "doc.text.viewfinder"
        case .userNote: "hand.point.up.left"
        }
    }
}
