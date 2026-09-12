import Observation
import SwiftUI
import UIKit
import XCTest
@testable import WGJ

@MainActor
final class ActivityShareSheetTests: XCTestCase {
    func testActivityCompletionDismissesSwiftUISheetForEveryOutcome() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let state = ActivityShareTestState()
        let host = UIHostingController(rootView: ActivityShareTestHost(state: state))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKeyAndVisible()
        }

        let outcomes: [(completed: Bool, error: Error?)] = [
            (true, nil),
            (false, nil),
            (false, NSError(domain: "ActivityShareTest", code: 1)),
        ]
        for (index, outcome) in outcomes.enumerated() {
            state.isPresented = true
            let didPresent = await waitUntil { self.activityController(in: host) != nil }
            XCTAssertTrue(didPresent)
            let activity = try XCTUnwrap(activityController(in: host))
            let completion = try XCTUnwrap(activity.completionWithItemsHandler)
            // Exercise the real UIKit bridge callback without sending to another
            // app. UIKit cannot update this SwiftUI binding on its own here.
            completion(.copyToPasteboard, outcome.completed, nil, outcome.error)
            let didDismiss = await waitUntil {
                !state.isPresented && host.presentedViewController == nil
            }
            XCTAssertTrue(didDismiss, "Outcome \(index) left the SwiftUI share sheet presented")
            XCTAssertEqual(state.completionCount, index + 1)
        }
    }

    private func activityController(in controller: UIViewController) -> UIActivityViewController? {
        if let activity = controller as? UIActivityViewController { return activity }
        if let presented = controller.presentedViewController,
           let activity = activityController(in: presented) {
            return activity
        }
        for child in controller.children {
            if let activity = activityController(in: child) { return activity }
        }
        return nil
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(6)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

@MainActor
@Observable
private final class ActivityShareTestState {
    var isPresented = false
    var completionCount = 0
}

private struct ActivityShareTestHost: View {
    @Bindable var state: ActivityShareTestState

    var body: some View {
        Text("Workout preview")
            .sheet(isPresented: $state.isPresented) {
                WGJActivityShareSheet(activityItems: ["Workout test fixture"]) {
                    state.completionCount += 1
                }
            }
    }
}
