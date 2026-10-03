import SwiftUI

struct ZJIllustration: View {
    let name: String
    var height: CGFloat = 200

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

struct ZJPaperBackground: View {

    var body: some View {
        ZJTheme.background.overlay {
            Canvas { context, size in
                // Fixed positions keep the paper still while the surrounding views update.
                for index in 0..<1_600 {
                    let x = CGFloat((index * 73 + 19) % 997) / 997 * size.width
                    let y = CGFloat((index * 137 + 47) % 991) / 991 * size.height
                    let side = index.isMultiple(of: 5) ? 1.2 : 0.6
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: side, height: side)),
                                 with: .color(ZJTheme.ink.opacity(0.045)))
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

/// Printed artwork replaces matching symbols; specialized controls keep their existing meaning.
struct ZJIcon: View {
    let systemName: String
    var size: CGFloat = 40
    var tint: Color?
    var isDecorative = true

    var body: some View {
        Group {
            if let name = assetName {
                Image(name)
                    .renderingMode(tint == nil ? .original : .template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.7, weight: .regular))
            }
        }
        .foregroundStyle(tint ?? ZJTheme.success)
        .frame(width: size, height: size)
        .accessibilityHidden(isDecorative)
    }

    private var assetName: String? {
        switch systemName {
        case "leaf", "leaf.fill": "LiuliLeaf"
        case "book", "book.fill", "book.closed": "LiuliBook"
        case "graduationcap", "graduationcap.fill": "LiuliStudy"
        case "briefcase", "briefcase.fill": "LiuliWork"
        case "iphone": "LiuliDigital"
        case "paintpalette", "paintpalette.fill": "LiuliCreate"
        case "figure.run", "dumbbell", "dumbbell.fill": "LiuliDumbbell"
        case "heart", "heart.fill": "LiuliLove"
        case "star", "star.fill": "LiuliStar"
        case "clock", "clock.fill": "LiuliClock"
        case "sun.max", "sun.max.fill": "LiuliSun"
        case "cloud", "cloud.fill": "LiuliCloud"
        case "house", "house.fill": "LiuliHome"
        case "calendar": "LiuliCalendarIcon"
        case "target", "scope", "sparkles": "LiuliTarget"
        case "person", "person.fill": "LiuliProfile"
        case "gearshape", "gearshape.fill": "LiuliGear"
        default: nil
        }
    }
}
