import XCTest

final class AppCapabilityConfigurationTests: XCTestCase {
    func testAppDeclaresOnlyReachableCapabilities() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let info = try propertyList(at: repository.appendingPathComponent("WGJ-App-Info.plist"))
        let debug = try propertyList(at: repository.appendingPathComponent("WGJ/WGJ-Debug.entitlements"))
        let release = try propertyList(at: repository.appendingPathComponent("WGJ/WGJ-Release.entitlements"))
        let project = try String(
            contentsOf: repository.appendingPathComponent("WGJ.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertNil(info["UIBackgroundModes"])
        for entitlements in [debug, release] {
            XCTAssertNil(entitlements["aps-environment"])
            XCTAssertNotNil(entitlements["com.apple.security.application-groups"])
            XCTAssertNotNil(entitlements["com.apple.developer.icloud-container-identifiers"])
            XCTAssertEqual(
                entitlements["com.apple.developer.usernotifications.time-sensitive"] as? Bool,
                true
            )
        }
        XCTAssertFalse(project.contains("com.apple.InAppPurchase"))
        XCTAssertFalse(project.contains("com.apple.Push"))
        XCTAssertTrue(project.contains("com.apple.TimeSensitiveNotifications"))
    }

    private func propertyList(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }
}
