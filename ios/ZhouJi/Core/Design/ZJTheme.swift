import SwiftUI

enum ZJTheme {
    static var style: ZJVisualStyle { ZJAppearance.shared.style }

    private static var palette: ZJPalette { style == .tech ? .tech : .printed }

    static func handwriting(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        // The tech style trades the hand-lettered face for the system Chinese face at an optically matched size.
        self.style == .tech
            ? .custom("PingFangSC-Medium", size: (size * 0.84).rounded(), relativeTo: style)
            : .custom("Xiaolai", size: size, relativeTo: style)
    }

    /// Readouts use rounded digits on paper and fixed-width digits in the tech style.
    static var numberDesign: Font.Design { style == .tech ? .monospaced : .rounded }

    static var colorScheme: ColorScheme { style == .tech ? .dark : .light }

    static var background: Color { palette.background }

    static var surface: Color { palette.surface }

    static var mutedSurface: Color { palette.mutedSurface }

    static var ink: Color { palette.ink }

    static var secondaryInk: Color { palette.secondaryInk }

    static var divider: Color { palette.divider }

    static var accent: Color { palette.accent }

    static var accentSoft: Color { palette.accentSoft }

    static var onAccent: Color { palette.onAccent }

    static var success: Color { palette.success }

    static var timerAccent: Color { accent }

    static var timerSoft: Color { accentSoft }

    static let pagePadding: CGFloat = 18
    static let controlHeight: CGFloat = 48
    static var cornerRadius: CGFloat { style == .tech ? 10 : 22 }
    static var compactCornerRadius: CGFloat { style == .tech ? 6 : 14 }

    static var pageBackground: ZJPaperBackground { ZJPaperBackground() }

    static func goalAccent(for iconName: String) -> Color {
        iconName == "heart" ? accent : success
    }

    static func goalSoft(for iconName: String) -> Color {
        goalAccent(for: iconName).opacity(0.13)
    }

    static func goalSymbol(for iconName: String) -> String {
        switch iconName {
        case "scope": "sparkles"
        case "target": "scope"
        case "book.closed": "book"
        case "graduationcap": "graduationcap.fill"
        case "briefcase": "briefcase.fill"
        default: iconName
        }
    }

}

struct ZJGoalIcon: View {
    let iconName: String
    var size: CGFloat = 32
    var isDecorative = true

    var body: some View {
        ZJIcon(systemName: iconName, size: size, isDecorative: isDecorative)
            .frame(width: size, height: size)
            .accessibilityHidden(isDecorative)
    }
}

private struct ZJCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ZJTheme.surface, in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous)
                    .stroke(ZJTheme.divider.opacity(0.35), lineWidth: 0.7)
            }
            .shadow(color: ZJTheme.secondaryInk.opacity(0.055), radius: 6, x: 0, y: 2)
    }
}

struct ZJSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(ZJTheme.ink)

            Text(count, format: .number)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(ZJTheme.secondaryInk)

            Spacer(minLength: 0)
        }
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(count) 项")
    }
}

struct ZJEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    @ScaledMetric(relativeTo: .title3) private var symbolSize = 20.0

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZJIcon(systemName: systemImage, size: symbolSize * 1.6)
                .frame(width: 42, height: 42)
                .background(ZJTheme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ZJTheme.ink)

                Text(message)
                    .font(.body)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func zjCard() -> some View {
        modifier(ZJCardModifier())
    }
}

/// Shared color tokens; every page reads them through `ZJTheme` instead of branching on the style.
struct ZJPalette {
    let background: Color
    let surface: Color
    let mutedSurface: Color
    let ink: Color
    let secondaryInk: Color
    let divider: Color
    let accent: Color
    let accentSoft: Color
    let onAccent: Color
    let success: Color

    /// Cream paper, moss green and terracotta from the Liuli printed redesign.
    static let printed = ZJPalette(
        background: Color(red: 0.972, green: 0.941, blue: 0.877),
        surface: Color(red: 0.994, green: 0.967, blue: 0.91),
        mutedSurface: Color(red: 0.917, green: 0.873, blue: 0.788),
        ink: Color(red: 0.2, green: 0.224, blue: 0.176),
        secondaryInk: Color(red: 0.42, green: 0.425, blue: 0.35),
        divider: Color(red: 0.855, green: 0.806, blue: 0.712),
        accent: Color(red: 0.753, green: 0.361, blue: 0.239),
        accentSoft: Color(red: 0.951, green: 0.849, blue: 0.738),
        onAccent: Color(red: 0.997, green: 0.974, blue: 0.922),
        success: Color(red: 0.386, green: 0.463, blue: 0.322)
    )

    /// Graphite surfaces with white primary actions; secondary text stays above 7:1 on the page.
    static let tech = ZJPalette(
        background: Color(red: 0.051, green: 0.055, blue: 0.063),
        surface: Color(red: 0.090, green: 0.098, blue: 0.110),
        mutedSurface: Color(red: 0.165, green: 0.176, blue: 0.192),
        ink: Color(red: 0.925, green: 0.933, blue: 0.941),
        secondaryInk: Color(red: 0.616, green: 0.639, blue: 0.667),
        divider: Color(red: 0.204, green: 0.220, blue: 0.243),
        accent: Color(red: 0.949, green: 0.953, blue: 0.961),
        accentSoft: Color(red: 0.149, green: 0.161, blue: 0.180),
        onAccent: Color(red: 0.051, green: 0.055, blue: 0.063),
        success: Color(red: 0.769, green: 0.788, blue: 0.812)
    )
}
