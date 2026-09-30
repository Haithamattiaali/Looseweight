import LooseweightKit
import SwiftData
import SwiftUI

struct TodayView: View {
    var onScan: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \MealLog.date, order: .reverse) private var allMeals: [MealLog]
    @State private var showingSearch = false
    @State private var scrollOffset: CGFloat = 0
    @State private var fillPulse = 0
    @State private var warnedOver = false

    private var todaysMeals: [MealLog] {
        allMeals.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var eaten: Nutrients { todaysMeals.map(\.total).sum() }
    private var target: Double { model.targets?.kcal ?? 2_000 }

    private var macros: PlateView.Macros {
        let targets = model.targets
        return PlateView.Macros(
            protein: eaten.protein, carbs: eaten.carbs, fat: eaten.fat,
            proteinTarget: targets?.proteinG ?? 120, carbsTarget: targets?.carbsG ?? 200, fatTarget: targets?.fatG ?? 65
        )
    }

    /// 0 at rest → 1 once the plate has scrolled away and docks in the toolbar.
    private var dock: CGFloat { min(max(scrollOffset / 260, 0), 1) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.xl) {
                    plateSection
                    if let problem = model.connectionProblem {
                        ConnectionPill(problem: problem)
                    }
                    if todaysMeals.isEmpty {
                        EmptyDay(onScan: onScan)
                    } else {
                        MealTimeline(meals: todaysMeals) { meal in
                            context.delete(meal)
                            try? context.save()
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.xxl)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scrollOffset = offset
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background { DaylightGround() }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showingSearch) {
                FoodSearchView()
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: todaysMeals.count) { old, new in
                if new > old { fillPulse += 1 }
            }
            .onChange(of: eaten.kcal > target) { _, over in
                if over { warnedOver = true }
            }
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: fillPulse)
            .sensoryFeedback(.warning, trigger: warnedOver) { old, new in !old && new }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            PlateView(eaten: eaten.kcal, target: target, macros: macros, style: .compact)
                .frame(width: 30, height: 30)
                .opacity(Double(dock))
                .accessibilityHidden(dock < 0.5)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Add food by search")
        }
    }

    private var plateSection: some View {
        let scale = 1 - 0.78 * dock
        return VStack(spacing: Theme.s) {
            PlateView(
                eaten: eaten.kcal,
                target: target,
                macros: macros,
                style: todaysMeals.isEmpty ? .outline : .full
            )
            .overlay {
                if todaysMeals.isEmpty {
                    EmptyPlateNumber(target: target)
                }
            }
            .frame(width: 300, height: 300)
            .scaleEffect(reduceMotion ? 1 : scale, anchor: .top)
            .opacity(reduceMotion ? 1 - Double(dock) : 1 - Double(dock) * 0.6)
            .accessibilityIdentifier("calorieRing")
            Text("\(Int(eaten.kcal.rounded())) eaten · \(Int(target.rounded())) target")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .contentTransition(.numericText(value: eaten.kcal))
        }
        .padding(.top, Theme.m)
        .animation(Theme.fill, value: eaten.kcal)
    }
}

/// Number shown inside an outline plate on an empty day.
private struct EmptyPlateNumber: View {
    var target: Double

    var body: some View {
        VStack(spacing: 2) {
            Text(Int(target.rounded()), format: .number)
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .tracking(-2)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            LabelText("kcal left")
        }
        .accessibilityHidden(true)
    }
}

private struct ConnectionPill: View {
    var problem: String

    var body: some View {
        GlassPill(tint: Theme.ember) {
            Label(problem, systemImage: "exclamationmark.circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.ink)
        }
        .accessibilityHint("Open Settings to connect the AI")
    }
}

private struct EmptyDay: View {
    var onScan: () -> Void

    var body: some View {
        VStack(spacing: Theme.s) {
            Text("Snap your first meal")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Hold the phone flat above the plate. The iPhone measures the food in 3D, then the AI names it and counts the calories.")
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            Button(action: onScan) {
                Label("Scan a meal", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.leaf)
            .controlSize(.large)
            .padding(.top, Theme.xs)
            .accessibilityIdentifier("scanFirstMeal")
        }
        .frame(maxWidth: .infinity)
    }
}

/// Meals grouped by type: a small label + time, then plain rows on the ground.
private struct MealTimeline: View {
    let meals: [MealLog]
    var onDelete: (MealLog) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Theme.l) {
            ForEach(MealType.allCases) { type in
                let group = meals.filter { $0.mealType == type }.sorted { $0.date < $1.date }
                if !group.isEmpty {
                    MealGroup(type: type, meals: group, onDelete: onDelete)
                }
            }
        }
    }
}

private struct MealGroup: View {
    let type: MealType
    let meals: [MealLog]
    var onDelete: (MealLog) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            HStack(spacing: Theme.xs) {
                LabelText(type.title)
                if let first = meals.first {
                    Text(first.date, format: .dateTime.hour().minute())
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            ForEach(meals) { meal in
                MealRow(meal: meal)
                    .scrollTransition { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.4)
                            .scaleEffect(phase.isIdentity ? 1 : 0.97)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            onDelete(meal)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                Hairline()
            }
        }
    }
}

struct MealRow: View {
    let meal: MealLog

    var body: some View {
        HStack(spacing: Theme.s) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(meal.items.map(\.name).joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.xs)
            Text(Int(meal.total.kcal.rounded()), format: .number)
                .font(.numeric)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(.vertical, Theme.xs)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = meal.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(.rect(cornerRadius: Theme.thumbRadius, style: .continuous))
            } else {
                Image(systemName: meal.mealType.systemImage)
                    .font(.title3)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 52, height: 52)
                    .background(Theme.hairline, in: .rect(cornerRadius: Theme.thumbRadius, style: .continuous))
            }
            if meal.usedDepth {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .padding(4)
                    .accessibilityLabel("Measured in 3D")
            }
        }
    }
}
