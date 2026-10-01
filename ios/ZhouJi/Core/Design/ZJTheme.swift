import SwiftUI

enum ZJTheme {
    static func handwriting(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("LXGWWenKai-Regular", size: size, relativeTo: style)
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

    static let timerAccent = Color(red: 0.753, green: 0.361, blue: 0.239, opacity: 1)

    static let timerSoft = Color(red: 0.951, green: 0.849, blue: 0.738, opacity: 1)

    static let pagePadding: CGFloat = 18
    static let pageTopSpacing: CGFloat = 42
    static let compactPageTopSpacing: CGFloat = 22
    static let rowVerticalPadding: CGFloat = 12
    static let controlHeight: CGFloat = 48
    static let cornerRadius: CGFloat = 22
    static let compactCornerRadius: CGFloat = 14
    static let hairlineOpacity = 0.62

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

    static func goalProgress(for iconName: String) -> Color { success }
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

struct ZJBrandHeader: View {
    let subtitle: String
    let systemImage: String
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("粥记")
                    .font(.system(.title2, design: .default, weight: .bold))
                    .foregroundStyle(ZJTheme.ink)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if let action {
                Button(action: action) {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(ZJTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(ZJTheme.surface, in: Circle())
                        .overlay {
                            Circle().stroke(ZJTheme.divider.opacity(0.7), lineWidth: 0.5)
                        }
                        .shadow(color: ZJTheme.accent.opacity(0.10), radius: 12, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actionLabel ?? "操作")
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
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

struct ZJPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? ZJTheme.accent : ZJTheme.secondaryInk)
            .background(
                isEnabled ? ZJTheme.accentSoft : ZJTheme.mutedSurface,
                in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous)
                    .stroke(isEnabled ? ZJTheme.accent.opacity(0.18) : ZJTheme.divider, lineWidth: 1)
            }
            .shadow(color: isEnabled ? ZJTheme.accent.opacity(0.09) : .clear, radius: 12, x: 0, y: 5)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ZJSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? ZJTheme.ink : ZJTheme.secondaryInk)
            .background(
                ZJTheme.surface,
                in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous)
                    .stroke(ZJTheme.divider.opacity(0.78), lineWidth: 0.7)
            }
            .shadow(color: ZJTheme.accent.opacity(0.06), radius: 12, x: 0, y: 5)
            .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.55))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ZJTimerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? ZJTheme.timerAccent : ZJTheme.secondaryInk)
            .background(
                isEnabled ? ZJTheme.timerSoft : ZJTheme.mutedSurface,
                in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous)
                    .stroke(isEnabled ? ZJTheme.timerAccent.opacity(0.20) : ZJTheme.divider, lineWidth: 1)
            }
            .shadow(color: isEnabled ? ZJTheme.timerAccent.opacity(0.10) : .clear, radius: 12, x: 0, y: 5)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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

extension ButtonStyle where Self == ZJPrimaryButtonStyle {
    static var zjPrimary: ZJPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == ZJSecondaryButtonStyle {
    static var zjSecondary: ZJSecondaryButtonStyle { .init() }
}

extension ButtonStyle where Self == ZJTimerButtonStyle {
    static var zjTimer: ZJTimerButtonStyle { .init() }
}
