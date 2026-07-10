# Workout Runtime and Race Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give active workouts one process-wide owner, reject stale snapshot writes, and make scene, exercise replacement, avatar, and settings behavior latest-value deterministic.

**Architecture:** A `@MainActor` observable coordinator owns the authoritative active snapshot and accepts typed commands. An actor-isolated store persists revisioned envelopes and rejects stale writes. Independent latest-value coordinators use cancellation/generation or serialized revisioned patches rather than untracked tasks.

**Tech Stack:** SwiftUI, Observation, Swift Concurrency, SwiftData, Codable snapshots, XCTest, UIKit.

## Global Constraints

- Complete the idempotent completion task in `2026-07-10-data-integrity-persistence.md` before Task 3.
- The active workout remains local-first; snapshot saves never wait for CloudKit.
- The coordinator is process-wide but dependency-injected, not a test-leaking global singleton.
- Existing revision-less snapshot files decode as revision `0`.
- Ordinary set/value/notes edits preserve stable exercise and set identities.
- New files in synchronized source/test groups require no PBX project edits.
- Use the installed simulator `WGJ iPhone 14 iOS 26.2` for focused tests.

---

### Task 1: Version Snapshot Envelopes and Reject Stale Writes

**Files:**
- Modify: `WGJ/Services/ActiveWorkoutRuntime.swift:59-96,491-658`
- Test: `WGJTests/ActiveWorkoutRuntimeTests.swift`
- Test: `WGJTests/ActiveWorkoutSnapshotRevisionTests.swift`

**Interfaces:**
- Produces: `ActiveWorkoutSnapshotStoring`
- Produces: `ActiveWorkoutSnapshotWriteResult`
- Extends: `ActiveWorkoutStoredSnapshot.revision`

- [ ] **Step 1: Write backward-compatibility and stale-write tests**

```swift
func testRevisionlessSnapshotDecodesAsZero() throws {
    let data = try legacySnapshotJSONWithoutRevision()
    let decoded = try JSONDecoder().decode(ActiveWorkoutStoredSnapshot.self, from: data)
    XCTAssertEqual(decoded.revision, 0)
}

func testOlderRevisionCannotOverwriteNewerDiskSnapshot() async throws {
    let store = ActiveWorkoutSnapshotStore(baseDirectory: try makeTemporaryDirectory())
    let newer = makeStoredSnapshot(revision: 2, name: "New")
    let older = makeStoredSnapshot(revision: 1, name: "Old")

    XCTAssertEqual(try await store.save(newer), .written)
    XCTAssertEqual(try await store.save(older), .rejectedStale(currentRevision: 2))
    XCTAssertEqual(try await store.loadStoredSnapshot()?.session.name, "New")
}

func testEqualSnapshotReturnsUnchanged() async throws {
    let store = ActiveWorkoutSnapshotStore(baseDirectory: try makeTemporaryDirectory())
    let snapshot = makeStoredSnapshot(revision: 4, name: "Push")
    XCTAssertEqual(try await store.save(snapshot), .written)
    XCTAssertEqual(try await store.save(snapshot), .unchanged)
}
```

- [ ] **Step 2: Run revision tests and verify missing interface failure**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme 'WGJ Dev' -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/ActiveWorkoutSnapshotRevisionTests
```

Expected: compilation fails because the envelope has no revision/write result.

- [ ] **Step 3: Add revision and write-result interfaces**

```swift
nonisolated enum ActiveWorkoutSnapshotWriteResult: Equatable, Sendable {
    case written
    case unchanged
    case rejectedStale(currentRevision: UInt64)
}

