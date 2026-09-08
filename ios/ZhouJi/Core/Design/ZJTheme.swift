import SwiftUI
import UIKit

enum ZJTheme {
    static let background = Color.dynamic(
        light: UIColor(red: 0.978, green: 0.969, blue: 0.953, alpha: 1),
        dark: UIColor(red: 0.090, green: 0.086, blue: 0.078, alpha: 1)
    )

    static let surface = Color.dynamic(
        light: UIColor(red: 0.996, green: 0.991, blue: 0.982, alpha: 1),
        dark: UIColor(red: 0.140, green: 0.132, blue: 0.118, alpha: 1)
    )

    static let mutedSurface = Color.dynamic(
        light: UIColor(red: 0.950, green: 0.932, blue: 0.902, alpha: 1),
        dark: UIColor(red: 0.190, green: 0.176, blue: 0.151, alpha: 1)
    )

    static let ink = Color.dynamic(
        light: UIColor(red: 0.115, green: 0.106, blue: 0.094, alpha: 1),
        dark: UIColor(red: 0.925, green: 0.898, blue: 0.847, alpha: 1)
    )

    static let secondaryInk = Color.dynamic(
        light: UIColor(red: 0.440, green: 0.414, blue: 0.376, alpha: 1),
        dark: UIColor(red: 0.690, green: 0.659, blue: 0.600, alpha: 1)
    )

    static let divider = Color.dynamic(
        light: UIColor(red: 0.895, green: 0.875, blue: 0.838, alpha: 1),
        dark: UIColor(red: 0.270, green: 0.255, blue: 0.220, alpha: 1)
    )

    static let accent = Color.dynamic(
        light: UIColor(red: 0.620, green: 0.333, blue: 0.154, alpha: 1),
        dark: UIColor(red: 0.850, green: 0.570, blue: 0.355, alpha: 1)
    )

    static let accentSoft = Color.dynamic(
        light: UIColor(red: 0.965, green: 0.910, blue: 0.838, alpha: 1),
        dark: UIColor(red: 0.245, green: 0.187, blue: 0.135, alpha: 1)
    )

    static let success = Color.dynamic(
        light: UIColor(red: 0.275, green: 0.447, blue: 0.314, alpha: 1),
        dark: UIColor(red: 0.490, green: 0.690, blue: 0.525, alpha: 1)
    )

    static let pagePadding: CGFloat = 20
    static let rowVerticalPadding: CGFloat = 13
    static let controlHeight: CGFloat = 48
    static let cornerRadius: CGFloat = 18
    static let compactCornerRadius: CGFloat = 12
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
                    .font(.system(.title2, design: .rounded, weight: .bold))
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
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .frame(width: 44, height: 44)
                        .background(ZJTheme.surface, in: Circle())
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
            .shadow(color: ZJTheme.ink.opacity(0.045), radius: 16, x: 0, y: 6)
    }
}

extension View {
    func zjCard() -> some View {
        modifier(ZJCardModifier())
    }
}

private extension Color {
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
