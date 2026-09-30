import LooseweightKit
import SwiftData
import SwiftUI

/// Planned meals wait here until the person says what happened. Only confirmed amounts count toward today.
struct InboxView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlannedMealRecord.createdAt, order: .reverse) private var records: [PlannedMealRecord]
    @State private var confirmedPulse = 0

    private var pending: [PlannedMealRecord] { records.filter(\.isPending) }
    private var recent: [PlannedMealRecord] {
        records.filter { !$0.isPending && Calendar.current.isDateInToday($0.confirmedAt ?? $0.createdAt) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.xl) {
                    if pending.isEmpty {
                        EmptyInbox()
                    } else {
                        VStack(alignment: .leading, spacing: Theme.l) {
                            LabelText("To confirm", color: Theme.violet)
                            ForEach(Array(pending.enumerated()), id: \.element.id) { index, record in
                                PlannedMealCard(record: record) { confirmation in
                                    withAnimation(Theme.settle) {
                                        Store.confirm(record, as: confirmation, in: context)
                                        confirmedPulse += 1
                                    }
                                }
                                .streamIn(index)
                            }
                        }
                    }
                    if !recent.isEmpty {
                        ConfirmedToday(records: recent)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.xxl)
                .padding(.top, Theme.m)
            }
            .background { DaylightGround(mood: Theme.violet) }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.success, trigger: confirmedPulse)
            .accessibilityIdentifier("inbox")
        }
    }
}

private struct EmptyInbox: View {
    var body: some View {
        VStack(spacing: Theme.s) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.aiGradient)
                .glow(Theme.violet, radius: 16)
            Text("Nothing to confirm")
                .font(.screenTitle)
                .foregroundStyle(Theme.ink)
            Text("Take a photo before you eat and choose Plan. The app tells you how many bites of each food fit today, and the plan waits here until you confirm what you ate.")
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.l)
        .frame(maxWidth: .infinity)
        .glassSurface()
        .padding(.top, Theme.xl)
    }
}

/// One planned meal: photo, what the plan said, and the three answers.
struct PlannedMealCard: View {
    let record: PlannedMealRecord
    var onConfirm: (PlanConfirmation) -> Void

    @State private var choosingPart = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s) {
            header
            if let plan = record.planned?.plan {
                PlanSummaryLines(portions: plan.portions)
            }
            ConfirmButtons(choosingPart: $choosingPart, onConfirm: onConfirm)
        }
        .padding(Theme.m)
        .glassSurface(tint: Theme.violet)
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.aiGradient, lineWidth: 1).opacity(0.6))
    }

    private var header: some View {
        HStack(spacing: Theme.s) {
            PlanThumbnail(photo: record.photo, mealType: record.mealType)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.rounded(.headline, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    LabelText(record.mealType.title)
                    Text(record.createdAt, format: .dateTime.hour().minute())
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            Spacer(minLength: Theme.xs)
            if let total = record.planned?.plan.total.kcal {
                Text(Int(total.rounded()), format: .number)
                    .font(.numeric)
                    .monospacedDigit()
                    .foregroundStyle(Theme.violet)
                    .accessibilityLabel("\(Int(total.rounded())) kcal planned")
            }
        }
    }
}

/// "Rice · 6 bites" lines for the foods the plan kept.
private struct PlanSummaryLines: View {
    let portions: [PlannedPortion]
    @Environment(\.unitsMode) private var unitsMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(portions) { portion in
                HStack(spacing: 6) {
                    FoodDot(color: portion.isSkipped ? Theme.hairline : Theme.foodColor(for: portion.name, isDrink: portion.profile.isDrink), size: 6)
                    Text(portion.name)
                        .foregroundStyle(portion.isSkipped ? Theme.inkTertiary : Theme.inkSecondary)
                    Spacer()
                    Text(AmountFormatter(mode: unitsMode).instruction(portion))
                        .fontWeight(.semibold)
                        .foregroundStyle(portion.isSkipped ? Theme.inkTertiary : Theme.ink)
                }
                .font(.footnote)
            }
        }
    }
}

/// Ate it all as planned / Ate part (quick fraction chips) / Didn't eat.
struct ConfirmButtons: View {
    @Binding var choosingPart: Bool
    var onConfirm: (PlanConfirmation) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(alignment: .leading, spacing: Theme.xs) {
                if choosingPart {
                    partChips
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    mainChoices
                        .transition(.opacity)
                }
            }
        }
        .animation(Theme.settle, value: choosingPart)
    }

    private var mainChoices: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.xs) { choiceButtons }
            VStack(alignment: .leading, spacing: Theme.xs) { choiceButtons }
        }
    }

    @ViewBuilder
    private var choiceButtons: some View {
        Button {
            onConfirm(.ateAsPlanned)
        } label: {
            Label("Ate it all", systemImage: "checkmark")
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.leaf)
        .glow(Theme.leaf, radius: 10)
        .accessibilityLabel("Ate it all as planned")
        .accessibilityIdentifier("confirmAteAll")

        Button("Ate part") { choosingPart = true }
            .buttonStyle(.glass)
            .accessibilityIdentifier("confirmAtePart")

        Button("Didn't eat") { onConfirm(.didNotEat) }
            .buttonStyle(.glass)
            .accessibilityIdentifier("confirmDidNotEat")
    }

    private var partChips: some View {
        HStack(spacing: Theme.xs) {
            Text("How much?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
            ForEach(0..<PlanConfirmation.partChoices.count, id: \.self) { index in
                let choice = PlanConfirmation.partChoices[index]
                Button(choice.title) { onConfirm(.atePart(choice.value)) }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Ate \(choice.title) of the plan")
            }
            Button {
                choosingPart = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Back")
        }
        .font(.subheadline.weight(.semibold))
    }
}

struct PlanThumbnail: View {
    let photo: Data?
    let mealType: MealType

    var body: some View {
        Group {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: mealType.systemImage)
                    .font(.title3)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.hairline)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(.rect(cornerRadius: Theme.thumbRadius, style: .continuous))
    }
}

/// Today's answered plans, quietly listed.
private struct ConfirmedToday: View {
    let records: [PlannedMealRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            LabelText("Answered today", color: Theme.leaf)
            ForEach(records) { record in
                HStack {
                    Text(record.title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(record.planned?.confirmation.title ?? "")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.vertical, 6)
                Hairline()
            }
        }
        .padding(Theme.m)
        .glassSurface()
    }
}

/// The gentle reminder: one planned meal, the same three answers, shown once when the app opens.
struct PlanReminderSheet: View {
    let record: PlannedMealRecord
    var onConfirm: (PlanConfirmation) -> Void
    var onLater: () -> Void

    @State private var choosingPart = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.m) {
            Text("Did you eat your \(record.mealType.title.lowercased())?")
                .font(.rounded(.title2, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Your plan only counts once you confirm it.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
            HStack(spacing: Theme.s) {
                PlanThumbnail(photo: record.photo, mealType: record.mealType)
                Text(record.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
            }
            ConfirmButtons(choosingPart: $choosingPart, onConfirm: onConfirm)
            Button("Later", action: onLater)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(Theme.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { DaylightGround(mood: Theme.violet) }
    }
}
