import SwiftUI

struct ZJIllustration: View {
    @Environment(\.colorScheme) private var colorScheme
    let name: String
    var height: CGFloat = 200

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .opacity(colorScheme == .dark ? 0.88 : 1)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

struct ZJPaperBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZJTheme.background.overlay {
            Canvas { context, size in
                // Fixed positions keep the paper still while the surrounding views update.
                for index in 0..<1_600 {
                    let x = CGFloat((index * 73 + 19) % 997) / 997 * size.width
                    let y = CGFloat((index * 137 + 47) % 991) / 991 * size.height
                    let side = index.isMultiple(of: 5) ? 1.2 : 0.6
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: side, height: side)),
                                 with: .color(ZJTheme.ink.opacity(colorScheme == .dark ? 0.035 : 0.045)))
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct ZJAddButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var diameter: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.43, weight: .regular, design: .rounded))
            .foregroundStyle(ZJTheme.onAccent)
            .frame(width: diameter, height: diameter)
            .background(ZJTheme.accent, in: Circle())
            .overlay { Circle().strokeBorder(ZJTheme.onAccent.opacity(0.3), lineWidth: 1) }
            .shadow(color: ZJTheme.accent.opacity(0.12), radius: 6, y: 3)
            .padding(max(0, (44 - diameter) / 2))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
    }
}

/// Edge-to-edge scenes use a viewport instead of shrinking into a small vignette.
struct ZJScene: View {
    @Environment(\.colorScheme) private var colorScheme
    let name: String
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Image(name)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .opacity(colorScheme == .dark ? 0.88 : 1)
        }
        .frame(height: height)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
