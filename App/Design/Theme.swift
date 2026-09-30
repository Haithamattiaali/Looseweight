import SwiftUI
import UIKit

/// Design tokens for "The Plate". One accent (leaf) marks room left; ember marks over.
enum Theme {
    // MARK: Palette

    static let ground = Color(light: 0xF6F4EF, dark: 0x0B0C0B)
    static let groundRaised = Color(light: 0xFFFFFF, dark: 0x151715)
    static let ink = Color(light: 0x111311, dark: 0xF3F2EE)
    static let inkSecondary = Color(light: 0x111311, dark: 0xF3F2EE, lightAlpha: 0.60, darkAlpha: 0.62)
    static let inkTertiary = Color(light: 0x111311, dark: 0xF3F2EE, lightAlpha: 0.36, darkAlpha: 0.40)
    static let hairline = Color(light: 0x111311, dark: 0xF3F2EE, lightAlpha: 0.08, darkAlpha: 0.12)

    static let leaf = Color(light: 0x1F9D6B, dark: 0x3CCB8C)
    static let ember = Color(light: 0xE4572E, dark: 0xFF7A52)
    static let honey = Color(light: 0xE9A23B, dark: 0xF4B654)
    static let protein = Color(light: 0xD9486A, dark: 0xF0708D)
    static let carbs = honey
    static let fat = Color(light: 0x4C7BE0, dark: 0x7FA3F5)

    // MARK: Spacing (4 pt base)

    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let gutter: CGFloat = 20

    // MARK: Radii (concentric)

    static let sheetRadius: CGFloat = 38
    static let controlRadius: CGFloat = 28
    static let thumbRadius: CGFloat = 18
    static let chipRadius: CGFloat = 12
    /// Kept for older call sites: large content shapes use the control radius.
    static let cardRadius: CGFloat = controlRadius

    // MARK: Motion

    static let snap = Animation.spring(duration: 0.28, bounce: 0.15)
    static let settle = Animation.spring(duration: 0.5, bounce: 0.2)
    static let fill = Animation.spring(duration: 0.9, bounce: 0.05)
    static let breath = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)
    /// Default spring for state changes.
    static let spring = settle

    static func confidenceColor(_ value: Double) -> Color {
        switch value {
        case ..<0.45: ember
        case ..<0.7: honey
        default: leaf
        }
    }

    static func confidenceWord(_ value: Double) -> String {
        switch value {
        case ..<0.45: "Low confidence"
        case ..<0.7: "Medium confidence"
        default: "High confidence"
        }
    }
}

// MARK: - Type

extension Font {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    /// 88 pt rounded: kcal left on Today, total on Review.
    static let hero = Font.system(size: 88, weight: .semibold, design: .rounded)
    /// 56 pt rounded: plan target, weight.
    static let display = Font.system(size: 56, weight: .semibold, design: .rounded)
    /// Row numbers.
    static let numeric = Font.system(.title3, design: .rounded, weight: .semibold)
    /// Tiny expanded all-caps voice.
    static let label = Font.system(size: 11, weight: .semibold).width(.expanded)
}

/// Small uppercase label ("KCAL LEFT", "PROTEIN").
struct LabelText: View {
    var text: String
    var color: Color = Theme.inkSecondary

    init(_ text: String, color: Color = Theme.inkSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.label)
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

// MARK: - Colour helpers

extension Color {
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

extension Double {
    var kcalText: String { "\(Int(self.rounded())) kcal" }
    var oneDecimal: String { String(format: "%.1f", self) }
}
