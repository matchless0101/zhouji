import SwiftUI

/// A white floating circle, matching the other round page controls.
struct ZJBackButton: View {
    var label = "关闭"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ZJTheme.ink)
                .frame(width: 44, height: 44)
                .background(ZJTheme.surface, in: Circle())
                .compositingGroup()
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct ZJPageHeader: View {
    let title: String
    var subtitle: String?
    var identifier: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(ZJTheme.titleFont(34, relativeTo: .largeTitle).weight(.bold))
                .foregroundStyle(ZJTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier)
            if let subtitle {
                Text(subtitle)
                    .font(ZJTheme.titleFont(20, relativeTo: .subheadline))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

/// Black capsule for the main action on a page.
struct ZJPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? ZJTheme.onAccent : ZJTheme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? ZJTheme.accent : ZJTheme.mutedSurface, in: Capsule())
            .compositingGroup()
            .shadow(color: .black.opacity(isEnabled ? 0.18 : 0), radius: 12, x: 0, y: 6)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// White capsule with a soft shadow for secondary actions.
struct ZJSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(isEnabled ? ZJTheme.ink : ZJTheme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(ZJTheme.surface, in: Capsule())
            .compositingGroup()
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A centered page title with a round back button on the left.
struct ZJTopBar: View {
    let title: String
    var identifier = ""
    var backLabel = "关闭"
    var backIdentifier = ""
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(ZJTheme.ink)
                .lineLimit(1)
                .padding(.horizontal, 56)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier)
            ZJBackButton(label: backLabel, action: onBack)
                .accessibilityIdentifier(backIdentifier)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, ZJTheme.pagePadding)
        .padding(.vertical, 6)
        .background(ZJTheme.pageBackground)
    }
}
