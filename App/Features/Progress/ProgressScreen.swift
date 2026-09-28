import Charts
import LooseweightKit
import SwiftData
import SwiftUI

struct ProgressScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightLog.date) private var weights: [WeightLog]
    @Query(sort: \MealLog.date) private var meals: [MealLog]
    @State private var showingWeightEntry = false

    private var samples: [WeightSample] { weights.map { WeightSample(date: $0.date, kg: $0.kg) } }
    private var trend: [TrendPoint] { WeightTrend.smoothed(samples) }

    private var maintenance: MaintenanceEstimate? {
        guard let profile = model.profile else { return nil }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: meals) { calendar.startOfDay(for: $0.date) }
        let intakes = grouped.map { DailyIntake(day: $0.key, kcal: $0.value.map(\.total.kcal).reduce(0, +)) }
        return AdaptiveMaintenance.estimate(intakes: intakes, weights: samples, formulaKcal: EnergyModel.maintenance(for: profile))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    chartCard
                    statsGrid
                    explanation
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background { AmbientBackground() }
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingWeightEntry = true
                    } label: {
                        Label("Log weight", systemImage: "plus")
                    }
                    .accessibilityIdentifier("logWeight")
                }
            }
            .sheet(isPresented: $showingWeightEntry) {
                WeightEntrySheet(initial: weights.last?.kg ?? model.profile?.weightKg ?? 80)
                    .presentationDetents([.height(280)])
            }
        }
    }

    private var chartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trend weight").font(.rounded(.caption, weight: .medium)).foregroundStyle(.secondary)
                        Text(trend.last.map { "\($0.kg.oneDecimal) kg" } ?? "—")
                            .font(.rounded(.largeTitle, weight: .bold))
                            .monospacedDigit()
                    }
                    Spacer()
                    if let goal = model.profile?.goalWeightKg {
                        Badge(text: "Goal \(goal.oneDecimal) kg", systemImage: "flag.checkered", color: Theme.teal)
                    }
                }
                if weights.count >= 2 {
                    Chart {
                        ForEach(weights) { weight in
                            PointMark(x: .value("Date", weight.date), y: .value("Weight", weight.kg))
                                .foregroundStyle(Theme.teal.opacity(0.45))
                                .symbolSize(28)
                        }
                        ForEach(trend, id: \.date) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Trend", point.kg))
                                .foregroundStyle(Theme.teal.gradient)
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                .interpolationMethod(.catmullRom)
                        }
                        if let goal = model.profile?.goalWeightKg {
                            RuleMark(y: .value("Goal", goal))
                                .foregroundStyle(Theme.mint.opacity(0.7))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                        }
                    }
                    .chartYScale(domain: yDomain)
                    .frame(height: 220)
                    .accessibilityIdentifier("weightChart")
                } else {
                    Text("Log your weight a few mornings a week. The trend line smooths out water swings.")
                        .font(.rounded(.subheadline))
                        .foregroundStyle(.secondary)
                        .frame(height: 120)
                }
            }
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = weights.map(\.kg) + [model.profile?.goalWeightKg].compactMap { $0 }
        let low = (values.min() ?? 60) - 1, high = (values.max() ?? 90) + 1
        return low...high
    }

    private var statsGrid: some View {
        let weekly = WeightTrend.slopeKgPerDay(trend).map { $0 * 7 }
        let targets = model.targets(maintenance: maintenance)
        let deficit = (targets?.maintenanceKcal ?? 0) - (targets?.kcal ?? 0)
        let days = trend.last.flatMap { current in
            model.profile.flatMap { EnergyModel.daysToGoal(currentKg: current.kg, goalKg: $0.goalWeightKg, dailyDeficitKcal: deficit) }
        }
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                stat("This week", weekly.map { String(format: "%+.2f kg", $0) } ?? "—", "chart.line.downtrend.xyaxis")
                stat("Daily target", targets.map { $0.kcal.kcalText } ?? "—", "target")
            }
            GridRow {
                stat(maintenance?.source == .blended ? "Your real burn" : "Estimated burn",
                     (maintenance?.kcal).map { $0.kcalText } ?? "—", "flame")
                stat("Goal date", days.map { Calendar.current.date(byAdding: .day, value: $0, to: Date())?.formatted(.dateTime.month(.abbreviated).day()) ?? "—" } ?? "—", "flag.checkered")
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon).font(.rounded(.caption, weight: .medium)).foregroundStyle(.secondary)
                Text(value).font(.rounded(.title3, weight: .bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            }
        }
    }

    private var explanation: some View {
        GlassCard(tint: Theme.sky, padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("How your target adapts", systemImage: "wand.and.stars").font(.rounded(.subheadline, weight: .semibold))
                if let maintenance, maintenance.source == .blended {
                    Text("From \(maintenance.loggedDays) logged days and your weight trend, you burn about \(Int(maintenance.kcal)) kcal a day. Your target follows this real number (\(Int(maintenance.dataWeight * 100))% based on your data).")
                        .font(.rounded(.footnote)).foregroundStyle(.secondary)
                } else {
                    Text("For now the target uses a standard formula. After two weeks of logging meals and weight, it learns how much you really burn.")
                        .font(.rounded(.footnote)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct WeightEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var kg: Double

    init(initial: Double) {
        _kg = State(initialValue: (initial * 10).rounded() / 10)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("\(kg.oneDecimal) kg")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Stepper("Weight", value: $kg, in: 30...350, step: 0.1)
                    .labelsHidden()
                Text("Weigh in the morning, after the bathroom, before eating.")
                    .font(.rounded(.caption)).foregroundStyle(.secondary)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Store.logWeight(kg, in: context)
                        dismiss()
                    }
                }
            }
        }
    }
}
