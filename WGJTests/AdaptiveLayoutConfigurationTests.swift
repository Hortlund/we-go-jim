import XCTest

final class AdaptiveLayoutConfigurationTests: XCTestCase {
    func testIPadSupportsResizablePortraitAndLandscape() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let plistURL = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ-App-Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertNil(plist["UIRequiresFullScreen"])
        let sceneManifest = try XCTUnwrap(
            plist["UIApplicationSceneManifest"] as? [String: Any]
        )
        XCTAssertEqual(sceneManifest["UIApplicationSupportsMultipleScenes"] as? Bool, false)
        XCTAssertEqual(
            Set(plist["UISupportedInterfaceOrientations~ipad"] as? [String] ?? []),
            Set([
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationPortraitUpsideDown",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight",
            ])
        )
    }
}
