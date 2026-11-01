import SwiftUI

/// Mono Soft tokens: light gray page, white cards and black ink blocks.
/// #555555 secondary text keeps 6.7:1 on the page.
enum ZJTheme {
    /// Titles use the system Chinese face; the size scale is kept from the earlier hand-lettered face.
    static func titleFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("PingFangSC-Medium", size: (size * 0.84).rounded(), relativeTo: style)
    }

    /// Readouts use plain system digits, usually at a light weight.
    static let numberDesign: Font.Design = .default

    static let background = Color(red: 0.953, green: 0.953, blue: 0.945)

    static let surface = Color.white

    static let mutedSurface = Color(red: 0.937, green: 0.937, blue: 0.929)

    static let ink = Color(red: 0.067, green: 0.067, blue: 0.067)

    static let secondaryInk = Color(red: 0.333, green: 0.333, blue: 0.333)

    static let divider = Color(red: 0.902, green: 0.902, blue: 0.890)

    static let accent = ink

    static let accentSoft = mutedSurface

    static let onAccent = Color.white

    static let success = ink

    static let timerAccent = accent

    static let timerSoft = accentSoft

    /// The black block that carries "happening now" content.
    static let emphasisSurface = ink

    static let onEmphasis = Color.white

    static let secondaryOnEmphasis = Color(red: 0.710, green: 0.710, blue: 0.710)

    static let pagePadding: CGFloat = 18
    static let controlHeight: CGFloat = 48
    static let cornerRadius: CGFloat = 24
    static let compactCornerRadius: CGFloat = 16

    static let pageBackground = background

    static func goalAccent(for iconName: String) -> Color {
        success
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

/// Cards separate from the page with a soft shadow alone, never a stroke.
private struct ZJCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ZJTheme.surface, in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous))
            .compositingGroup()
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
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

    /// A black ink block for "happening now" content such as the active timer bar.
    func zjEmphasisCard() -> some View {
        background(ZJTheme.emphasisSurface,
                   in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous))
            .compositingGroup()
            .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 10)
    }
}

/// A black summary card with faint, still contour lines; purely decorative.
struct ZJInkBlock: View {
    var cornerRadius: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(ZJTheme.emphasisSurface)
            .overlay {
                Canvas { context, size in
                    for index in 0..<7 {
                        let y = size.height * (0.32 + CGFloat(index) * 0.11)
                        var path = Path()
                        path.move(to: CGPoint(x: -10, y: y))
                        path.addCurve(to: CGPoint(x: size.width + 10, y: y - size.height * 0.4),
                                      control1: CGPoint(x: size.width * 0.3, y: y - size.height * 0.32),
                                      control2: CGPoint(x: size.width * 0.58, y: y + size.height * 0.22))
                        context.stroke(path, with: .color(ZJTheme.onEmphasis.opacity(0.10)), lineWidth: 1)
                    }
                }
                .clipShape(shape)
            }
            .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 10)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
