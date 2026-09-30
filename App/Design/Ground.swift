import SwiftUI

/// The still "Daylight" ground: warm paper tinted ≤6 % by the time of day. Never animated per frame.
struct DaylightGround: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var hour = Calendar.current.component(.hour, from: Date())

    var body: some View {
        MeshGradient(
            width: 2,
            height: 2,
            points: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)],
            colors: colors
        )
        .ignoresSafeArea()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { hour = Calendar.current.component(.hour, from: Date()) }
        }
        .accessibilityHidden(true)
    }

    private var colors: [Color] {
        let base = colorScheme == .dark ? UIColor(hex: 0x0B0C0B) : UIColor(hex: 0xF6F4EF)
        let tint = Self.tint(hour: hour, dark: colorScheme == .dark)
        let top = Color(uiColor: Self.blend(base, tint, 0.06))
        let mid = Color(uiColor: Self.blend(base, tint, 0.03))
        let plain = Color(uiColor: base)
        return [top, mid, mid, plain]
    }

    private static func tint(hour: Int, dark: Bool) -> UIColor {
        switch hour {
        case 5..<10: return UIColor(hex: 0xFFE9C9)
        case 17..<21: return UIColor(hex: 0xF5D6C8)
        case 10..<17: return dark ? UIColor(hex: 0x1A2233) : UIColor(hex: 0xFFFFFF)
        default: return dark ? UIColor(hex: 0x1A2233) : UIColor(hex: 0xF5D6C8)
        }
    }

    private static func blend(_ a: UIColor, _ b: UIColor, _ amount: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: ar + (br - ar) * amount,
            green: ag + (bg - ag) * amount,
            blue: ab + (bb - ab) * amount,
            alpha: 1
        )
    }
}
