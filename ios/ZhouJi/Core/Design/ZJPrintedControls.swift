import SwiftUI

/// Stationary ink gaps give controls the same dry-print texture as the illustrations.
struct ZJInkGrain: View {
    var count = 700
    var color = ZJTheme.onAccent.opacity(0.30)

    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x5A17
            for index in 0..<count {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                let x = CGFloat(seed >> 32) / CGFloat(UInt32.max) * size.width
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                let y = CGFloat(seed >> 32) / CGFloat(UInt32.max) * size.height
                let side: CGFloat = index.isMultiple(of: 5) ? 1.3 : 0.6
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: side, height: side)), with: .color(color))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct ZJBackButton: View {
    var label = "关闭"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(ZJTheme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct ZJPaperHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    var subtitle: String?
    var illustration: String?
    var identifier: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(ZJTheme.handwriting(34, relativeTo: .largeTitle).weight(.bold))
                    .foregroundStyle(ZJTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(identifier)
                if let subtitle {
                    Text(subtitle)
                        .font(ZJTheme.handwriting(20, relativeTo: .subheadline))
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            if let illustration, dynamicTypeSize <= .large {
                Image(decorative: illustration)
                    .resizable()
                    .scaledToFit()
                    .containerRelativeFrame(.horizontal) { width, _ in
                        max(0, width - ZJTheme.pagePadding * 2) * 0.49
                    }
                    .allowsHitTesting(false)
            }
        }
    }
}

struct ZJPrintedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ZJTheme.handwriting(22, relativeTo: .headline))
            .foregroundStyle(isEnabled ? ZJTheme.onAccent : ZJTheme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: ZJTheme.cornerRadius)
                    .fill(isEnabled ? ZJTheme.accent : ZJTheme.mutedSurface)
                    .overlay {
                        if isEnabled {
                            ZJInkGrain().clipShape(.rect(cornerRadius: ZJTheme.cornerRadius))
                        }
                    }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct ZJPaperButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var border = ZJTheme.success

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ZJTheme.handwriting(21, relativeTo: .headline))
            .foregroundStyle(isEnabled ? ZJTheme.ink : ZJTheme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.vertical, 3)
            .background(ZJTheme.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ZJTheme.cornerRadius)
                    .stroke(isEnabled ? border : ZJTheme.divider, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    func zjPaperCard() -> some View {
        background(ZJTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ZJTheme.cornerRadius)
                    .stroke(ZJTheme.divider, lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
    }
}
