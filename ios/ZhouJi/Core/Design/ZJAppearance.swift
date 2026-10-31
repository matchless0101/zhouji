import Foundation
import Observation
import SwiftUI
import UIKit

enum ZJVisualStyle: String, CaseIterable, Identifiable, Sendable {
    case printed
    case tech

    static let defaultsKey = "zj.visualStyle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .printed: "复古印刷"
        case .tech: "黑白科技"
        }
    }
}

/// Views read the style through `ZJTheme`, so Observation re-renders every page that touched a token.
@Observable
final class ZJAppearance: @unchecked Sendable {
    static let shared = ZJAppearance()

    private(set) var style: ZJVisualStyle
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        style = defaults.string(forKey: ZJVisualStyle.defaultsKey).flatMap(ZJVisualStyle.init(rawValue:)) ?? .printed
    }

    @MainActor func select(_ style: ZJVisualStyle) {
        guard style != self.style else { return }
        self.style = style
        defaults.set(style.rawValue, forKey: ZJVisualStyle.defaultsKey)
        // Sheets already on screen keep their own trait collection; align every window with the new scheme.
        let interfaceStyle: UIUserInterfaceStyle = style == .tech ? .dark : .light
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = interfaceStyle }
        }
    }
}

extension View {
    /// Printed artwork stays in color on paper and becomes a quiet grayscale print in the tech style.
    func zjIllustrationTone() -> some View {
        modifier(ZJIllustrationTone())
    }
}

private struct ZJIllustrationTone: ViewModifier {
    func body(content: Content) -> some View {
        let isTech = ZJTheme.style == .tech
        content
            .grayscale(isTech ? 1 : 0)
            .opacity(isTech ? 0.72 : 1)
    }
}