protocol ActiveWorkoutSnapshotStoring: Sendable {
    func loadStoredSnapshot() async throws -> ActiveWorkoutStoredSnapshot?
    func save(_ snapshot: ActiveWorkoutStoredSnapshot) async throws -> ActiveWorkoutSnapshotWriteResult
    func delete() async throws
}
```

Add `var revision: UInt64` to `ActiveWorkoutStoredSnapshot`. Its custom decoder uses `decodeIfPresent(UInt64.self, forKey: .revision) ?? 0`; all existing convenience save overloads accept or preserve a revision explicitly.

- [ ] **Step 4: Enforce disk-aware monotonic writes**

Before writing, obtain the current envelope from the actor cache or disk. Return `.rejectedStale` for lower revision, `.unchanged` when both revision and encoded envelope match, and `.written` after atomic data replacement. A cold actor must compare against disk, not assume revision zero.

- [ ] **Step 5: Run snapshot and existing runtime tests**

Expected: revision tests and `ActiveWorkoutRuntimeTests` pass, including metadata-preserving saves.

- [ ] **Step 6: Commit the revisioned store**

```bash
git add WGJ/Services/ActiveWorkoutRuntime.swift WGJTests/ActiveWorkoutRuntimeTests.swift WGJTests/ActiveWorkoutSnapshotRevisionTests.swift
git commit -m "fix(workout): reject stale snapshot revisions"
```

### Task 2: Introduce the Process-Wide Active Workout Coordinator

**Files:**
- Create: `WGJ/Services/ActiveWorkoutCoordinator.swift`
- Create: `WGJTests/ActiveWorkoutCoordinatorTests.swift`
- Modify: `WGJ/Services/ActiveWorkoutRuntime.swift:1350-1382`
- Modify: `WGJ/Services/AppLaunchBootstrap.swift:16-19`
- Modify: `WGJ/WGJApp.swift:8-27`

**Interfaces:**
- Consumes: `ActiveWorkoutSnapshotStoring` from Task 1.
- Produces: `ActiveWorkoutCommand`, `ActiveWorkoutMutationReceipt`, `ActiveWorkoutPersistence`, and `ActiveWorkoutCoordinator`.

- [ ] **Step 1: Write mutation interleaving and coalescing tests**

Use a recording snapshot-store actor. Start a session, update metadata, set drafts, minimize presentation, and append a catalog exercise. Assert the final in-memory and flushed disk envelope contains every mutation and a strictly increasing revision. Fire ten rapid commands and assert `flushSnapshot()` writes the latest revision while concurrent writes never exceed one.

- [ ] **Step 2: Run coordinator tests and verify missing type failure**

Expected: compilation fails.

- [ ] **Step 3: Define typed commands and receipts**

```swift
nonisolated enum ActiveWorkoutCommand: Sendable {
    case start(ActiveWorkoutRuntimeSession)
    case updateMetadata(name: String, notes: String)
    case upsertCardio(ActiveWorkoutRuntimeCardioBlock)
    case removeCardio(WorkoutCardioPhase)
    case setCardioCompleted(phase: WorkoutCardioPhase, isCompleted: Bool)
    case appendExercise(ActiveWorkoutRuntimeExercise)
    case replaceExercise(exerciseID: UUID, replacement: ActiveWorkoutRuntimeExercise)
    case removeExercise(UUID)
    case moveExercise(exerciseID: UUID, destinationIndex: Int)
    case setExerciseDrafts(exerciseID: UUID, drafts: [WorkoutSessionSetDraft])
    case setExerciseRest(exerciseID: UUID, seconds: Int)
    case setExerciseNotes(exerciseID: UUID, notes: String)
    case updateExerciseSettings(exerciseID: UUID, minReps: Int?, maxReps: Int?, restSeconds: Int)
    case selectExerciseComponent(exerciseID: UUID, componentID: UUID)
    case updatePresentation(mode: ActiveWorkoutStoredPresentationMode, scrollTarget: ActiveWorkoutScrollTarget?, expandedExerciseIDs: Set<UUID>)
    case updateRestTimer(RestTimerSnapshot?)
}

nonisolated struct ActiveWorkoutMutationReceipt: Equatable, Sendable {
    let revision: UInt64
    let session: ActiveWorkoutRuntimeSession
}

@MainActor
protocol ActiveWorkoutCommandHandling: AnyObject {
    @discardableResult
    func send(_ command: ActiveWorkoutCommand) -> ActiveWorkoutMutationReceipt
}
```

- [ ] **Step 4: Implement command application and coalesced persistence**

```swift
@MainActor
@Observable
final class ActiveWorkoutCoordinator: ActiveWorkoutCommandHandling {
    private(set) var storedSnapshot: ActiveWorkoutStoredSnapshot?
    private(set) var persistenceWarning: String?
    @ObservationIgnored private let snapshotStore: any ActiveWorkoutSnapshotStoring
    @ObservationIgnored private let persistence: any ActiveWorkoutPersistence
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var completionTask: Task<WorkoutCompletionCommitResult, Error>?

    @discardableResult
    func send(_ command: ActiveWorkoutCommand) -> ActiveWorkoutMutationReceipt {
        var snapshot = requireSnapshot(for: command)
        apply(command, to: &snapshot)
        snapshot.revision &+= 1
        storedSnapshot = snapshot
        scheduleSnapshotSave(snapshot)
        return ActiveWorkoutMutationReceipt(revision: snapshot.revision, session: snapshot.session)
    }

