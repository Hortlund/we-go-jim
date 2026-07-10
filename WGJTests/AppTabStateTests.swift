import XCTest
@testable import WGJ

@MainActor
final class AppTabStateTests: XCTestCase {
    func testInMemoryUITestLaunchIgnoresPersistedTab() {
        let suiteName = "AppTabStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            AppMainTab.profile.rawValue,
            forKey: AppTabState.selectedTabDefaultsKey
        )

        let state = AppTabState(
            defaults: defaults,
            arguments: ["UITEST_IN_MEMORY_STORE"]
        )

        XCTAssertEqual(state.selectedTab, .startWorkout)
    }
}
