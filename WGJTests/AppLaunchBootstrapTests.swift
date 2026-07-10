import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class AppLaunchBootstrapTests: XCTestCase {
    private enum TestError: Error {
        case storeOpen
    }

    func testPersistentStoreFailureShowsRecoveryInsteadOfReadyContent() async {
        let state = makeState()

        state.resolveIfNeeded(resolver: { throw TestError.storeOpen })
        await waitUntil { state.recoveryState != nil }

        XCTAssertNil(state.resolvedBootstrap)
        XCTAssertEqual(state.recoveryState?.canMutateUserData, false)
    }

    func testRetryCanResolveDurableStore() async throws {
        let state = makeState()
        state.resolveIfNeeded(resolver: { throw TestError.storeOpen })
        await waitUntil { state.recoveryState != nil }
        let schema = Schema([UserProfile.self])
        let configuration = ModelConfiguration(
            "LaunchTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])

        state.retry(resolver: {
            ModelContainerBootstrap(
                container: container,
                cloudRuntimeMode: .unavailable("Unit test"),
                cloudFeaturesEnabled: false,
                userDataSyncEnabled: false,
                cloudSyncEnabled: false,
                cloudSyncErrorDescription: nil,
                persistenceMode: .durable
            )
        })
        await waitUntil { state.resolvedBootstrap != nil }

        XCTAssertEqual(state.resolvedBootstrap?.bootstrap.persistenceMode, .durable)
        XCTAssertNil(state.recoveryState)
    }

    func testDiagnosticModeIsExplicitAndReadOnly() async throws {
        let state = makeState()
        state.resolveIfNeeded(resolver: { throw TestError.storeOpen })
        await waitUntil { state.recoveryState != nil }
        let schema = Schema([UserProfile.self])
        let configuration = ModelConfiguration(
            "DiagnosticTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])

        state.enterDiagnosticMode { reason in
            ModelContainerBootstrap(
                container: container,
                cloudRuntimeMode: .unavailable(reason),
                cloudFeaturesEnabled: false,
                userDataSyncEnabled: false,
                cloudSyncEnabled: false,
                cloudSyncErrorDescription: reason,
                persistenceMode: .volatileDiagnostic(reason: reason)
            )
        }
        await waitUntil { state.resolvedBootstrap != nil }

        XCTAssertFalse(state.resolvedBootstrap?.bootstrap.persistenceMode.canMutateUserData ?? true)
        XCTAssertNil(state.recoveryState)
    }

    func testAppDoesNotAutomaticallyEnterEmergencyInMemoryMode() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("WGJ/WGJApp.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(appSource.contains("failureFallback:"))
        XCTAssertTrue(appSource.contains("launchBootstrapState.recoveryState"))
        XCTAssertTrue(appSource.contains("AppStorageRecoveryView("))
    }

    func testSuccessfulResolutionPublishesThroughInjectedRuntimeBoundary() async throws {
        var publishedModes: [AppPersistenceMode] = []
        let state = AppLaunchBootstrapState { bootstrap in
            publishedModes.append(bootstrap.persistenceMode)
        }
        let schema = Schema([UserProfile.self])
        let configuration = ModelConfiguration(
            "RuntimeBoundaryTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])

        state.resolveIfNeeded {
            ModelContainerBootstrap(
                container: container,
                cloudRuntimeMode: .unavailable("Unit test"),
                cloudFeaturesEnabled: false,
                userDataSyncEnabled: false,
                cloudSyncEnabled: false,
                cloudSyncErrorDescription: nil
            )
        }
        await waitUntil { state.resolvedBootstrap != nil }

        XCTAssertEqual(publishedModes, [.durable])
    }

    private func makeState() -> AppLaunchBootstrapState {
        AppLaunchBootstrapState(runtimeStateUpdater: { _ in })
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if predicate() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition did not become true within one second")
    }
}
