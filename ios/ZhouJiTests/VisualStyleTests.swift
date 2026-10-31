import Foundation
import Testing
@testable import ZhouJi

@MainActor struct VisualStyleTests {
    @Test func newInstallationKeepsThePrintedStyle() throws {
        let suite = "visual-style-default.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ZJAppearance(defaults: defaults).style == .printed)
    }

    @Test func selectedStyleSurvivesRelaunch() throws {
        let suite = "visual-style-persist.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let appearance = ZJAppearance(defaults: defaults)
        appearance.select(.tech)
        #expect(appearance.style == .tech)
        #expect(ZJAppearance(defaults: try #require(UserDefaults(suiteName: suite))).style == .tech)

        appearance.select(.printed)
        #expect(ZJAppearance(defaults: defaults).style == .printed)
    }

    @Test func monoStyleSurvivesRelaunchAndStaysLight() throws {
        let suite = "visual-style-mono.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let appearance = ZJAppearance(defaults: defaults)
        appearance.select(.mono)
        #expect(ZJAppearance(defaults: try #require(UserDefaults(suiteName: suite))).style == .mono)
        #expect(!ZJVisualStyle.mono.isDark)
        #expect(!ZJVisualStyle.mono.isPrinted)
    }

    @Test func preferencesOfferThreeDistinctStyles() {
        #expect(ZJVisualStyle.allCases == [.printed, .tech, .mono])
        #expect(Set(ZJVisualStyle.allCases.map(\.title)) == ["复古印刷", "黑白科技", "黑白柔和"])
        #expect(ZJVisualStyle.allCases.filter(\.isDark) == [.tech])
    }

    @Test func unknownStoredValueFallsBackToPrinted() throws {
        let suite = "visual-style-unknown.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("neon", forKey: ZJVisualStyle.defaultsKey)

        #expect(ZJAppearance(defaults: defaults).style == .printed)
    }
}
