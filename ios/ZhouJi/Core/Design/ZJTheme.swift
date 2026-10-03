import SwiftUI

enum ZJTheme {
    static func handwriting(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Xiaolai", size: size, relativeTo: style)
    }

    static let background = Color(red: 0.972, green: 0.941, blue: 0.877, opacity: 1)

    static let surface = Color(red: 0.994, green: 0.967, blue: 0.91, opacity: 1)

    static let mutedSurface = Color(red: 0.917, green: 0.873, blue: 0.788, opacity: 1)

    static let ink = Color(red: 0.2, green: 0.224, blue: 0.176, opacity: 1)

    static let secondaryInk = Color(red: 0.42, green: 0.425, blue: 0.35, opacity: 1)

    static let divider = Color(red: 0.855, green: 0.806, blue: 0.712, opacity: 1)

    static let accent = Color(red: 0.753, green: 0.361, blue: 0.239, opacity: 1)

    static let accentSoft = Color(red: 0.951, green: 0.849, blue: 0.738, opacity: 1)

    static let onAccent = Color(red: 0.997, green: 0.974, blue: 0.922, opacity: 1)

    static let success = Color(red: 0.386, green: 0.463, blue: 0.322, opacity: 1)

    static let timerAccent = accent

    static let timerSoft = accentSoft

    static let pagePadding: CGFloat = 18
    static let controlHeight: CGFloat = 48
    static let cornerRadius: CGFloat = 22
    static let compactCornerRadius: CGFloat = 14

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
