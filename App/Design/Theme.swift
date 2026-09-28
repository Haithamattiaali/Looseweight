import SwiftUI

enum Theme {
    static let mint = Color(red: 0.36, green: 0.88, blue: 0.60)
    static let teal = Color(red: 0.11, green: 0.75, blue: 0.64)
    static let deep = Color(red: 0.04, green: 0.35, blue: 0.32)
    static let sun = Color(red: 1.00, green: 0.74, blue: 0.33)
    static let coral = Color(red: 1.00, green: 0.47, blue: 0.42)
    static let sky = Color(red: 0.36, green: 0.62, blue: 1.00)

    static let protein = Color(red: 0.98, green: 0.45, blue: 0.47)
    static let carbs = Color(red: 1.00, green: 0.72, blue: 0.30)
    static let fat = Color(red: 0.45, green: 0.62, blue: 1.00)

    static let cardRadius: CGFloat = 28
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.78)

    static func confidenceColor(_ value: Double) -> Color {
        switch value {
        case ..<0.45: coral
        case ..<0.7: sun
        default: mint
        }
    }
}

extension Font {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

extension Double {
    var kcalText: String { "\(Int(self.rounded())) kcal" }
    var gramsText: String { "\(Int(self.rounded())) g" }
    var oneDecimal: String { String(format: "%.1f", self) }
}
