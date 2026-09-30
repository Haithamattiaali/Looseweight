import LooseweightKit
import SwiftUI

private struct UnitsModeKey: EnvironmentKey {
    static let defaultValue: UnitsMode = .default
}

extension EnvironmentValues {
    /// The user's units mode, set once at the root from AppModel. Views build an `AmountFormatter` from it.
    var unitsMode: UnitsMode {
        get { self[UnitsModeKey.self] }
        set { self[UnitsModeKey.self] = newValue }
    }
}

/// One macro as a thin progress bar with plain words under it (never grams in Everyday).
struct MacroProgress: View {
    let title: String
    let fraction: Double
    let text: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            LabelText(title, color: color)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(color)
                        .frame(width: proxy.size.width * CGFloat(min(max(fraction, 0), 1)))
                }
            }
            .frame(width: 56, height: 4)
            Text(text)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(text)")
    }
}

/// Protein, carbs and fat of one meal as a share of the day's targets. Everyday: bars and "% of your day";
/// Precise adds grams. Used by Review and Plan.
struct MealMacrosRow: View {
    let total: Nutrients
    @Environment(AppModel.self) private var model
    @Environment(\.unitsMode) private var unitsMode

    var body: some View {
        let amounts = AmountFormatter(mode: unitsMode)
        let targets = model.targets
        HStack(alignment: .top, spacing: Theme.l) {
            cell("Protein", total.protein, targets?.proteinG, Theme.protein, amounts)
            cell("Carbs", total.carbs, targets?.carbsG, Theme.carbs, amounts)
            cell("Fat", total.fat, targets?.fatG, Theme.fat, amounts)
        }
    }

    private func cell(_ title: String, _ value: Double, _ target: Double?, _ color: Color, _ amounts: AmountFormatter) -> some View {
        MacroProgress(
            title: title,
            fraction: AmountFormatter.fraction(value, of: target ?? 0),
            text: amounts.macroShare(value, dailyTarget: target),
            color: color
        )
    }
}

/// Precise mode only: type the amount in grams.
struct GramEntryField: View {
    @Binding var grams: Double

    var body: some View {
        HStack {
            Text("Grams")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            TextField("Grams", value: $grams, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 90)
                .accessibilityIdentifier("gramEntry")
            Text("g")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

/// Today's protein, carbs and fat against their targets. Everyday: bars and "on track" words;
/// Precise adds "62 of 120 g".
struct DayMacrosRow: View {
    let macros: PlateView.Macros
    @Environment(\.unitsMode) private var unitsMode

    var body: some View {
        let amounts = AmountFormatter(mode: unitsMode)
        HStack(alignment: .top, spacing: Theme.l) {
            cell("Protein", macros.protein, macros.proteinTarget, Theme.protein, amounts)
            cell("Carbs", macros.carbs, macros.carbsTarget, Theme.carbs, amounts)
            cell("Fat", macros.fat, macros.fatTarget, Theme.fat, amounts)
        }
        .accessibilityIdentifier("dayMacros")
    }

    private func cell(_ title: String, _ value: Double, _ target: Double, _ color: Color, _ amounts: AmountFormatter) -> some View {
        MacroProgress(
            title: title,
            fraction: AmountFormatter.fraction(value, of: target),
            text: amounts.macroProgress(value, target: target),
            color: color
        )
    }
}
