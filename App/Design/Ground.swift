import SwiftUI

/// The "Aurora" ground behind every screen: a dark base with a living 3×3 mesh of saturated colour that drifts
/// slowly and shifts with the time of day (warm dawn, clear cyan noon, magenta dusk, violet night). A `mood`
/// colour (the meal's lead food, or the AI while it works) pulls one corner toward it. Reduce Motion freezes it.
struct DaylightGround: View {
    var mood: Color?
    /// 0 = calm (Today, Settings); 1 = alive (Scan, Analysis).
    var energy: Double = 0.35

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hour = Calendar.current.component(.hour, from: Date())

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion || scenePhase != .active)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Theme.ground
                MeshGradient(width: 3, height: 3, points: points(t), colors: colors)
                    .opacity(colorScheme == .dark ? 0.9 : 0.55)
                LinearGradient(colors: [.clear, Theme.ground.opacity(colorScheme == .dark ? 0.55 : 0.35)], startPoint: .center, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { hour = Calendar.current.component(.hour, from: Date()) }
        }
        .accessibilityHidden(true)
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        let a = Float(0.06 + energy * 0.08)
        func wobble(_ speed: Double, _ phase: Double) -> Float { Float(sin(t * speed + phase)) * a }
        return [
            SIMD2(0, 0), SIMD2(0.5 + wobble(0.23, 0), 0), SIMD2(1, 0),
            SIMD2(0, 0.5 + wobble(0.19, 1)), SIMD2(0.5 + wobble(0.31, 2), 0.5 + wobble(0.27, 3)), SIMD2(1, 0.5 + wobble(0.21, 4)),
            SIMD2(0, 1), SIMD2(0.5 + wobble(0.17, 5), 1), SIMD2(1, 1),
        ]
    }

    private var colors: [Color] {
        let palette = Self.palette(hour: hour)
        let base = Theme.ground
        let lead = mood ?? palette[0]
        return [
            lead, palette[1].opacity(0.85), palette[2],
            palette[2].opacity(0.55), base.opacity(0.35), lead.opacity(0.6),
            base, palette[1].opacity(0.35), base,
        ]
    }

    /// Three saturated colours per part of the day.
    static func palette(hour: Int) -> [Color] {
        switch hour {
        case 5..<10: [Theme.honey, Theme.coral, Theme.magenta]
        case 10..<16: [Theme.cyan, Theme.leaf, Theme.fat]
        case 16..<21: [Theme.magenta, Theme.coral, Theme.violet]
        default: [Theme.violet, Theme.fat, Theme.magenta]
        }
    }
}
