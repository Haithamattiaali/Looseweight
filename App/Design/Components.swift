import SwiftUI

/// 6 pt confidence dot: leaf / honey / ember, with a VoiceOver word.
struct ConfidenceDot: View {
    var value: Double

    var body: some View {
        Circle()
            .fill(Theme.confidenceColor(value))
            .frame(width: 6, height: 6)
            .accessibilityLabel(Theme.confidenceWord(value))
    }
}

/// Capsule glass for guidance and small state. Falls back to a raised fill with Reduce Transparency.
struct GlassPill<Content: View>: View {
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .modifier(ControlGlass(tint: tint, shape: Capsule()))
    }
}

/// Glass for controls only; Reduce Transparency → raised ground + hairline.
struct ControlGlass<S: Shape>: ViewModifier {
    var tint: Color?
    var shape: S
    var interactive = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(Theme.groundRaised))
                .overlay(shape.stroke(Theme.hairline, lineWidth: 0.5))
        } else {
            content.glassEffect(glass, in: shape)
        }
    }

    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.35)) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Plain hairline, 0.5 pt.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5)
    }
}

/// Gentle press feedback for custom tappable rows.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.snap, value: configuration.isPressed)
    }
}
