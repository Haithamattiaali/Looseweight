import SwiftUI

/// The day as a plate: a disc that fills like liquid as you eat, with three macro arcs on the rim.
struct PlateView: View {
    enum Style {
        /// Today: 300 pt, hero number inside.
        case full
        /// Toolbar / week strip: no text.
        case compact
        /// Outline only (empty day, onboarding).
        case outline
    }

    struct Macros: Equatable {
        var protein: Double
        var carbs: Double
        var fat: Double
        var proteinTarget: Double
        var carbsTarget: Double
        var fatTarget: Double

        static let none = Macros(protein: 0, carbs: 0, fat: 0, proteinTarget: 1, carbsTarget: 1, fatTarget: 1)
    }

    var eaten: Double
    var target: Double
    var macros: Macros = .none
    var style: Style = .full

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { target > 0 ? max(0, eaten / target) : 0 }
    private var isOver: Bool { eaten > target && target > 0 }
    private var liquid: Color { isOver ? Theme.ember : Theme.leaf }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let rim = rimWidth(side)
            ZStack {
                disc(rim: rim)
                PlateRim(macros: macros, lineWidth: rim, dashed: style == .outline)
                if style == .full {
                    centre(side: side)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .phaseAnimator([1.0, 1.05, 0.98, 1.0], trigger: isOver) { content, scale in
            content.scaleEffect(reduceMotion ? 1 : scale)
        } animation: { _ in Theme.snap }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func rimWidth(_ side: CGFloat) -> CGFloat {
        switch style {
        case .full, .outline: max(3, side * 0.033)
        case .compact: max(2, side * 0.08)
        }
    }

    private func disc(rim: CGFloat) -> some View {
        ZStack {
            Circle().fill(Theme.hairline.opacity(style == .outline ? 0 : 0.5))
            if style != .outline {
                LiquidShape(level: min(fraction, 1))
                    .fill(liquid.opacity(style == .compact ? 0.55 : 0.22))
                    .animation(reduceMotion ? nil : Theme.fill, value: fraction)
            }
        }
        .clipShape(Circle())
        .padding(rim * 1.6)
    }

    private func centre(side: CGFloat) -> some View {
        let value = Int(abs(target - eaten).rounded())
        return VStack(spacing: 2) {
            ViewThatFits(in: .horizontal) {
                heroNumber(value, size: min(88, side * 0.29))
                heroNumber(value, size: 64)
                heroNumber(value, size: 44)
            }
            LabelText(isOver ? "kcal over" : "kcal left", color: isOver ? Theme.ember : Theme.inkSecondary)
        }
        .padding(.horizontal, side * 0.14)
    }

    private func heroNumber(_ value: Int, size: CGFloat) -> some View {
        Text(value, format: .number)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .tracking(-2)
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            .contentTransition(.numericText(value: Double(value)))
            .lineLimit(1)
    }

    private var accessibilityText: String {
        if target <= 0 { return "No plan yet" }
        return isOver
            ? "\(Int(eaten - target)) calories over today, \(Int(eaten)) of \(Int(target)) eaten"
            : "\(Int(target - eaten)) calories left today, \(Int(eaten)) of \(Int(target)) eaten"
    }
}

/// The rim: a hairline track with three macro arcs (protein, carbs, fat), 2° gaps between them.
struct PlateRim: View {
    var macros: PlateView.Macros
    var lineWidth: CGFloat
    var dashed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dashed ? [lineWidth * 1.2, lineWidth * 1.8] : []))
            arc(index: 0, value: macros.protein, target: macros.proteinTarget, color: Theme.protein)
            arc(index: 1, value: macros.carbs, target: macros.carbsTarget, color: Theme.carbs)
            arc(index: 2, value: macros.fat, target: macros.fatTarget, color: Theme.fat)
        }
        .padding(lineWidth / 2)
    }

    private func arc(index: Int, value: Double, target: Double, color: Color) -> some View {
        let gap = 2.0 / 360.0
        let segment = 1.0 / 3.0
        let start = Double(index) * segment + gap / 2
        let progress = target > 0 ? min(max(value / target, 0), 1) : 0
        let end = start + (segment - gap) * progress
        return Circle()
            .trim(from: start, to: max(start, end))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .rotationEffect(.degrees(-90))
            .animation(reduceMotion ? nil : Theme.fill, value: progress)
    }
}

/// Liquid rising from the bottom, with a gentle meniscus.
struct LiquidShape: Shape {
    var level: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard level > 0 else { return path }
        let surface = rect.maxY - rect.height * CGFloat(min(level, 1))
        let amplitude = min(rect.height * 0.015, 6) * CGFloat(level < 1 ? 1 : 0)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: surface))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: surface),
            control1: CGPoint(x: rect.minX + rect.width * 0.33, y: surface - amplitude),
            control2: CGPoint(x: rect.minX + rect.width * 0.66, y: surface + amplitude)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
