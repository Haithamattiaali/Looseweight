import Charts
import LooseweightKit
import SwiftData
import SwiftUI

/// "Stacked plates": the weight trend, then the week as seven tiny plates.
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
        let targets = model.targets(maintenance: maintenance)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.xl) {
                    WeightHeader(trend: trend)
                    WeightChart(weights: weights, trend: trend, goal: model.profile?.goalWeightKg)
                        .padding(Theme.m)
                        .glassSurface()
                        .streamIn(0)
                    WeekPlates(meals: meals, target: targets?.kcal ?? 2_000)
                        .padding(Theme.m)
                        .glassSurface()
                        .streamIn(1)
                    stats(targets: targets)
                        .padding(.horizontal, Theme.m)
                        .glassSurface()
                        .streamIn(2)
                    explanation
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.xxl)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background { DaylightGround(mood: Theme.cyan) }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
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
                    .presentationDetents([.medium])
            }
        }
    }

    private func stats(targets: DailyTargets?) -> some View {
        let deficit = (targets?.maintenanceKcal ?? 0) - (targets?.kcal ?? 0)
        let days = trend.last.flatMap { current in
            model.profile.flatMap { EnergyModel.daysToGoal(currentKg: current.kg, goalKg: $0.goalWeightKg, dailyDeficitKcal: deficit) }
        }
        let goalDate = days.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: Date()) }
        return VStack(spacing: 0) {
            StatRow(title: "Daily target", value: targets.map { $0.kcal.kcalText } ?? "—")
            Hairline()
            StatRow(title: maintenance?.source == .blended ? "Your real burn" : "Estimated burn",
                    value: (maintenance?.kcal).map { "~" + $0.kcalText + " a day" } ?? "—")
            Hairline()
            StatRow(title: "Goal date", value: goalDate?.formatted(.dateTime.month(.abbreviated).day()) ?? "—")
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            LabelText("How your target adapts", color: Theme.violet)
            if let maintenance, maintenance.source == .blended {
                Text("From \(maintenance.loggedDays) logged days and your weight trend, you burn about \(Int(maintenance.kcal)) kcal a day. Your target follows this real number (\(Int(maintenance.dataWeight * 100))% based on your data).")
                    .font(.footnote).foregroundStyle(Theme.inkSecondary)
            } else {
                Text("For now the target uses a standard formula. After two weeks of logging meals and weight, it learns how much you really burn.")
                    .font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}

private struct StatRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title).font(.body).foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(value).font(.rounded(.body, weight: .bold)).monospacedDigit().foregroundStyle(Theme.cyan)
        }
        .padding(.vertical, Theme.s)
        .accessibilityElement(children: .combine)
    }
}

private struct WeightHeader: View {
    var trend: [TrendPoint]

    private var weekly: Double? { WeightTrend.slopeKgPerDay(trend).map { $0 * 7 } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.xs) {
                Text(trend.last.map { $0.kg.oneDecimal } ?? "—")
                    .font(.display)
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [Theme.ink, Theme.cyan], startPoint: .top, endPoint: .bottom))
                    .glow(Theme.cyan, radius: 18)
                LabelText("kg")
                if let weekly {
                    Text(String(format: "%@%.1f this week", weekly <= 0 ? "↓" : "↑", abs(weekly)))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(weekly <= 0 ? Theme.leaf : Theme.inkSecondary)
                }
            }
            LabelText("Trend weight")
        }
        .padding(.top, Theme.m)
        .accessibilityElement(children: .combine)
    }
}

private struct WeightChart: View {
    var weights: [WeightLog]
    var trend: [TrendPoint]
    var goal: Double?

    @State private var selectedDate: Date?

    private var yDomain: ClosedRange<Double> {
        let values = weights.map(\.kg) + [goal].compactMap { $0 }
        let low = (values.min() ?? 60) - 1, high = (values.max() ?? 90) + 1
        return low...high
    }

