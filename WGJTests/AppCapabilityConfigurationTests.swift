import XCTest
@testable import WGJ

final class AppCapabilityConfigurationTests: XCTestCase {
    func testRuntimeEnvironmentFallbackCannotPromoteDevelopmentBundleToProduction() {
        XCTAssertEqual(
            AppRuntimeConfig.resolvedAppEnvironment(
                configuredValue: nil,
                bundleIdentifier: "se.highball.WeGoJim.dev"
            ),
            .development
        )
        XCTAssertEqual(
            AppRuntimeConfig.resolvedAppEnvironment(
                configuredValue: "development",
                bundleIdentifier: "se.highball.WeGoJim"
            ),
            .development
        )
        XCTAssertEqual(
            AppRuntimeConfig.resolvedAppEnvironment(
                configuredValue: nil,
                bundleIdentifier: "se.highball.WeGoJim"
            ),
            .production
        )
    }

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

    func testDevelopmentAndProductionBuildsKeepUserDataSurfacesIsolated() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let info = try propertyList(at: repository.appendingPathComponent("WGJ-App-Info.plist"))
        let widgetInfo = try propertyList(
            at: repository.appendingPathComponent("WGJWidgetExtension/Info.plist")
        )
        let debug = try propertyList(at: repository.appendingPathComponent("WGJ/WGJ-Debug.entitlements"))
        let release = try propertyList(at: repository.appendingPathComponent("WGJ/WGJ-Release.entitlements"))
        let project = try String(
            contentsOf: repository.appendingPathComponent("WGJ.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let productionScheme = try String(
            contentsOf: repository.appendingPathComponent(
                "WGJ.xcodeproj/xcshareddata/xcschemes/WGJ.xcscheme"
            ),
            encoding: .utf8
        )
        let developmentScheme = try String(
            contentsOf: repository.appendingPathComponent(
                "WGJ.xcodeproj/xcshareddata/xcschemes/WGJ Dev.xcscheme"
            ),
            encoding: .utf8
        )

        XCTAssertEqual(info["WGJAppGroupIdentifier"] as? String, "$(WGJ_APP_GROUP_IDENTIFIER)")
        XCTAssertEqual(info["WGJURLScheme"] as? String, "$(WGJ_URL_SCHEME)")
        XCTAssertEqual(widgetInfo["WGJAppGroupIdentifier"] as? String, "$(WGJ_APP_GROUP_IDENTIFIER)")
        XCTAssertEqual(widgetInfo["WGJURLScheme"] as? String, "$(WGJ_URL_SCHEME)")
        XCTAssertEqual(debug["com.apple.developer.icloud-container-environment"] as? String, "Development")
        XCTAssertEqual(release["com.apple.developer.icloud-container-environment"] as? String, "Production")

        for setting in [
            "PRODUCT_BUNDLE_IDENTIFIER = se.highball.WeGoJim.dev;",
            "PRODUCT_BUNDLE_IDENTIFIER = se.highball.WeGoJim;",
            "PRODUCT_BUNDLE_IDENTIFIER = se.highball.WeGoJim.dev.WGJWidgetExtension;",
            "PRODUCT_BUNDLE_IDENTIFIER = se.highball.WeGoJim.WGJWidgetExtension;",
            "WGJ_APP_GROUP_IDENTIFIER = group.se.highball.WeGoJim.dev;",
            "WGJ_APP_GROUP_IDENTIFIER = group.se.highball.WeGoJim;",
            "WGJ_APP_ENVIRONMENT = development;",
            "WGJ_APP_ENVIRONMENT = production;",
            "WGJ_CLOUDKIT_CONTAINER_IDENTIFIER = iCloud.se.highball.WeGoJim.dev;",
            "WGJ_CLOUDKIT_CONTAINER_IDENTIFIER = iCloud.se.highball.WeGoJim;",
            "WGJ_URL_SCHEME = \"wgj-dev\";",
            "WGJ_URL_SCHEME = wgj;",
        ] {
            XCTAssertTrue(project.contains(setting), "Missing isolation setting: \(setting)")
        }

        XCTAssertTrue(developmentScheme.contains("buildConfiguration = \"Debug\""))
        XCTAssertTrue(productionScheme.contains("<LaunchAction\n      buildConfiguration = \"Release\""))
        XCTAssertEqual(developmentScheme.components(separatedBy: "buildForAnalyzing = \"YES\"").count - 1, 1)
        XCTAssertEqual(productionScheme.components(separatedBy: "buildForAnalyzing = \"YES\"").count - 1, 1)
        XCTAssertEqual(project.components(separatedBy: "MARKETING_VERSION = 1.4.0;").count - 1, 4)
    }

    private func propertyList(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }
}
