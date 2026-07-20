import XCTest
@testable import WGJ

@MainActor
final class AppTabStateTests: XCTestCase {
    func testColdLaunchIgnoresPersistedTab() {
        let legacySelectedTabDefaultsKey = "selectedMainTab"
        let suiteName = "AppTabStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            AppMainTab.profile.rawValue,
            forKey: legacySelectedTabDefaultsKey
        )

        let state = AppTabState(defaults: defaults)

        XCTAssertEqual(state.selectedTab, .startWorkout)
    }

    func testChangingTabDoesNotPersistAcrossProcessState() {
        let legacySelectedTabDefaultsKey = "selectedMainTab"
        let suiteName = "AppTabStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppTabState(defaults: defaults)

        state.selectedTab = .history

        XCTAssertEqual(state.selectedTab, .history)
        XCTAssertNil(defaults.string(forKey: legacySelectedTabDefaultsKey))
    }
}
