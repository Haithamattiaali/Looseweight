import LooseweightKit
import SwiftData
import SwiftUI

struct TodayView: View {
    var onScan: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \MealLog.date, order: .reverse) private var allMeals: [MealLog]
    @State private var showingSearch = false

    private var todaysMeals: [MealLog] {
        allMeals.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var eaten: Nutrients { todaysMeals.map(\.total).sum() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    summaryCard
                    if let problem = model.connectionProblem {
                        GlassCard(tint: Theme.sun, padding: 16) {
                            Label(problem, systemImage: "sparkles")
                                .font(.rounded(.footnote, weight: .medium))
                        }
                    }
                    mealsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background { AmbientBackground() }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Add food by search")
                }
            }
            .sheet(isPresented: $showingSearch) {
                FoodSearchView()
                    .presentationDetents([.large])
            }
        }
    }

    private var summaryCard: some View {
        let targets = model.targets
        let target = targets?.kcal ?? 2_000
        return GlassCard {
            VStack(spacing: 22) {
                HStack(alignment: .center, spacing: 24) {
                    CalorieRing(eaten: eaten.kcal, target: target)
                        .frame(width: 170, height: 170)
                        .accessibilityIdentifier("calorieRing")
                    VStack(alignment: .leading, spacing: 14) {
                        stat("Eaten", value: eaten.kcal.kcalText, color: Theme.teal)
                        stat("Target", value: target.kcalText, color: .secondary)
                        if let maintenance = targets?.maintenanceKcal {
                            stat("Burn", value: maintenance.kcalText, color: .secondary)
                        }
                    }
                }
                VStack(spacing: 12) {
                    MacroBar(title: "Protein", value: eaten.protein, target: targets?.proteinG ?? 120, color: Theme.protein)
                    MacroBar(title: "Carbs", value: eaten.carbs, target: targets?.carbsG ?? 200, color: Theme.carbs)
                    MacroBar(title: "Fat", value: eaten.fat, target: targets?.fatG ?? 65, color: Theme.fat)
                }
            }
        }
    }

    private func stat(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.rounded(.caption, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.rounded(.title3, weight: .bold)).foregroundStyle(color).monospacedDigit()
        }
    }

    @ViewBuilder
    private var mealsSection: some View {
        if todaysMeals.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "camera.macro")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Theme.teal)
                    Text("Snap your first meal")
                        .font(.rounded(.title3, weight: .bold))
                    Text("Hold the phone flat above the plate. The iPhone measures the food in 3D, then the AI names it and counts the calories.")
                        .font(.rounded(.subheadline))
                        .foregroundStyle(.secondary)
                    Button(action: onScan) {
                        Label("Scan a meal", systemImage: "camera.viewfinder")
                            .font(.rounded(.body, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("scanFirstMeal")
                }
            }
        } else {
            VStack(spacing: 12) {
                SectionTitle(text: "Meals", systemImage: "fork.knife")
                ForEach(MealType.allCases) { type in
                    let meals = todaysMeals.filter { $0.mealType == type }.sorted { $0.date < $1.date }
                    ForEach(meals) { meal in
                        MealRow(meal: meal)
                            .contextMenu {
                                Button(role: .destructive) {
                                    context.delete(meal)
                                    try? context.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
    }
}

struct MealRow: View {
    let meal: MealLog

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 14) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: meal.mealType.systemImage).foregroundStyle(Theme.teal)
                        Text(meal.mealType.title).font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary)
                        if meal.usedDepth {
                            Badge(text: "LiDAR", systemImage: "cube.transparent", color: Theme.teal)
                        }
                    }
                    Text(meal.title).font(.rounded(.headline, weight: .semibold)).lineLimit(2)
                    Text(meal.items.map(\.name).joined(separator: ", "))
                        .font(.rounded(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(meal.total.kcal.rounded()))")
                        .font(.rounded(.title3, weight: .bold))
                        .monospacedDigit()
                    Text("kcal").font(.rounded(.caption2)).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = meal.photo, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 58)
                .clipShape(.rect(cornerRadius: 16))
        } else {
            Image(systemName: meal.mealType.systemImage)
                .font(.title2)
                .foregroundStyle(Theme.teal)
                .frame(width: 58, height: 58)
                .glassEffect(.regular.tint(Theme.teal.opacity(0.15)), in: .rect(cornerRadius: 16))
        }
    }
}
