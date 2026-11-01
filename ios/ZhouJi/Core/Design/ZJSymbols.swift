import SwiftUI

struct ZJAddButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var diameter: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.43, weight: .regular, design: .rounded))
            .foregroundStyle(ZJTheme.onAccent)
            .frame(width: diameter, height: diameter)
            .background(ZJTheme.accent, in: Circle())
            .compositingGroup()
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            .padding(max(0, (44 - diameter) / 2))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
    }
}

/// Line system symbols at a consistent optical size.
struct ZJIcon: View {
    let systemName: String
    var size: CGFloat = 40
    var tint: Color?
    var isDecorative = true

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.56, weight: .regular))
            .foregroundStyle(tint ?? ZJTheme.success)
            .frame(width: size, height: size)
            .accessibilityHidden(isDecorative)
    }
}
