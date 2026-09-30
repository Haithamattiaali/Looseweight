import SwiftUI
import UIKit

/// Design tokens for "Aurora": dark-first, saturated colour, glass floating over light. Leaf (mint) marks room
/// left and go; ember (hot coral) marks over; every food and macro has its own vivid colour.
enum Theme {
    // MARK: Palette

    static let ground = Color(light: 0xF3F0FF, dark: 0x07060F)
    static let groundRaised = Color(light: 0xFFFFFF, dark: 0x16132B)
    static let ink = Color(light: 0x0E0B1F, dark: 0xFFFFFF)
    static let inkSecondary = Color(light: 0x0E0B1F, dark: 0xFFFFFF, lightAlpha: 0.64, darkAlpha: 0.72)
    static let inkTertiary = Color(light: 0x0E0B1F, dark: 0xFFFFFF, lightAlpha: 0.40, darkAlpha: 0.46)
    static let hairline = Color(light: 0x0E0B1F, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.14)

    static let leaf = Color(light: 0x00A67E, dark: 0x2EF2B0)
    static let ember = Color(light: 0xF0265E, dark: 0xFF5C86)
    static let honey = Color(light: 0xF08C00, dark: 0xFFC23D)
    static let protein = Color(light: 0xE8267A, dark: 0xFF5FA2)
    static let carbs = honey
    static let fat = Color(light: 0x2F6BFF, dark: 0x5AA2FF)

    static let violet = Color(light: 0x5B3DF5, dark: 0x8B6CFF)
    static let cyan = Color(light: 0x0096C7, dark: 0x22E1FF)
    static let magenta = Color(light: 0xC23BE8, dark: 0xFF5CF4)
    static let coral = Color(light: 0xF2545B, dark: 0xFF7A6B)
    static let lime = Color(light: 0x6BAF00, dark: 0xB6F35A)

    /// The AI's colours: the orb, the scanning light, suggestions.
    static let aiColors: [Color] = [violet, cyan, leaf, magenta, violet]
    static var aiGradient: LinearGradient {
        LinearGradient(colors: [violet, magenta, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Vivid per-food colours; a food keeps its colour on every screen (stable hash of the name).
    static let foodPalette: [Color] = [coral, honey, lime, leaf, cyan, fat, violet, magenta]

    static func foodColor(for name: String, isDrink: Bool = false) -> Color {
        if isDrink { return cyan }
        let sum = name.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return foodPalette[sum % foodPalette.count]
    }

    /// A lighter-to-full sweep of one colour, for bars, arcs and slider fills.
    static func sweep(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.55), color], startPoint: .leading, endPoint: .trailing)
    }

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

    /// 96 pt heavy rounded: kcal left on Today, total on Review and Plan.
    static let hero = Font.system(size: 96, weight: .heavy, design: .rounded)
    /// 60 pt bold rounded: plan target, weight.
    static let display = Font.system(size: 60, weight: .bold, design: .rounded)
    /// Big confident screen titles.
    static let screenTitle = Font.system(size: 34, weight: .heavy, design: .rounded)
    /// Row numbers.
    static let numeric = Font.system(.title3, design: .rounded, weight: .bold)
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
