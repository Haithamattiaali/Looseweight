import LooseweightKit
import SwiftUI

/// Onboarding over the living aurora: the AI orb glows behind a plate that gains colour with every step.
struct OnboardingView: View {
    var isEditing = false

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var sex: BiologicalSex = .female
    @State private var birthYear = Calendar.current.component(.year, from: Date()) - 35
    @State private var heightCm = 170.0
    @State private var weightKg = 80.0
    @State private var goalKg = 72.0
    @State private var activity: ActivityLevel = .light
    @State private var pace = 0.5

    private var draft: UserProfile {
        UserProfile(sex: sex, birthYear: birthYear, heightCm: heightCm, weightKg: weightKg, goalWeightKg: goalKg, activity: activity, weeklyLossKg: pace)
    }

    private var problems: [EnergyModel.ProfileProblem] { EnergyModel.validate(draft) }

    private static let moods: [Color] = [Theme.violet, Theme.cyan, Theme.magenta, Theme.honey, Theme.leaf]

    /// Welcome, how you count food, about you, goal, plan.
    private let lastPage = 4
    /// The plate drawing has four stages; the counting step keeps the welcome stage.
    private var plateStep: Int { max(page - 1, 0) }

    var body: some View {
        ZStack {
            DaylightGround(mood: Self.moods[min(page, Self.moods.count - 1)], energy: 0.6)
            VStack(spacing: Theme.l) {
                OnboardingPlate(step: plateStep, pace: pace)
                    .background { AIOrb(size: 150, isActive: page == 0).opacity(page == 0 ? 0.9 : 0.35) }
                    .frame(width: page == lastPage ? 140 : 120, height: page == lastPage ? 140 : 120)
                    .padding(.top, Theme.l)
                    .animation(Theme.settle, value: page)
                ScrollView {
                    stepContent
                        .padding(.horizontal, Theme.gutter)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                footer
            }
        }
        .sensoryFeedback(.selection, trigger: page)
        .onAppear(perform: loadExisting)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch page {
        case 0:
            WelcomeStep().transition(stepTransition)
        case 1:
            CountingStep().transition(stepTransition)
        case 2:
            AboutYouStep(sex: $sex, birthYear: $birthYear, heightCm: $heightCm, weightKg: $weightKg)
                .transition(stepTransition)
        case 3:
            GoalStep(goalKg: $goalKg, pace: $pace, activity: $activity, problems: problems)
                .transition(stepTransition)
        default:
            PlanStep(draft: draft)
                .transition(stepTransition)
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(insertion: .push(from: .trailing), removal: .push(from: .leading))
    }

    private var footer: some View {
        VStack(spacing: Theme.m) {
            PageDots(count: lastPage + 1, current: page)
            HStack(spacing: Theme.s) {
                if page > 0 {
                    Button("Back") { withAnimation(Theme.settle) { page -= 1 } }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                } else if isEditing {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
                Button {
                    if page < lastPage {
                        withAnimation(Theme.settle) { page += 1 }
                    } else {
                        model.profile = draft
                        if isEditing { dismiss() }
                    }
                } label: {
                    Text(page < lastPage ? "Continue" : (isEditing ? "Save" : "Start"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.leaf)
                .controlSize(.large)
                .glow(Theme.leaf, radius: 14)
                .disabled(page == 3 && !problems.isEmpty)
                .accessibilityIdentifier("onboardingContinue")
            }
        }
        .padding(.horizontal, Theme.l)
        .padding(.bottom, Theme.l)
    }

    private func loadExisting() {
        guard let profile = model.profile else { return }
        sex = profile.sex
        birthYear = profile.birthYear
        heightCm = profile.heightCm
        weightKg = profile.weightKg
        goalKg = profile.goalWeightKg
        activity = profile.activity
        pace = profile.weeklyLossKg
    }
}

// MARK: - The plate being drawn

private struct OnboardingPlate: View {
    var step: Int
    var pace: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    private var rimWidth: CGFloat { step >= 2 ? 4 + CGFloat(pace) * 8 : 5 }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: drawn)
                .stroke(AngularGradient(colors: Theme.aiColors, center: .center), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if step >= 1 {
                PlateRim(
                    macros: PlateView.Macros(protein: 1, carbs: 1, fat: 1, proteinTarget: 1, carbsTarget: 1, fatTarget: 1),
                    lineWidth: rimWidth
                )
                .padding(6)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            if step >= 3 {
                Circle()
                    .fill(LinearGradient(colors: [Theme.cyan.opacity(0.5), Theme.leaf.opacity(0.6)], startPoint: .bottom, endPoint: .top))
                    .padding(rimWidth + 14)
                    .glow(Theme.leaf, radius: 18)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(Theme.fill, value: step)
        .animation(Theme.settle, value: pace)
        .onAppear {
            if reduceMotion {
                drawn = 1
            } else {
                withAnimation(.easeInOut(duration: 1.2)) { drawn = 1 }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PageDots: View {
    var count: Int
    var current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(Theme.aiGradient) : AnyShapeStyle(Theme.hairline))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .animation(Theme.snap, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

// MARK: - Steps

/// How amounts read in the app: bites, sips, pieces, a share of the item, servings. No scale.
private struct CountingStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.l) {
            Text("Count food the way you eat it")
                .font(.screenTitle)
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: Theme.m) {
                row("fork.knife", "Bites", "Rice, pasta, salad: \"about 7 bites\".", Theme.honey)
                row("cup.and.saucer", "Sips", "Juice, milk, coffee: \"5 sips\".", Theme.cyan)
                row("wineglass", "Glasses, cans, mugs", "A whole drink: \"1 glass\", \"1 can\".", Theme.fat)
                row("circle.grid.2x2", "Pieces", "Nuggets, dates, cherry tomatoes: \"6 pieces\".", Theme.coral)
                row("chart.pie", "A share of it", "One chicken breast or sandwich: \"2/3 of the piece\".", Theme.magenta)
                row("square.stack", "Servings", "Packaged or searched food: \"1½ servings\".", Theme.leaf)
            }
            .padding(Theme.m)
            .glassSurface()
            Text("Protein, carbs and fat show as progress towards your day, not numbers to add up.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
        .accessibilityIdentifier("countingStep")
    }

    private func row(_ icon: String, _ title: String, _ example: String, _ color: Color) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                Text(example).font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(color).glow(color, radius: 6)
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.l) {
            Text("Lose weight by just taking a photo")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .tracking(-1.5)
                .foregroundStyle(LinearGradient(colors: [Theme.ink, Theme.cyan, Theme.magenta], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: Theme.m) {
                point("cube.transparent", "Your iPhone measures the food in 3D with its camera and LiDAR.", Theme.cyan)
                point("sparkles", "Claude AI names each food and drink and works out how much is there.", Theme.violet)
                point("checkmark.seal", "Calories come from the USDA food database, not from guesses.", Theme.leaf)
                point("chart.line.downtrend.xyaxis", "Your daily target learns how much you really burn.", Theme.magenta)
            }
        }
    }

    private func point(_ icon: String, _ text: String, _ color: Color) -> some View {
        Label {
            Text(text).font(.body.weight(.medium)).foregroundStyle(Theme.inkSecondary)
        } icon: {
            Image(systemName: icon).foregroundStyle(color).glow(color, radius: 6)
        }
    }
}

private struct AboutYouStep: View {
    @Binding var sex: BiologicalSex
    @Binding var birthYear: Int
    @Binding var heightCm: Double
    @Binding var weightKg: Double

    private static let years = Array((1925...2012).reversed())
    private static let heights = Array(stride(from: 120.0, through: 230.0, by: 1.0))
    private static let weights = Array(stride(from: 35.0, through: 300.0, by: 0.5))

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.l) {
            Text("About you")
                .font(.screenTitle)
                .foregroundStyle(Theme.ink)
            SexPicker(sex: $sex)
            HStack(spacing: 0) {
                wheel("Born", selection: $birthYear) {
                    ForEach(Self.years, id: \.self) { Text(String($0)).tag($0) }
                }
                wheel("Height cm", selection: $heightCm) {
                    ForEach(Self.heights, id: \.self) { Text("\(Int($0))").tag($0) }
                }
                wheel("Weight kg", selection: $weightKg) {
                    ForEach(Self.weights, id: \.self) { Text($0.oneDecimal).tag($0) }
                }
            }
        }
        .onAppear {
            heightCm = heightCm.rounded()
            weightKg = (weightKg * 2).rounded() / 2
        }
    }

    private func wheel<Value: Hashable, Content: View>(_ title: String, selection: Binding<Value>, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            LabelText(title)
            Picker(title, selection: selection, content: content)
                .pickerStyle(.wheel)
                .frame(height: 150)
                .clipped()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Two glass segments in one container; the selection moves between them.
private struct SexPicker: View {
    @Binding var sex: BiologicalSex
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: Theme.s) {
                segment("Female", .female)
                segment("Male", .male)
            }
        }
        .sensoryFeedback(.selection, trigger: sex)
    }

    private func segment(_ title: String, _ value: BiologicalSex) -> some View {
        let isOn = sex == value
        return Button {
            withAnimation(Theme.snap) { sex = value }
        } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(isOn ? Theme.ink : Theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(Theme.leaf.opacity(0.45)).interactive() : .regular.interactive(), in: .capsule)
        .glassEffectID(value == .female ? "female" : "male", in: glass)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct GoalStep: View {
    @Binding var goalKg: Double
    @Binding var pace: Double
    @Binding var activity: ActivityLevel
    var problems: [EnergyModel.ProfileProblem]

    private static let weights = Array(stride(from: 35.0, through: 300.0, by: 0.5))

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.l) {
            Text("Your goal")
                .font(.screenTitle)
                .foregroundStyle(Theme.ink)
            VStack(spacing: 0) {
                LabelText("Goal weight kg")
                Picker("Goal weight", selection: $goalKg) {
                    ForEach(Self.weights, id: \.self) { Text($0.oneDecimal).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 130)
                .clipped()
            }
            VStack(alignment: .leading, spacing: Theme.xs) {
                LabelText("Pace · kg per week")
                GlassEffectContainer(spacing: 20) {
                    HStack(spacing: Theme.xs) {
                        chip("Gentle 0.25", 0.25)
                        chip("Steady 0.5", 0.5)
                        chip("Faster 0.75", 0.75)
                    }
                }
            }
            HStack {
                LabelText("Activity")
                Spacer()
                Picker("Activity", selection: $activity) {
                    ForEach(ActivityLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            ForEach(problems, id: \.self) { problem in
                if case let .goalBelowHealthyWeight(minimum) = problem {
                    Label("For your height, the lowest healthy goal is \(minimum.oneDecimal) kg.", systemImage: "heart.text.square")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.ember)
                }
            }
        }
        .onAppear { goalKg = (goalKg * 2).rounded() / 2 }
        .sensoryFeedback(.selection, trigger: pace)
    }

    private func chip(_ title: String, _ value: Double) -> some View {
        let isOn = pace == value
        return Button {
            withAnimation(Theme.snap) { pace = value }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Theme.ink : Theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(Theme.leaf.opacity(0.45)).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct PlanStep: View {
    var draft: UserProfile
    @Environment(\.unitsMode) private var unitsMode

    @State private var shown = 0.0

    var body: some View {
        let targets = EnergyModel.targets(for: draft)
        let deficit = targets.maintenanceKcal - targets.kcal
        let days = EnergyModel.daysToGoal(currentKg: draft.weightKg, goalKg: draft.goalWeightKg, dailyDeficitKcal: deficit)
        VStack(alignment: .leading, spacing: Theme.l) {
            Text("Your daily plan")
                .font(.screenTitle)
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(shown))")
                    .font(.hero)
                    .tracking(-3)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(LinearGradient(colors: [Theme.ink, Theme.leaf], startPoint: .top, endPoint: .bottom))
                    .glow(Theme.leaf, radius: 20)
                    .contentTransition(.numericText(value: shown))
                    .accessibilityLabel("\(Int(targets.kcal)) kcal a day")
                    .accessibilityIdentifier("planTarget")
                LabelText("kcal a day")
            }
            HStack(spacing: Theme.l) {
                macro("Protein", targets.proteinG, 4, targets.kcal, Theme.protein)
                macro("Carbs", targets.carbsG, 4, targets.kcal, Theme.carbs)
                macro("Fat", targets.fatG, 9, targets.kcal, Theme.fat)
            }
            .padding(Theme.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
            Text("You burn about \(Int(targets.maintenanceKcal)) kcal a day." + (days.map { " At this pace you reach \(draft.goalWeightKg.oneDecimal) kg in about \(max($0 / 7, 1)) weeks." } ?? ""))
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
            ForEach(targets.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .onAppear {
            withAnimation(Theme.fill) { shown = targets.kcal.rounded(.down) }
        }
        .onChange(of: targets.kcal) { _, value in
            withAnimation(Theme.snap) { shown = value.rounded(.down) }
        }
    }

    private func macro(_ title: String, _ grams: Double, _ kcalPerGram: Double, _ dailyKcal: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LabelText(title, color: color)
            Text(AmountFormatter(mode: unitsMode).macroTarget(grams: grams, kcalPerGram: kcalPerGram, dailyKcal: dailyKcal))
                .font(.numeric)
                .foregroundStyle(color)
        }
    }
}
