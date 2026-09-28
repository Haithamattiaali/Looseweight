import LooseweightKit
import SwiftUI

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

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 20) {
                ProgressView(value: Double(page + 1), total: 4)
                    .tint(Theme.teal)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                TabView(selection: $page) {
                    welcome.tag(0)
                    aboutYou.tag(1)
                    goal.tag(2)
                    plan.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(Theme.spring, value: page)
                footer
            }
        }
        .onAppear(perform: loadExisting)
    }

    private var welcome: some View {
        card {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "camera.macro.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.teal.gradient)
                Text("Lose weight by just taking a photo")
                    .font(.rounded(.largeTitle, weight: .bold))
                VStack(alignment: .leading, spacing: 12) {
                    point("cube.transparent", "Your iPhone measures the food in 3D with its camera and LiDAR.")
                    point("sparkles", "Claude AI names each food and weighs it from those measurements.")
                    point("checkmark.seal", "Calories come from the USDA food database, not from guesses.")
                    point("chart.line.downtrend.xyaxis", "Your daily target learns how much you really burn.")
                }
            }
        }
    }

    private var aboutYou: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                Text("About you").font(.rounded(.title, weight: .bold))
                Picker("Sex", selection: $sex) {
                    Text("Female").tag(BiologicalSex.female)
                    Text("Male").tag(BiologicalSex.male)
                }
                .pickerStyle(.segmented)
                numberRow("Birth year", value: Binding(get: { Double(birthYear) }, set: { birthYear = Int($0) }), range: 1925...2012, step: 1, unit: "", digits: 0)
                numberRow("Height", value: $heightCm, range: 120...230, step: 1, unit: "cm", digits: 0)
                numberRow("Weight", value: $weightKg, range: 35...300, step: 0.5, unit: "kg", digits: 1)
            }
        }
    }

    private var goal: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your goal").font(.rounded(.title, weight: .bold))
                numberRow("Goal weight", value: $goalKg, range: 35...300, step: 0.5, unit: "kg", digits: 1)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pace").font(.rounded(.subheadline, weight: .semibold))
                    Picker("Pace", selection: $pace) {
                        Text("Gentle 0.25").tag(0.25)
                        Text("Steady 0.5").tag(0.5)
                        Text("Faster 0.75").tag(0.75)
                    }
                    .pickerStyle(.segmented)
                    Text("kg per week").font(.rounded(.caption)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity").font(.rounded(.subheadline, weight: .semibold))
                    Picker("Activity", selection: $activity) {
                        ForEach(ActivityLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                ForEach(problems, id: \.self) { problem in
                    if case let .goalBelowHealthyWeight(minimum) = problem {
                        Label("For your height, the lowest healthy goal is \(minimum.oneDecimal) kg.", systemImage: "heart.text.square")
                            .font(.rounded(.footnote, weight: .medium))
                            .foregroundStyle(Theme.coral)
                    }
                }
            }
        }
    }

    private var plan: some View {
        let targets = EnergyModel.targets(for: draft)
        let deficit = targets.maintenanceKcal - targets.kcal
        let days = EnergyModel.daysToGoal(currentKg: weightKg, goalKg: goalKg, dailyDeficitKcal: deficit)
        return card {
            VStack(alignment: .leading, spacing: 18) {
                Text("Your daily plan").font(.rounded(.title, weight: .bold))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(targets.kcal))")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.teal)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("planTarget")
                    Text("kcal a day").font(.rounded(.title3, weight: .semibold)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    macro("Protein", targets.proteinG, Theme.protein)
                    macro("Carbs", targets.carbsG, Theme.carbs)
                    macro("Fat", targets.fatG, Theme.fat)
                }
                Text("You burn about \(Int(targets.maintenanceKcal)) kcal a day." + (days.map { " At this pace you reach \(goalKg.oneDecimal) kg in about \(max($0 / 7, 1)) weeks." } ?? ""))
                    .font(.rounded(.subheadline))
                    .foregroundStyle(.secondary)
                ForEach(targets.notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle").font(.rounded(.footnote)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button("Back") { withAnimation(Theme.spring) { page -= 1 } }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            } else if isEditing {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
            Button {
                if page < 3 {
                    withAnimation(Theme.spring) { page += 1 }
                } else {
                    model.profile = draft
                    if isEditing { dismiss() }
                }
            } label: {
                Text(page < 3 ? "Continue" : (isEditing ? "Save" : "Start"))
                    .font(.rounded(.headline, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(page == 2 && !problems.isEmpty)
            .accessibilityIdentifier("onboardingContinue")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            GlassCard(padding: 24) { content() }
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.rounded(.body))
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.teal)
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String, digits: Int) -> some View {
        HStack {
            Text(title).font(.rounded(.subheadline, weight: .semibold))
            Spacer()
            Text(String(format: "%.\(digits)f", value.wrappedValue) + (unit.isEmpty ? "" : " \(unit)"))
                .font(.rounded(.title3, weight: .bold))
                .monospacedDigit()
            Stepper(title, value: value, in: range, step: step)
                .labelsHidden()
        }
    }

    private func macro(_ title: String, _ grams: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.rounded(.caption, weight: .medium)).foregroundStyle(.secondary)
            Text("\(Int(grams)) g").font(.rounded(.headline, weight: .bold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular.tint(color.opacity(0.12)), in: .rect(cornerRadius: 16))
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
