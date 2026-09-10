import SwiftUI
import UIKit

enum ZJTheme {
    static let background = Color.dynamic(
        light: UIColor(red: 0.978, green: 0.976, blue: 0.968, alpha: 1),
        dark: UIColor(red: 0.055, green: 0.070, blue: 0.100, alpha: 1)
    )

    static let surface = Color.dynamic(
        light: UIColor(red: 0.995, green: 0.997, blue: 1.000, alpha: 1),
        dark: UIColor(red: 0.095, green: 0.118, blue: 0.165, alpha: 1)
    )

    static let mutedSurface = Color.dynamic(
        light: UIColor(red: 0.937, green: 0.940, blue: 0.946, alpha: 1),
        dark: UIColor(red: 0.135, green: 0.160, blue: 0.215, alpha: 1)
    )

    static let ink = Color.dynamic(
        light: UIColor(red: 0.045, green: 0.048, blue: 0.055, alpha: 1),
        dark: UIColor(red: 0.925, green: 0.945, blue: 0.980, alpha: 1)
    )

    static let secondaryInk = Color.dynamic(
        light: UIColor(red: 0.405, green: 0.445, blue: 0.550, alpha: 1),
        dark: UIColor(red: 0.635, green: 0.690, blue: 0.790, alpha: 1)
    )

    static let divider = Color.dynamic(
        light: UIColor(red: 0.915, green: 0.920, blue: 0.936, alpha: 1),
        dark: UIColor(red: 0.205, green: 0.245, blue: 0.330, alpha: 1)
    )

    static let accent = Color.dynamic(
        light: UIColor(red: 0.025, green: 0.440, blue: 1.000, alpha: 1),
        dark: UIColor(red: 0.340, green: 0.650, blue: 1.000, alpha: 1)
    )

    static let accentSoft = Color.dynamic(
        light: UIColor(red: 0.875, green: 0.930, blue: 1.000, alpha: 1),
        dark: UIColor(red: 0.105, green: 0.230, blue: 0.410, alpha: 1)
    )

    static let onAccent = Color.dynamic(
        light: UIColor(red: 0.985, green: 0.992, blue: 1.000, alpha: 1),
        dark: UIColor(red: 0.035, green: 0.055, blue: 0.090, alpha: 1)
    )

    static let success = Color.dynamic(
        light: UIColor(red: 0.450, green: 0.475, blue: 0.545, alpha: 1),
        dark: UIColor(red: 0.560, green: 0.630, blue: 0.745, alpha: 1)
    )

    static let timerAccent = Color.dynamic(
        light: UIColor(red: 0.985, green: 0.545, blue: 0.060, alpha: 1),
        dark: UIColor(red: 1.000, green: 0.660, blue: 0.250, alpha: 1)
    )

    static let timerSoft = Color.dynamic(
        light: UIColor(red: 1.000, green: 0.940, blue: 0.825, alpha: 1),
        dark: UIColor(red: 0.310, green: 0.205, blue: 0.075, alpha: 1)
    )

    static let pagePadding: CGFloat = 18
    static let pageTopSpacing: CGFloat = 42
    static let compactPageTopSpacing: CGFloat = 22
    static let rowVerticalPadding: CGFloat = 12
    static let controlHeight: CGFloat = 48
    static let cornerRadius: CGFloat = 22
    static let compactCornerRadius: CGFloat = 14
    static let hairlineOpacity = 0.62