    func flushSnapshot() async {
        saveTask?.cancel()
        saveTask = nil
        guard let snapshot = storedSnapshot else { return }
        await persist(snapshot)
    }
}
```

`scheduleSnapshotSave` coalesces on revision and passes a captured Sendable envelope to the actor. A stale rejection is expected cleanup, not a user-visible failure. Real I/O failure sets `persistenceWarning` while preserving in-memory state.

- [ ] **Step 5: Inject one coordinator from the app root**

Create it beside the resolved bootstrap, using that bootstrap’s container-backed `ActiveWorkoutPersistence`. Inject it with `.environment(coordinator)` into `ContentView`; tests construct fresh coordinators. Delete the unused `ActiveWorkoutRuntimeController` rather than keeping two owners.

- [ ] **Step 6: Run coordinator tests**

Expected: interleaved commands retain all fields, revisions are monotonic, and the final flush persists the latest envelope.

- [ ] **Step 7: Commit coordinator ownership**

```bash
git add WGJ/Services/ActiveWorkoutCoordinator.swift WGJ/Services/ActiveWorkoutRuntime.swift WGJ/Services/AppLaunchBootstrap.swift WGJ/WGJApp.swift WGJTests/ActiveWorkoutCoordinatorTests.swift
git commit -m "refactor(workout): centralize active session ownership"
```

### Task 3: Route Every Active Snapshot Caller Through the Coordinator

**Files:**
- Modify: `WGJ/Views/Workout/StartWorkoutHomeView.swift:674-719`
- Modify: `WGJ/Views/Exercises/ExercisesCatalogView.swift:895-1005`
- Modify: `WGJ/Views/Workout/ActiveWorkoutStripView.swift:71-98`
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift:902-945,1933-1953,2088-2124,2527-2629,2717-2784`
- Modify: `WGJ/ContentView.swift:387-397`
- Modify: `WGJ/Models/AppRuntimeConfig.swift:796-1055`
- Test: `WGJTests/ActiveWorkoutCoordinatorTests.swift`

**Interfaces:**
- Consumes: coordinator and idempotent `WorkoutCompletionRepository`.
- Produces: no new store writer outside `ActiveWorkoutCoordinator`.

- [ ] **Step 1: Add a source-boundary regression test**

Read the caller source files and assert none contains `ActiveWorkoutSnapshotStore.shared.save`, `.loadStoredSnapshot`, or `.loadDiscardingCorruptSnapshot`. Allow direct store construction only in `ActiveWorkoutRuntime.swift` and tests.

- [ ] **Step 2: Make startup restore completion-aware**

`ActiveWorkoutCoordinator.restore()` loads one envelope, asks `ActiveWorkoutPersistence.isCompleted(sessionID:)`, and deletes/ignores a completed snapshot. Otherwise it publishes the loaded envelope unchanged. A failed delete records a retry warning but never exposes a completed workout as active.

- [ ] **Step 3: Move start, catalog, strip, and active-view operations**

- Start Workout sends `.start` and presents the coordinator snapshot.
- Catalog sends `.appendExercise` or `.replaceExercise`; it never loads disk first.
- Active strip observes `coordinator.storedSnapshot`.
- Active Workout sends metadata, drafts, cardio, rest, component, ordering, and presentation commands and reads coordinator state.
- Content startup calls `restore()` once.
- `ActiveWorkoutPresentationState` retains only navigation/presentation metadata and deletes its hidden runtime-session cache.

- [ ] **Step 4: Make completion share one in-flight operation**

`complete(notes:)` returns the existing `completionTask` when present, calls idempotent persistence once, clears in-memory active state after commit, then best-effort deletes the snapshot. Completion success remains success if deletion fails.

- [ ] **Step 5: Run source-boundary, coordinator, runtime, and completion tests**

Expected: no direct store caller remains, completed stale snapshots never publish, and all active flows pass.

- [ ] **Step 6: Commit caller migration**

```bash
git add WGJ/ContentView.swift WGJ/Models/AppRuntimeConfig.swift WGJ/Views/Exercises/ExercisesCatalogView.swift WGJ/Views/Workout/StartWorkoutHomeView.swift WGJ/Views/Workout/ActiveWorkoutStripView.swift WGJ/Views/Workout/ActiveWorkoutView.swift WGJTests/ActiveWorkoutCoordinatorTests.swift
git commit -m "fix(workout): serialize active snapshot mutations"
```

### Task 4: Disable Divergent Scenes and Centralize Idle-Timer Policy

