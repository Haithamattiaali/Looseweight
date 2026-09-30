import LooseweightKit
import SwiftUI

/// "Plan": how much of each food in front of you to eat — in bites, sips, pieces or a share of the item.
struct PlanView: View {
    let image: UIImage
    let plan: MealPlan
    /// What is left today before this meal (the plan may use only this meal's share of it).
    let leftToday: Nutrients
    @Binding var mealType: MealType
    var onSave: () -> Void
    var onRetake: () -> Void

    @State private var appeared = false
    @State private var saved = false

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
                    PlanList(portions: plan.portions)
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
                onSave()
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
            HStack(spacing: Theme.l) {
                macro("Protein", plan.total.protein, Theme.protein)
                macro("Carbs", plan.total.carbs, Theme.carbs)
                macro("Fat", plan.total.fat, Theme.fat)
            }
            .padding(.top, Theme.xs)
        }
        .frame(maxWidth: .infinity)
    }

    private func macro(_ title: String, _ grams: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            LabelText(title, color: color)
            Text(grams.gramsText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
    }
}

/// One plain row per food: name on the left, the instruction ("6 bites", "Skip") large on the right.
struct PlanList: View {
    let portions: [PlannedPortion]

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            ForEach(portions) { portion in
                PlanRow(portion: portion)
                Hairline()
            }
        }
        .accessibilityIdentifier("planList")
    }
}

struct PlanRow: View {
    let portion: PlannedPortion

    var body: some View {
        HStack(alignment: .center, spacing: Theme.s) {
            Circle()
                .fill(portion.isSkipped ? Theme.hairline : Theme.leaf)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(portion.name)
                    .font(.headline)
                    .foregroundStyle(portion.isSkipped ? Theme.inkTertiary : Theme.ink)
                if !portion.isSkipped {
                    Text("\(Int(portion.nutrients.kcal.rounded())) kcal")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            Spacer(minLength: Theme.xs)
            VStack(alignment: .trailing, spacing: 2) {
                Text(portion.instruction)
                    .font(.numeric)
                    .foregroundStyle(portion.isSkipped ? Theme.inkTertiary : Theme.ink)
                    .multilineTextAlignment(.trailing)
                if let available = portion.availableText, !portion.isSkipped, !portion.isAll {
                    Text(available)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .padding(.vertical, Theme.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(portion.name): \(portion.instruction)")
    }
}