    static var pageBackground: LinearGradient {
        LinearGradient(
            colors: [accentSoft.opacity(0.30), background, background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func goalAccent(for iconName: String) -> Color {
        switch iconName {
        case "book.closed": goalOrange
        case "graduationcap": goalIndigo
        case "briefcase": accent
        case "iphone": goalPurple
        case "figure.run": goalCyan
        case "heart": goalRose
        case "paintpalette": goalPurple
        case "leaf": goalGreen
        default: accent
        }
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

    static func goalProgress(for iconName: String) -> Color {
        switch iconName {
        case "briefcase": Color(red: 0.49, green: 0.65, blue: 1)
        case "iphone", "paintpalette": Color(red: 0.66, green: 0.54, blue: 1)
        default: goalAccent(for: iconName)
        }
    }

    private static let goalOrange = Color.dynamic(
        light: UIColor(red: 0.995, green: 0.555, blue: 0.055, alpha: 1),
        dark: UIColor(red: 1.000, green: 0.680, blue: 0.260, alpha: 1)
    )
    private static let goalIndigo = Color.dynamic(
        light: UIColor(red: 0.345, green: 0.430, blue: 0.960, alpha: 1),
        dark: UIColor(red: 0.555, green: 0.625, blue: 1.000, alpha: 1)
    )
    private static let goalCyan = Color.dynamic(
        light: UIColor(red: 0.035, green: 0.650, blue: 0.810, alpha: 1),
        dark: UIColor(red: 0.250, green: 0.790, blue: 0.920, alpha: 1)
    )
    private static let goalRose = Color.dynamic(
        light: UIColor(red: 0.880, green: 0.330, blue: 0.470, alpha: 1),
        dark: UIColor(red: 1.000, green: 0.525, blue: 0.650, alpha: 1)
    )
    private static let goalPurple = Color.dynamic(
        light: UIColor(red: 0.470, green: 0.300, blue: 0.940, alpha: 1),
        dark: UIColor(red: 0.675, green: 0.535, blue: 1.000, alpha: 1)
    )
    private static let goalGreen = Color.dynamic(
        light: UIColor(red: 0.180, green: 0.650, blue: 0.420, alpha: 1),
        dark: UIColor(red: 0.370, green: 0.800, blue: 0.565, alpha: 1)
    )
}

struct ZJGoalIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    let iconName: String
    var size: CGFloat = 32
    var isDecorative = true

    var body: some View {
        let color = ZJTheme.goalAccent(for: iconName)
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)

        Image(systemName: ZJTheme.goalSymbol(for: iconName))
            .font(.system(size: size * 0.49, weight: .regular))
            .foregroundStyle(LinearGradient(
                colors: [color.opacity(0.78), color, color],
                startPoint: .top, endPoint: .bottom
            ))
            .shadow(color: isDark ? color.opacity(0.18) : .white.opacity(0.9), radius: 1, y: 1)
            .frame(width: size, height: size)
            .background {
                shape
                    .fill(LinearGradient(
                        stops: [.init(color: color.opacity(isDark ? 0.13 : 0.10), location: 0),
                                .init(color: color.opacity(isDark ? 0.25 : 0.24), location: 0.55),
                                .init(color: color.opacity(isDark ? 0.12 : 0.08), location: 1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay {
                        shape.fill(RadialGradient(
                            colors: [.white.opacity(isDark ? 0.12 : 0.85), .clear],
                            center: .topLeading, startRadius: 0, endRadius: size * 0.85
                        ))
                    }
                    .overlay {
                        shape.stroke(LinearGradient(
                            colors: [.white.opacity(isDark ? 0.18 : 0.96), .clear,
                                     .white.opacity(isDark ? 0.08 : 0.70)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ), lineWidth: 1)
                    }
                    .shadow(color: color.opacity(isDark ? 0.05 : 0.08), radius: size * 0.13, y: size * 0.08)
            }
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
                    .stroke(ZJTheme.surface.opacity(0.9), lineWidth: 1)
            }
            .shadow(color: ZJTheme.secondaryInk.opacity(0.055), radius: 14, x: 0, y: 6)
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

struct ZJFloatingGlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        glassSurface(
            configuration.label
                .font(.body.weight(.semibold))
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(minHeight: 54)
                .contentShape(Capsule())
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }

    @ViewBuilder
    private func glassSurface<Content: View>(_ content: Content) -> some View {
        if reduceTransparency {
            content
                .background(ZJTheme.surface, in: Capsule())
                .overlay { Capsule().stroke(ZJTheme.divider, lineWidth: 1) }
        } else if #available(iOS 26, *) {
            content
                .glassEffect(.regular.tint(ZJTheme.accent.opacity(0.06)).interactive(), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(LinearGradient(
                        colors: [.white.opacity(0.75), .white.opacity(0.12), .white.opacity(0.35)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 1)
                }
        }
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
            Image(systemName: systemImage)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(ZJTheme.accent)
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

private extension Color {
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