**Files:**
- Modify: `WGJ-App-Info.plist:77-83`
- Create: `WGJ/Services/WorkoutIdleTimerController.swift`
- Modify: `WGJ/ContentView.swift:63-107,732-738`
- Modify: `WGJ/Views/Profile/SettingsView.swift:96-103`
- Test: `WGJTests/SceneOwnershipTests.swift`

**Interfaces:**
- Produces: `WorkoutIdleTimerPolicy` and controller.

- [ ] **Step 1: Write plist and truth-table tests**

```swift
func testAppDisablesMultipleScenes() throws {
    let plist = try loadAppInfoPlist()
    let manifest = try XCTUnwrap(plist["UIApplicationSceneManifest"] as? [String: Any])
    XCTAssertEqual(manifest["UIApplicationSupportsMultipleScenes"] as? Bool, false)
}

func testIdleTimerRequiresActiveScenePreferenceAndWorkout() {
    XCTAssertTrue(WorkoutIdleTimerPolicy.shouldDisableIdleTimer(isSceneActive: true, keepsScreenAwake: true, hasActiveWorkout: true))
    XCTAssertFalse(WorkoutIdleTimerPolicy.shouldDisableIdleTimer(isSceneActive: false, keepsScreenAwake: true, hasActiveWorkout: true))
    XCTAssertFalse(WorkoutIdleTimerPolicy.shouldDisableIdleTimer(isSceneActive: true, keepsScreenAwake: true, hasActiveWorkout: false))
}
```

- [ ] **Step 2: Run tests and verify current plist failure**

Expected: multiple-scenes assertion fails and controller type is missing.

- [ ] **Step 3: Implement effective-value controller**

```swift
nonisolated enum WorkoutIdleTimerPolicy {
    static func shouldDisableIdleTimer(isSceneActive: Bool, keepsScreenAwake: Bool, hasActiveWorkout: Bool) -> Bool {
        isSceneActive && keepsScreenAwake && hasActiveWorkout
    }
}

@MainActor
final class WorkoutIdleTimerController {
    private let setDisabled: (Bool) -> Void
    private var current = false

    init(setDisabled: @escaping (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }) {
        self.setDisabled = setDisabled
    }

    func update(isSceneActive: Bool, keepsScreenAwake: Bool, hasActiveWorkout: Bool) {
        let next = WorkoutIdleTimerPolicy.shouldDisableIdleTimer(isSceneActive: isSceneActive, keepsScreenAwake: keepsScreenAwake, hasActiveWorkout: hasActiveWorkout)
        guard next != current else { return }
        current = next
        setDisabled(next)
    }

    func reset() { if current { current = false; setDisabled(false) } }
}
```

- [ ] **Step 4: Set one scene and feed coordinator state**

Set `UIApplicationSupportsMultipleScenes` false. `ContentView` updates the controller from scene activity, preference, and `coordinator.storedSnapshot != nil`. Minimize remains active; completion/discard clears it. Update settings copy to “while a workout is active.”

- [ ] **Step 5: Run scene tests and simulator build**

Expected: start→minimize→complete setter sequence is `[true, false]` with no redundant writes.

- [ ] **Step 6: Commit scene safety**

```bash
git add WGJ-App-Info.plist WGJ/Services/WorkoutIdleTimerController.swift WGJ/ContentView.swift WGJ/Views/Profile/SettingsView.swift WGJTests/SceneOwnershipTests.swift
git commit -m "fix(app): align scene and idle timer ownership"
```

### Task 5: Reset Stateful Exercise Rows on Catalog Replacement

