import Foundation
import Testing
@testable import ZhouJi

@MainActor struct FirstLaunchPresentationTests {
    @Test func preparingStateBeforeShowingTheScreenDoesNotConsumeFirstLaunch() throws {
        let suite = "first-launch-not-shown.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(FirstLaunchPresentation(defaults: defaults).isPresented)
        #expect(FirstLaunchPresentation(defaults: defaults).isPresented)
    }

    @Test func newInstallationShowsTheCoverOnceAcrossRelaunches() throws {
        let suite = "first-launch-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = FirstLaunchPresentation(defaults: defaults)
        #expect(first.isPresented)
        first.begin()
        first.finish()
        #expect(!first.isPresented)

        let reopenedDefaults = try #require(UserDefaults(suiteName: suite))
        #expect(!FirstLaunchPresentation(defaults: reopenedDefaults).isPresented)
    }

    @Test func interruptedFirstPresentationIsNotReplayed() throws {
        let suite = "first-launch-interrupted.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let interrupted = FirstLaunchPresentation(defaults: defaults)
        #expect(interrupted.isPresented)
        interrupted.begin()
        // A new process must not replay a cover already shown before it was interrupted.
        #expect(!FirstLaunchPresentation(defaults: defaults).isPresented)
        interrupted.finish()
        interrupted.finish()
        #expect(!interrupted.isPresented)
    }

    @Test func installationMarkerDoesNotTouchAccountOrTaskPreferences() throws {
        let suite = "first-launch-preferences.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("account-A", forKey: "localLibraryScope")
        let original = defaults.dictionaryRepresentation()

        let presentation = FirstLaunchPresentation(defaults: defaults)
        presentation.begin()
        presentation.finish()
        #expect(defaults.string(forKey: "localLibraryScope") == "account-A")
        let addedKeys = Set(defaults.dictionaryRepresentation().keys).subtracting(original.keys)
        #expect(addedKeys.count == 1)
        defaults.set("guest", forKey: "localLibraryScope")
        #expect(!FirstLaunchPresentation(defaults: defaults).isPresented)
    }
}
