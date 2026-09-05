import XCTest
@testable import WGJ

final class SceneOwnershipTests: XCTestCase {
    private enum ReleaseContext {
        @TaskLocal static var isReleasingState = false
    }

    @MainActor
    func testStateObjectsReleaseSynchronouslyInsideTaskLocalScope() {
        weak var releasedRuntime: AppRuntimeState?
        weak var releasedFileOpenState: TemplateFileOpenState?
        ReleaseContext.$isReleasingState.withValue(true) {
            let runtime = AppRuntimeState.makeTestingInstance()
            let fileOpenState = TemplateFileOpenState()
            releasedRuntime = runtime
            releasedFileOpenState = fileOpenState
            XCTAssertNotNil(releasedRuntime)
            XCTAssertNotNil(releasedFileOpenState)
            assertSynchronousRelease(WorkoutCompletionPresentationState())
            assertSynchronousRelease(ActiveWorkoutPresentationState())
            assertSynchronousRelease(RestTimerState())
            assertSynchronousRelease(CatalogSyncCoordinator())
            assertSynchronousRelease(AppDeferredMaintenanceState())
            assertSynchronousRelease(AppWarmupState())
        }
        XCTAssertNil(releasedRuntime)
        XCTAssertNil(releasedFileOpenState)
    }

    @MainActor
    private func assertSynchronousRelease<T: AnyObject>(_ makeObject: @autoclosure () -> T) {
        weak var releasedObject: T?
        do {
            let object = makeObject()
            releasedObject = object
            XCTAssertNotNil(releasedObject)
        }
        XCTAssertNil(releasedObject)
    }

    func testAppDisablesMultipleScenes() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("WGJ-App-Info.plist"))
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let manifest = try XCTUnwrap(plist["UIApplicationSceneManifest"] as? [String: Any])

        XCTAssertEqual(manifest["UIApplicationSupportsMultipleScenes"] as? Bool, false)
    }

    func testIdleTimerRequiresActiveScenePreferenceAndWorkout() {
        XCTAssertTrue(WorkoutIdleTimerPolicy.shouldDisableIdleTimer(
            isSceneActive: true,
            keepsScreenAwake: true,
            hasActiveWorkout: true
        ))
        XCTAssertFalse(WorkoutIdleTimerPolicy.shouldDisableIdleTimer(
            isSceneActive: false,
            keepsScreenAwake: true,
            hasActiveWorkout: true
        ))
        XCTAssertFalse(WorkoutIdleTimerPolicy.shouldDisableIdleTimer(
            isSceneActive: true,
            keepsScreenAwake: true,
            hasActiveWorkout: false
        ))
    }

    @MainActor
    func testIdleTimerControllerWritesOnlyEffectiveTransitions() {
        let recorder = IdleTimerValueRecorder()
        let controller = WorkoutIdleTimerController { recorder.record($0) }

        controller.update(isSceneActive: true, keepsScreenAwake: true, hasActiveWorkout: true)
        controller.update(isSceneActive: true, keepsScreenAwake: true, hasActiveWorkout: true)
        controller.update(isSceneActive: true, keepsScreenAwake: true, hasActiveWorkout: true)
        controller.update(isSceneActive: true, keepsScreenAwake: true, hasActiveWorkout: false)

        XCTAssertEqual(recorder.values, [true, false])
    }
}

@MainActor
private final class IdleTimerValueRecorder {
    private(set) var values: [Bool] = []

    func record(_ value: Bool) {
        values.append(value)
    }
}
