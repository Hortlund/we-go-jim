import ImageIO
import XCTest
@testable import WGJ

final class AppCapabilityConfigurationTests: XCTestCase {
    func testLaunchScreenAndSplashAssetsUseProductionConfiguration() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let info = try propertyList(at: repository.appendingPathComponent("WGJ-App-Info.plist"))
        let launchScreen = try XCTUnwrap(info["UILaunchScreen"] as? [String: Any])
        XCTAssertEqual(launchScreen["UIColorName"] as? String, "LaunchBackground")
        XCTAssertNil(launchScreen["UILaunchScreen"])

        let imageDirectory = repository.appendingPathComponent(
            "WGJ/Assets.xcassets/SplashIcon.imageset",
            isDirectory: true
        )
        let expectedPixelsByFilename = [
            "SplashIcon.png": 176,
            "SplashIcon@2x.png": 352,
            "SplashIcon@3x.png": 528,
        ]
        for (filename, expectedPixels) in expectedPixelsByFilename {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(
                imageDirectory.appendingPathComponent(filename) as CFURL,
                nil
            ))
            let properties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            )
            XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, expectedPixels, filename)
            XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, expectedPixels, filename)
        }

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repository
                .appendingPathComponent("WGJ/Assets.xcassets/LaunchBackground.colorset/Contents.json")
                .path
        ))
    }

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
        XCTAssertEqual(
            info["NSPhotoLibraryAddUsageDescription"] as? String,
            "Save workout images to your photo library."
        )
        XCTAssertNil(info["NSPhotoLibraryUsageDescription"])
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
        let releaseLikeProject = try String(
            contentsOf: repository.appendingPathComponent("Configuration/Project-ReleaseLike.xcconfig"),
            encoding: .utf8
        )
        let releaseLikeApp = try String(
            contentsOf: repository.appendingPathComponent("Configuration/WGJ-App-ReleaseLike.xcconfig"),
            encoding: .utf8
        )
        let releaseLikeWidget = try String(
            contentsOf: repository.appendingPathComponent("Configuration/WGJ-Widget-ReleaseLike.xcconfig"),
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

        let developmentLaunchAction = try XCTUnwrap(
            developmentScheme
                .components(separatedBy: "<LaunchAction")
                .dropFirst()
                .first?
                .components(separatedBy: "</LaunchAction>")
                .first
        )
        XCTAssertTrue(developmentScheme.contains("<TestAction\n      buildConfiguration = \"Debug\""))
        XCTAssertTrue(developmentLaunchAction.contains("buildConfiguration = \"Dev Preview\""))
        XCTAssertTrue(developmentLaunchAction.contains(
            "selectedDebuggerIdentifier = \"Xcode.DebuggerFoundation.Debugger.LLDB\""
        ))
        XCTAssertTrue(developmentLaunchAction.contains(
            "selectedLauncherIdentifier = \"Xcode.DebuggerFoundation.Launcher.LLDB\""
        ))
        XCTAssertTrue(developmentScheme.contains("<ProfileAction\n      buildConfiguration = \"Dev Preview\""))
        XCTAssertTrue(developmentScheme.contains("<ArchiveAction\n      buildConfiguration = \"Dev Preview\""))
        XCTAssertFalse(developmentScheme.contains("DEV_SEED_DEMO_DATA"))
        XCTAssertTrue(productionScheme.contains("<LaunchAction\n      buildConfiguration = \"Release\""))
        XCTAssertEqual(developmentScheme.components(separatedBy: "buildForAnalyzing = \"YES\"").count - 1, 1)
        XCTAssertEqual(productionScheme.components(separatedBy: "buildForAnalyzing = \"YES\"").count - 1, 1)
        XCTAssertEqual(project.components(separatedBy: "name = \"Dev Preview\";").count - 1, 5)
        XCTAssertEqual(
            project.components(separatedBy: "baseConfigurationReference = A20000000000000000000001").count - 1,
            2
        )
        XCTAssertEqual(
            project.components(separatedBy: "baseConfigurationReference = A20000000000000000000002").count - 1,
            2
        )
        XCTAssertEqual(
            project.components(separatedBy: "baseConfigurationReference = A20000000000000000000003").count - 1,
            2
        )
        XCTAssertTrue(releaseLikeProject.contains("SWIFT_OPTIMIZATION_LEVEL = -O"))
        XCTAssertTrue(releaseLikeProject.contains("SWIFT_COMPILATION_MODE = wholemodule"))
        XCTAssertTrue(releaseLikeProject.contains("ENABLE_NS_ASSERTIONS = NO"))
        XCTAssertTrue(releaseLikeProject.contains("VALIDATE_PRODUCT = YES"))
        XCTAssertTrue(releaseLikeApp.contains("MARKETING_VERSION = 1.4.2"))
        XCTAssertTrue(releaseLikeWidget.contains("MARKETING_VERSION = 1.4.2"))
    }

    private func propertyList(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }
}