**Files:**
- Modify: `WGJ/Views/Workout/WorkoutExerciseRowHostView.swift:48-154`
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift:585-696,1346-1388`
- Test: `WGJTests/ActiveWorkoutRuntimeTests.swift`

**Interfaces:**
- Produces: `WorkoutExerciseRowContentIdentity`.

- [ ] **Step 1: Write identity tests**

```swift
func testRowContentIdentityChangesOnlyWhenCatalogExerciseChanges() {
    let runtimeID = UUID()
    let first = WorkoutExerciseRowContentIdentity(runtimeExerciseID: runtimeID, catalogExerciseUUID: "bench")
    let valueEdit = WorkoutExerciseRowContentIdentity(runtimeExerciseID: runtimeID, catalogExerciseUUID: "bench")
    let replacement = WorkoutExerciseRowContentIdentity(runtimeExerciseID: runtimeID, catalogExerciseUUID: "incline")
    XCTAssertEqual(first, valueEdit)
    XCTAssertNotEqual(first, replacement)
}
```

Add a callback test whose A coordinator is replaced by B and assert set completion emits B’s exercise name/rest metadata.

- [ ] **Step 2: Run tests and verify missing identity failure**

- [ ] **Step 3: Add nested content identity**

```swift
nonisolated struct WorkoutExerciseRowContentIdentity: Hashable, Sendable {
    let runtimeExerciseID: UUID
    let catalogExerciseUUID: String

    init(exercise: ActiveWorkoutRuntimeExercise) {
        runtimeExerciseID = exercise.id
        catalogExerciseUUID = exercise.catalogExerciseUUID
    }
}
```

Apply `.id(WorkoutExerciseRowContentIdentity(exercise: exercise))` to the stateful host inside the existing outer scroll-target identity. Include it in equatable row content.

- [ ] **Step 4: Flush old state before replacement**

Dismiss metric focus, synchronously commit the draft buffer, cancel old row tasks, then send `.replaceExercise`. Ordinary edits leave content identity unchanged.

- [ ] **Step 5: Run runtime tests**

Expected: replacement metadata is B; ordinary edits preserve row state and scroll anchor.

- [ ] **Step 6: Commit replacement identity**

```bash
git add WGJ/Views/Workout/WorkoutExerciseRowHostView.swift WGJ/Views/Workout/ActiveWorkoutView.swift WGJTests/ActiveWorkoutRuntimeTests.swift
git commit -m "fix(workout): refresh row state after replacement"
```

### Task 6: Make Avatar Selection Latest-Value

**Files:**
- Create: `WGJ/Services/AvatarSelectionCoordinator.swift`
- Modify: `WGJ/Views/Profile/ProfileManagementView.swift:15-18,72-78,153-159,264-298`
- Test: `WGJTests/AvatarSelectionCoordinatorTests.swift`

**Interfaces:**
- Produces: `AvatarSelectionCoordinator`.

- [ ] **Step 1: Write delayed A/B, removal, and cancellation tests**

Hold selection A behind a continuation, complete B, then release A and assert B remains. Hold A, call `remove()`, release A and assert nil. Cancel during a delayed load and assert no late publication.

- [ ] **Step 2: Run tests and verify missing coordinator failure**

- [ ] **Step 3: Implement cancellation plus generation**

```swift
@MainActor
@Observable
final class AvatarSelectionCoordinator {
    private(set) var imageData: Data?
    private(set) var isLoading = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private let transform: @Sendable (Data) async -> Data?

    func select(load: @escaping @Sendable () async throws -> Data?) {
        loadTask?.cancel(); generation &+= 1
        let expected = generation
        isLoading = true
        loadTask = Task { [weak self] in
            guard let raw = try? await load(), !Task.isCancelled else { return }
            let transformed = await self?.transform(raw) ?? raw
            guard let self, self.generation == expected, !Task.isCancelled else { return }
            self.imageData = transformed
            self.isLoading = false
            self.loadTask = nil
        }
    }

