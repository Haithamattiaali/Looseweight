import LooseweightKit
import SwiftUI

/// "Plan": how much of each food in front of you to eat — in bites, sips, pieces or a share of the item.
struct PlanView: View {
    let image: UIImage
    /// The planner's suggestion; each slider marks it as a snap point.
    let suggested: MealPlan
    /// What is left today before this meal (the plan may use only this meal's share of it).
    let leftToday: Nutrients
    @Binding var mealType: MealType
    var onSave: (MealPlan) -> Void
    var onRetake: () -> Void

    @State private var plan: MealPlan
    @State private var appeared = false
    @State private var saved = false

    init(image: UIImage, plan: MealPlan, leftToday: Nutrients, mealType: Binding<MealType>,
         onSave: @escaping (MealPlan) -> Void, onRetake: @escaping () -> Void) {
        self.image = image
        suggested = plan
        self.leftToday = leftToday
        _mealType = mealType
        self.onSave = onSave
        self.onRetake = onRetake
        _plan = State(initialValue: plan)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.l) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: Theme.controlRadius, style: .continuous))
                        .frame(maxHeight: 280)
                        .accessibilityHidden(true)
                    PlanHeader(plan: plan, leftToday: leftToday, mealType: mealType)
                    PlanList(plan: $plan, suggested: suggested)
                    footnote
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.xxl)
            }
            .background { DaylightGround() }
            .navigationTitle(plan.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sensoryFeedback(.success, trigger: appeared)
            .onAppear { appeared = true }
        }
    }

    private var footnote: some View {
        Text("Estimates, not medical advice. Nothing counts until you confirm what you ate in the Inbox.")
            .font(.footnote)
            .foregroundStyle(Theme.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                onSave(plan)
            } label: {
                Label("Save plan", systemImage: "tray.and.arrow.down")
                    .labelStyle(.titleAndIcon)
                    .symbolEffect(.bounce, value: saved)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.leaf)
            .accessibilityLabel("Save plan to the Inbox")
            .accessibilityIdentifier("savePlan")
        }
    }
}

/// Hero: kcal the plan uses, this meal's budget and the one-line summary.
private struct PlanHeader: View {
    let plan: MealPlan
    let leftToday: Nutrients
    let mealType: MealType

    var body: some View {
        VStack(spacing: Theme.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Int(plan.total.kcal.rounded()), format: .number)
                    .font(.hero)
                    .tracking(-2)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: plan.total.kcal))
                    .accessibilityIdentifier("planTotal")
                LabelText("kcal")
            }
            Text("This \(mealType.title.lowercased()): up to \(Int(plan.remainingBefore.kcal.rounded())) · \(Int(leftToday.kcal.rounded())) left today")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            Text(plan.summary)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.xxs)
            BudgetFitBar(fit: BudgetFit(mealKcal: plan.total.kcal, leftBefore: leftToday.kcal))
                .padding(.top, Theme.xs)
            MealMacrosRow(total: plan.total)
                .padding(.top, Theme.xs)
        }
        .frame(maxWidth: .infinity)
        .animation(Theme.snap, value: plan.total.kcal)
    }
}

/// One row per food, each with a slider in its own unit ("3 pieces", "5 sips") and "= X kcal".
struct PlanList: View {
    @Binding var plan: MealPlan
    let suggested: MealPlan

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            ForEach($plan.portions) { $portion in
                PlanRow(portion: $portion, suggestedGrams: suggestedGrams(portion.id))
                Hairline()
            }
        }
        .accessibilityIdentifier("planList")
    }

    private func suggestedGrams(_ id: UUID) -> Double? {
        suggested.portions.first { $0.id == id }?.plannedGrams
    }
}

struct PlanRow: View {
    @Binding var portion: PlannedPortion
    var suggestedGrams: Double?
    @Environment(\.unitsMode) private var unitsMode

    private var instruction: String { AmountFormatter(mode: unitsMode).instruction(portion) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            header
            UnitSlider(name: portion.name, scale: portion.unitScale, grams: $portion.plannedGrams, suggestedGrams: suggestedGrams)
        }
        .padding(.vertical, Theme.s)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.s) {
            Circle()
                .fill(portion.isSkipped ? Theme.hairline : Theme.leaf)
                .frame(width: 8, height: 8)
            Text(portion.name)
                .font(.headline)
                .foregroundStyle(portion.isSkipped ? Theme.inkTertiary : Theme.ink)
            Spacer(minLength: Theme.xs)
            if let available = portion.availableText, !portion.isSkipped, !portion.isAll {
                Text(available)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(portion.name): \(instruction)")
    }
}
