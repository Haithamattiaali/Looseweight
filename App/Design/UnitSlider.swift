import LooseweightKit
import SwiftUI

/// A portion slider in the food's natural unit: "3 pieces", "5 sips", "Half the piece". Each step shows
/// "= X kcal" live, ticks with a haptic, and marks the AI's suggestion as a snap point. Grams stay internal
/// (Precise mode adds them to the label).
struct UnitSlider: View {
    let name: String
    let scale: UnitScale
    @Binding var grams: Double
    /// The AI's recommendation, shown as a marker; dragging near it snaps onto it.
    var suggestedGrams: Double?
    var tint: Color = Theme.leaf

    @Environment(\.unitsMode) private var unitsMode

    private var step: Int { scale.step(forGrams: grams) }
    private var suggestedStep: Int? { suggestedGrams.map { scale.step(forGrams: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            readout
            UnitTrack(scale: scale, step: step, suggestedStep: suggestedStep, tint: tint, onStep: set)
                .frame(height: 44)
            if let suggestedGrams, suggestedStep != nil {
                suggestion(suggestedGrams)
            }
        }
        .sensoryFeedback(.selection, trigger: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amount of \(name)")
        .accessibilityValue("\(scale.label(atStep: step, mode: unitsMode)), \(Int(scale.kcal(atStep: step).rounded())) kcal")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(step + 1)
            case .decrement: set(step - 1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("unitSlider")
    }

    private var readout: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(scale.label(atStep: step, mode: unitsMode))
                .font(.rounded(.title3, weight: .bold))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(value: Double(step)))
            Spacer(minLength: Theme.xs)
            Text(scale.kcalText(atStep: step))
                .font(.rounded(.title3, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText(value: scale.kcal(atStep: step)))
        }
        .animation(Theme.snap, value: step)
    }

    private func suggestion(_ suggested: Double) -> some View {
        Button {
            if let suggestedStep { set(suggestedStep) }
        } label: {
            Label(scale.suggestionText(grams: suggested, mode: unitsMode), systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(step == suggestedStep ? tint : Theme.inkSecondary)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("unitSliderSuggestion")
    }

    private func set(_ newStep: Int) {
        let clamped = scale.clamp(newStep)
        guard clamped != step || abs(scale.grams(atStep: clamped) - grams) > 0.01 else { return }
        withAnimation(Theme.snap) { grams = scale.grams(atStep: clamped) }
    }
}

/// The track: filled capsule, step ticks, the suggestion marker and a glass thumb. Drag or tap to move.
private struct UnitTrack: View {
    let scale: UnitScale
    let step: Int
    let suggestedStep: Int?
    let tint: Color
    var onStep: (Int) -> Void

    private let thumb: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - thumb, 1)
            let x = CGFloat(scale.position(ofStep: step)) * width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.hairline)
                    .frame(height: 10)
                    .padding(.horizontal, thumb / 2)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: x + thumb / 2 + 5, height: 10)
                    .padding(.leading, thumb / 2 - 5)
                ticks(width: width)
                marker(width: width)
                Circle()
                    .fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: tint.opacity(0.6), radius: 8)
                    .overlay(Circle().stroke(tint, lineWidth: 3))
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in onStep(target(for: value.location.x, width: width)) }
            )
        }
    }

    private func target(for location: CGFloat, width: CGFloat) -> Int {
        let raw = scale.step(atPosition: Double((location - thumb / 2) / width))
        // Magnetic snap onto the suggestion on long scales.
        if let suggestedStep, scale.lastStep > 12, abs(raw - suggestedStep) == 1 { return suggestedStep }
        return raw
    }

    @ViewBuilder
    private func ticks(width: CGFloat) -> some View {
        if scale.lastStep > 0, scale.lastStep <= 30 {
            ForEach(0...scale.lastStep, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Color.white.opacity(0.7) : Theme.inkTertiary)
                    .frame(width: 2, height: 6)
                    .offset(x: CGFloat(scale.position(ofStep: index)) * width + thumb / 2 - 1)
            }
        }
    }

    @ViewBuilder
    private func marker(width: CGFloat) -> some View {
        if let suggestedStep {
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 16, height: 16)
                .offset(x: CGFloat(scale.position(ofStep: suggestedStep)) * width + thumb / 2 - 8, y: -18)
                .accessibilityHidden(true)
        }
    }
}

/// "= 540 kcal this meal · 380 kcal left today after this", with a bar that fills toward what is left.
struct BudgetFitBar: View {
    let fit: BudgetFit
    var tint: Color = Theme.leaf

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule()
                        .fill(fit.isOver ? AnyShapeStyle(Theme.ember) : AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.6), tint], startPoint: .leading, endPoint: .trailing)))
                        .frame(width: proxy.size.width * CGFloat(min(fit.share.isFinite ? fit.share : 1, 1)))
                }
            }
            .frame(height: 8)
            Text(fit.text)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(fit.isOver ? Theme.ember : Theme.inkSecondary)
                .contentTransition(.numericText(value: fit.leftAfter))
                .accessibilityIdentifier("budgetFit")
        }
        .animation(Theme.snap, value: fit.mealKcal)
    }
}