    func remove() { loadTask?.cancel(); generation &+= 1; loadTask = nil; isLoading = false; imageData = nil }
    func cancel() { loadTask?.cancel(); generation &+= 1; loadTask = nil; isLoading = false }
}
```

Provide a complete initializer and `reset(to:)`; the live transform uses `AvatarImageCodec.compressedAvatarData` with 640 pixels.

- [ ] **Step 4: Bind `ProfileManagementView` to the coordinator**

PhotosPicker calls `select { try await item.loadTransferable(type: Data.self) }`; remove calls coordinator.remove; disappearance calls cancel. Saving reads coordinator.imageData.

- [ ] **Step 5: Run avatar and profile build tests**

Expected: latest selection/removal always wins.

- [ ] **Step 6: Commit avatar ordering**

```bash
git add WGJ/Services/AvatarSelectionCoordinator.swift WGJ/Views/Profile/ProfileManagementView.swift WGJTests/AvatarSelectionCoordinatorTests.swift
git commit -m "fix(profile): keep latest avatar selection"
```

### Task 7: Serialize Settings Patches and Side Effects

**Files:**
- Create: `WGJ/Services/SettingsPersistenceCoordinator.swift`
- Modify: `WGJ/Views/Profile/SettingsView.swift:10-25,254-283,317-478`
- Modify: `WGJ/Services/ProfileRepository.swift:129-163`
- Test: `WGJTests/SettingsPersistenceCoordinatorTests.swift`

**Interfaces:**
- Produces: `UserSettingsDraft`, `UserSettingsPatch`, `RevisionedSettingsWrite`, `OrderedSettingsWriter`, and `SettingsDraftCoordinator`.

- [ ] **Step 1: Write out-of-order and patch-isolation tests**

Delay revision 1, submit revision 2, release 1, and assert the persisted/reloaded value is revision 2. Assert rapid false→true→false ends false, old commits cannot apply runtime side effects, feedback cancellation does not cancel a durable write, and an unrelated toggle patch does not persist an unsaved weekly-goal draft.

- [ ] **Step 2: Run the new test class and confirm missing interfaces**

- [ ] **Step 3: Add patch and persisted-draft types**

```swift
nonisolated struct UserSettingsPatch: Equatable, Sendable {
    var weeklyWorkoutGoal: Int?
    var isTrainingGuidanceEnabled: Bool?
    var keepsScreenAwake: Bool?
    var preferredWeightUnit: PreferredWeightUnit?
    var workoutNotificationStyle: WorkoutNotificationStyle?

    mutating func merge(_ newer: UserSettingsPatch) {
        if let value = newer.weeklyWorkoutGoal { weeklyWorkoutGoal = value }
        if let value = newer.isTrainingGuidanceEnabled { isTrainingGuidanceEnabled = value }
        if let value = newer.keepsScreenAwake { keepsScreenAwake = value }
        if let value = newer.preferredWeightUnit { preferredWeightUnit = value }
        if let value = newer.workoutNotificationStyle { workoutNotificationStyle = value }
    }
}

nonisolated struct RevisionedSettingsWrite: Equatable, Sendable {
    let revision: UInt64
    let patch: UserSettingsPatch
}
```

Implement `ProfileRepository.applySettingsPatch(_:)` so one context save returns a complete `UserSettingsDraft`.

- [ ] **Step 4: Implement serialized writer**

The actor merges pending patches, never runs more than one persist closure, and applies commit/failure callbacks only when the completed revision equals `newestSubmittedRevision`. `flush()` waits until no active/pending write remains; `retryLatest()` resubmits the last failed patch.

- [ ] **Step 5: Replace detached tasks in Settings**

`SettingsDraftCoordinator` owns draft, revision, error, and feedback. View controls bind to its draft and submit one-field patches. Weekly goal remains explicit-save only. Runtime-state invalidation, idle preference, widget, and notification side effects receive the same committed revision.

- [ ] **Step 6: Run settings tests and relaunch persistence smoke test**

Expected: last visible value is last persisted value after `flush()` and reload.

- [ ] **Step 7: Commit settings serialization**

```bash
git add WGJ/Services/SettingsPersistenceCoordinator.swift WGJ/Services/ProfileRepository.swift WGJ/Views/Profile/SettingsView.swift WGJTests/SettingsPersistenceCoordinatorTests.swift
git commit -m "fix(settings): serialize preference writes"
```

### Task 8: Verify Runtime and Race Workstream

**Files:**
- Verify only: all Task 1-7 files.

**Interfaces:**
- Verifies all runtime ownership contracts.

- [ ] **Step 1: Run focused runtime classes**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme 'WGJ Dev' -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/ActiveWorkoutSnapshotRevisionTests -only-testing:WGJTests/ActiveWorkoutCoordinatorTests -only-testing:WGJTests/ActiveWorkoutRuntimeTests -only-testing:WGJTests/SceneOwnershipTests -only-testing:WGJTests/AvatarSelectionCoordinatorTests -only-testing:WGJTests/SettingsPersistenceCoordinatorTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Confirm there is one active snapshot writer**

```bash
rg -n 'ActiveWorkoutSnapshotStore\.shared\.(save|load|loadStoredSnapshot|loadDiscardingCorruptSnapshot)' WGJ --glob '*.swift'
```

Expected: application-level direct calls exist only inside coordinator/store composition, never feature views.

- [ ] **Step 3: Build for testing**

```bash
xcodebuild build-for-testing -project WGJ.xcodeproj -scheme 'WGJ Dev' -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/WGJRuntimeBuild CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 4: Run race tests three times**

Run coordinator, avatar, and settings test classes with `-test-iterations 3` and sequential testing.

Expected: all iterations pass with no timing-dependent failure.

- [ ] **Step 5: Commit only if verification needs corrections**

```bash
git add WGJ WGJTests WGJ-App-Info.plist
git commit -m "test(runtime): cover latest-value coordination"
```

Skip when no corrections are required.
