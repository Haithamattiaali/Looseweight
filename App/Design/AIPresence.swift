import SwiftUI

/// The AI's presence: a glowing orb that breathes while it looks and thinks. Calm when idle, bright when active.
struct AIOrb: View {
    var size: CGFloat = 120
    var isActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            OrbLayers(size: size, t: t, isActive: isActive)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct OrbLayers: View {
    let size: CGFloat
    let t: Double
    let isActive: Bool

    private var breath: CGFloat { 1 + CGFloat(sin(t * (isActive ? 2.4 : 1.2))) * (isActive ? 0.07 : 0.03) }

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: Theme.aiColors, center: .center, angle: .degrees(t * 40)))
                .blur(radius: size * 0.28)
                .scaleEffect(breath * 1.3)
                .opacity(isActive ? 0.95 : 0.55)
            Circle()
                .fill(AngularGradient(colors: Array(Theme.aiColors.reversed()), center: .center, angle: .degrees(-t * 70)))
                .scaleEffect(breath)
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.85), .white.opacity(0)], center: UnitPoint(x: 0.36, y: 0.3),
                                     startRadius: 0, endRadius: size * 0.42))
                .scaleEffect(breath)
                .blendMode(.plusLighter)
            Circle()
                .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                .scaleEffect(breath)
        }
        .frame(width: size, height: size)
    }
}

/// Soft sparks that rise and twinkle: the AI at work. Drawn in one Canvas; frozen with Reduce Motion.
struct SparkleField: View {
    var count = 28
    var color: Color = .white

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                for index in 0..<count {
                    let seed = Double(index) * 12.9898
                    let speed = 0.03 + (sin(seed) + 1) * 0.025
                    let x = (sin(seed * 3.1) + 1) / 2 * size.width
                    let rise = (t * speed + (cos(seed) + 1) / 2).truncatingRemainder(dividingBy: 1)
                    let y = size.height * (1 - rise)
                    let twinkle = (sin(t * 3 + seed) + 1) / 2
                    let radius = 1 + twinkle * 2.2
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    canvas.opacity = twinkle * (1 - abs(rise - 0.5) * 1.6)
                    canvas.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A band of light that sweeps across the content: "the AI is reading this".
struct Shimmer: ViewModifier {
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive && !reduceMotion {
            content.overlay {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.45)
                            .offset(x: -proxy.size.width * 0.5 + proxy.size.width * 1.5 * CGFloat(phase))
                            .blendMode(.plusLighter)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

/// Results stream in one by one: each row rises and un-blurs a moment after the one before.
struct StreamIn: ViewModifier {
    var index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0.01)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(Theme.settle.delay(Double(min(index, 10)) * 0.09)) { shown = true }
            }
    }
}

extension View {
    func shimmer(_ isActive: Bool = true) -> some View { modifier(Shimmer(isActive: isActive)) }
    func streamIn(_ index: Int) -> some View { modifier(StreamIn(index: index)) }

    /// A Liquid Glass surface floating over the colour ground, tinted by `tint`.
    func glassSurface(tint: Color? = nil, radius: CGFloat = Theme.controlRadius) -> some View {
        modifier(ControlGlass(tint: tint, shape: RoundedRectangle(cornerRadius: radius, style: .continuous)))
    }

    /// Soft coloured glow under vivid elements.
    func glow(_ color: Color, radius: CGFloat = 14) -> some View {
        shadow(color: color.opacity(0.55), radius: radius)
    }
}

/// A vivid dot with a halo: a food's own colour.
struct FoodDot: View {
    var color: Color
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .glow(color, radius: size * 0.8)
            .accessibilityHidden(true)
    }
}