    private var selectedPoint: TrendPoint? {
        guard let selectedDate else { return nil }
        return trend.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        if weights.count >= 2 {
            chart
                .frame(height: 220)
                .overlay(alignment: .top) { readout }
                .accessibilityIdentifier("weightChart")
        } else {
            Text("Log your weight a few mornings a week. The trend line smooths out water swings.")
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(trend, id: \.date) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("Base", yDomain.lowerBound), yEnd: .value("Trend", point.kg))
                    .foregroundStyle(LinearGradient(colors: [Theme.cyan.opacity(0.45), Theme.violet.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(trend, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("Trend", point.kg))
                    .foregroundStyle(LinearGradient(colors: [Theme.magenta, Theme.cyan, Theme.leaf], startPoint: .leading, endPoint: .trailing))
                    .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(weights) { weight in
                PointMark(x: .value("Date", weight.date), y: .value("Weight", weight.kg))
                    .foregroundStyle(Theme.ink.opacity(0.35))
                    .symbolSize(24)
            }
            if let goal {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .foregroundStyle(Theme.hairline)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedDate)
    }

    @ViewBuilder
    private var readout: some View {
        if let selectedPoint {
            GlassPill {
                Text("\(selectedPoint.kg.oneDecimal) kg · \(selectedPoint.date.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .transition(.opacity)
        }
    }
}

/// The last seven days as tiny plates. Tap one to lift it up with that day's meals.
private struct WeekPlates: View {
    var meals: [MealLog]
    var target: Double

    @State private var selectedDay: Date?
    @Namespace private var plates

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private func meals(on day: Date) -> [MealLog] {
        meals.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private func kcal(on day: Date) -> Double {
        meals(on: day).map(\.total.kcal).reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.m) {
            LabelText("This week", color: Theme.leaf)
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    dayButton(day)
                }
            }
            if let selectedDay {
                DayDetail(day: selectedDay, meals: meals(on: selectedDay), kcal: kcal(on: selectedDay), target: target, namespace: plates)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Theme.settle, value: selectedDay)
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = selectedDay == day
        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 6) {
                if !isSelected {
                    PlateView(eaten: kcal(on: day), target: target, style: .compact)
                        .matchedGeometryEffect(id: day, in: plates)
                        .frame(width: 36, height: 36)
                } else {
                    Circle().fill(Theme.hairline).frame(width: 36, height: 36)
                }
                Text(day, format: .dateTime.weekday(.narrow))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Calendar.current.isDateInToday(day) ? Theme.ink : Theme.inkTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))), \(Int(kcal(on: day))) of \(Int(target)) kcal")
    }
}

private struct DayDetail: View {
    var day: Date
    var meals: [MealLog]
    var kcal: Double
    var target: Double
    var namespace: Namespace.ID

    var body: some View {
        VStack(spacing: Theme.m) {
            PlateView(eaten: kcal, target: target, style: .full)
                .matchedGeometryEffect(id: day, in: namespace)
                .frame(width: 160, height: 160)
            if meals.isEmpty {
                Text("Nothing logged").font(.footnote).foregroundStyle(Theme.inkTertiary)
            } else {
                VStack(spacing: Theme.xs) {
                    ForEach(meals) { meal in
                        MealRow(meal: meal)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WeightEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var whole: Int
    @State private var tenth: Int

    private var kg: Double { Double(whole) + Double(tenth) / 10 }

    init(initial: Double) {
        let rounded = (initial * 10).rounded() / 10
        _whole = State(initialValue: min(max(Int(rounded), 30), 350))
        _tenth = State(initialValue: Int(((rounded - Double(Int(rounded))) * 10).rounded()) % 10)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.m) {
                HStack(spacing: 0) {
                    Picker("Kilograms", selection: $whole) {
                        ForEach(30...350, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    Text(".").font(.display).foregroundStyle(Theme.ink)
                    Picker("Tenths", selection: $tenth) {
                        ForEach(0...9, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80)
                    LabelText("kg")
                }
                .font(.system(.title, design: .rounded, weight: .semibold))
                .frame(height: 160)
                Text("Weigh in the morning, after the bathroom, before eating.")
                    .font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
            .padding()
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
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
