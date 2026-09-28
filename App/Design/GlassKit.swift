import SwiftUI

/// A Liquid Glass card: content on the system glass material with a continuous-corner shape.
struct GlassCard<Content: View>: View {
    var tint: Color?
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: .rect(cornerRadius: Theme.cardRadius))
    }

    private var glass: Glass {
        if let tint { return .regular.tint(tint.opacity(0.18)) }
        return .regular
    }
}

struct SectionTitle: View {
    var text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage).foregroundStyle(.secondary) }
            Text(text).font(.rounded(.headline, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

/// Ring that fills with the day's energy; turns coral past the target.
struct CalorieRing: View {
    var eaten: Double
    var target: Double
    var lineWidth: CGFloat = 18

    private var progress: Double { target > 0 ? eaten / target : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(
                    AngularGradient(colors: progress > 1 ? [Theme.sun, Theme.coral] : [Theme.teal, Theme.mint, Theme.teal], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(Theme.spring, value: progress)
            VStack(spacing: 2) {
                Text("\(Int(abs(target - eaten).rounded()))")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .monospacedDigit()
                Text(eaten <= target ? "kcal left" : "kcal over")
                    .font(.rounded(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(eaten <= target ? "\(Int(target - eaten)) calories left today" : "\(Int(eaten - target)) calories over today")
    }
}

struct MacroBar: View {
    var title: String
    var value: Double
    var target: Double
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value.rounded()))/\(Int(target.rounded())) g").font(.rounded(.caption2)).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(color.gradient)
                        .frame(width: max(8, proxy.size.width * min(target > 0 ? value / target : 0, 1)))
                        .animation(Theme.spring, value: value)
                }
            }
            .frame(height: 8)
        }
    }
}

struct Badge: View {
    var text: String
    var systemImage: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.rounded(.caption2, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .glassEffect(.regular.tint(color.opacity(0.15)), in: .capsule)
    }
}

/// Gentle press feedback for custom tappable rows.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.spring, value: configuration.isPressed)
    }
}
