import SwiftUI

/// Slowly drifting mesh gradient behind every screen, so the glass layers have light to bend.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            MeshGradient(width: 3, height: 3, points: Self.points(at: context.date), colors: colors)
        }
        .ignoresSafeArea()
    }

    private static func points(at date: Date) -> [SIMD2<Float>] {
        let t = Float(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
        let top = SIMD2<Float>(0.5 + 0.08 * sin(t * 0.21), 0)
        let left = SIMD2<Float>(0, 0.5 + 0.07 * cos(t * 0.17))
        let middle = SIMD2<Float>(0.5 + 0.10 * sin(t * 0.13), 0.5 + 0.10 * cos(t * 0.19))
        let right = SIMD2<Float>(1, 0.5 + 0.07 * sin(t * 0.23))
        let bottom = SIMD2<Float>(0.5 + 0.08 * cos(t * 0.11), 1)
        return [
            SIMD2(0, 0), top, SIMD2(1, 0),
            left, middle, right,
            SIMD2(0, 1), bottom, SIMD2(1, 1),
        ]
    }

    private var colors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.02, green: 0.10, blue: 0.10), Color(red: 0.03, green: 0.20, blue: 0.18), Color(red: 0.02, green: 0.08, blue: 0.14),
                Color(red: 0.04, green: 0.22, blue: 0.18), Color(red: 0.05, green: 0.30, blue: 0.26), Color(red: 0.06, green: 0.14, blue: 0.24),
                Color(red: 0.02, green: 0.08, blue: 0.09), Color(red: 0.04, green: 0.16, blue: 0.14), Color(red: 0.03, green: 0.07, blue: 0.10),
            ]
        }
        return [
            Color(red: 0.87, green: 0.98, blue: 0.93), Color(red: 0.78, green: 0.95, blue: 0.90), Color(red: 0.86, green: 0.93, blue: 1.00),
            Color(red: 0.74, green: 0.94, blue: 0.84), Color(red: 0.93, green: 0.99, blue: 0.96), Color(red: 0.80, green: 0.90, blue: 1.00),
            Color(red: 0.99, green: 0.95, blue: 0.86), Color(red: 0.85, green: 0.97, blue: 0.90), Color(red: 0.90, green: 0.95, blue: 0.99),
        ]
    }
}
