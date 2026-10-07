import Foundation
import Observation

@MainActor @Observable
final class FirstLaunchPresentation {
    private(set) var isPresented: Bool
    private let defaults: UserDefaults
    private static let key = "hasShownOpeningAnimation"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPresented = !defaults.bool(forKey: Self.key)
    }

    func begin() {
        guard isPresented else { return }
        // Persist when the cover reaches the foreground, before it can be interrupted.
        defaults.set(true, forKey: Self.key)
    }

    func finish() { isPresented = false }
}
