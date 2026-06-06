import Foundation
import Testing

struct ReleaseSchemeTests {
    @Test
    func releaseRunSchemeSuppressesXcodeOSActivityNoise() throws {
        let scheme = try String(contentsOf: releaseSchemeURL(), encoding: .utf8)
        let launchAction = try #require(xmlElement(named: "LaunchAction", in: scheme))

        #expect(launchAction.contains(#"buildConfiguration = "Release""#))
        #expect(launchAction.contains(#"key = "OS_ACTIVITY_MODE""#))
        #expect(launchAction.contains(#"value = "disable""#))
        #expect(launchAction.contains(#"isEnabled = "YES""#))
    }

    private func releaseSchemeURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ.xcodeproj/xcshareddata/xcschemes/WGJ.xcscheme")
    }

    private func xmlElement(named name: String, in source: String) -> String? {
        guard
            let start = source.range(of: "<\(name)"),
            let end = source.range(of: "</\(name)>", range: start.lowerBound..<source.endIndex)
        else {
            return nil
        }

        return String(source[start.lowerBound..<end.upperBound])
    }
}
