# Data Integrity and Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make restore, launch storage, workout completion, history editing, and template saving atomic, durable, idempotent, and explicit about failure.

**Architecture:** Destructive restore work is staged in one unsaved `ModelContext` and committed once. App launch exposes durable versus diagnostic persistence as typed state. Completion and history changes become repository/service commands with one commit followed by post-commit notifications and best-effort backup.

**Tech Stack:** Swift 5 transitioning to Swift 6, SwiftUI, SwiftData, XCTest, CloudKit, Observation, Xcode 26.5.

## Global Constraints

- The deployment target remains iOS 17 or newer.
- Active workout progress and template edits remain local-first.
- CloudKit work must not run during typing, scrolling, set completion, or other interaction paths.
- A successful local save is never rolled back because an asynchronous Cloud backup failed.
- Existing user data remains readable; this plan adds no SwiftData schema migration.
- SwiftUI views contain presentation only; persistence and business rules stay in repositories and services.
- New files under the synchronized `WGJ`, `WGJTests`, and `WGJUITests` groups require no manual PBX file entries.
- Simulator test commands use the installed iPhone 15 Pro / iOS 17.5 destination `8624785A-FA03-43D6-A624-4192C8738D6A`.

---

### Task 1: Stage Local Database Deletion Without Saving

**Files:**
- Modify: `WGJ/Services/AppDataDeletionService.swift:37-112`
- Test: `WGJTests/UserDataCloudBackupServiceTests.swift`

**Interfaces:**
- Produces: `func stageLocalDataDeletion() throws`
- Produces: `func clearLocalArtifacts() async throws`
- Produces: `static func removeExerciseImageCacheDirectory()`
- Preserves: `func deleteLocalDeviceData() async throws`

- [ ] **Step 1: Write the failing staged-deletion test**

Add a test that inserts a `UserProfile`, stages deletion, then proves a second context still sees the profile until the first context saves:

```swift
func testStageLocalDataDeletionDoesNotCommitUntilCallerSaves() throws {
    let container = try makeInMemoryContainer()
    let seedContext = ModelContext(container)
    seedContext.insert(UserProfile(displayName: "Durable Athlete"))
    try seedContext.save()

    let restoreContext = ModelContext(container)
    restoreContext.autosaveEnabled = false
    let service = AppDataDeletionService(
        modelContext: restoreContext,
        deleteCloudBackup: {},
        clearWeeklyGoalWidgetSnapshot: {},
        clearActiveWorkoutSnapshot: {}
    )

    try service.stageLocalDataDeletion()

    let observerContext = ModelContext(container)
    XCTAssertEqual(try observerContext.fetch(FetchDescriptor<UserProfile>()).count, 1)
    restoreContext.rollback()
    XCTAssertEqual(try observerContext.fetch(FetchDescriptor<UserProfile>()).count, 1)
}
```

- [ ] **Step 2: Run the focused test and confirm the interface is missing**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,id=8624785A-FA03-43D6-A624-4192C8738D6A' -only-testing:WGJTests/UserDataCloudBackupServiceTests/testStageLocalDataDeletionDoesNotCommitUntilCallerSaves
```

Expected: compilation fails because `stageLocalDataDeletion()` is not defined.

- [ ] **Step 3: Split database mutation, commit, and artifact cleanup**

Expose the existing deletion graph without saving. Keep filesystem work out of the staged method:

```swift
func deleteLocalDeviceData() async throws {
    try stageLocalDataDeletion()
    if modelContext.hasChanges {
        try modelContext.save()
    }
    invalidateCommittedCaches()
    try await clearLocalArtifacts()
}

func stageLocalDataDeletion() throws {
    try stageExerciseImageMetadataReset()
    try deleteCustomExercises()

    try deleteAll(TemplateExerciseDropStage.self)
    try deleteAll(TemplateExerciseSet.self)
    try deleteAll(TemplateExerciseComponent.self)
    try deleteAll(TemplateCardioBlock.self)
    try deleteAll(TemplateSupersetGroup.self)
    try deleteAll(TemplateExercise.self)
    try deleteAll(WorkoutTemplate.self)
    try deleteAll(TemplateFolder.self)

    try deleteAll(ActiveWorkoutDraftDropStage.self)
    try deleteAll(ActiveWorkoutDraftSet.self)
    try deleteAll(ActiveWorkoutDraftExerciseComponent.self)
    try deleteAll(ActiveWorkoutDraftCardioBlock.self)
    try deleteAll(ActiveWorkoutDraftSupersetGroup.self)
    try deleteAll(ActiveWorkoutDraftExercise.self)
    try deleteAll(ActiveWorkoutDraftSession.self)

    try deleteAll(WorkoutSessionDropStage.self)
    try deleteAll(WorkoutSessionSet.self)
    try deleteAll(WorkoutSessionCardioBlock.self)
    try deleteAll(WorkoutSessionSupersetGroup.self)
    try deleteAll(WorkoutSessionExercise.self)
    try deleteAll(WorkoutSession.self)

    try deleteAll(CompletedSetFact.self)
    try deleteAll(CachedCoachFollowUpNarrative.self)
    try deleteAll(CachedCoachNarrative.self)
    try deleteAll(ProfileWidgetConfig.self)
    try deleteAll(UserDataDeletionTombstone.self)
    try deleteAll(UserProfile.self)
}

func clearLocalArtifacts() async throws {
    Self.removeExerciseImageCacheDirectory()
    clearWeeklyGoalWidgetSnapshot()
    try await clearActiveWorkoutSnapshot()
}

func invalidateCommittedCaches() {
    ExerciseSearchService.invalidateCatalogIndex(for: modelContext)
    HistoryAnalyticsCache.shared.clear()
}
```

Rename `clearExerciseImageCache()` to `stageExerciseImageMetadataReset()` and leave only model-field mutation in it. Move cache-directory removal into an internal nonthrowing static `removeExerciseImageCacheDirectory()` called after commit and by the cleanup queue.

- [ ] **Step 4: Run staged deletion and existing deletion tests**

Run the test class command from Step 2 without the method suffix.

Expected: all `UserDataCloudBackupServiceTests` pass.

- [ ] **Step 5: Commit the staged deletion boundary**

```bash
git add WGJ/Services/AppDataDeletionService.swift WGJTests/UserDataCloudBackupServiceTests.swift
git commit -m "refactor(storage): stage local deletion before commit"
```

### Task 2: Make Replacement Restore Transactional

**Files:**
- Create: `WGJ/Services/UserDataCloudBackupPayload.swift`
- Create: `WGJ/Services/UserDataCloudRestoreTransaction.swift`
- Create: `WGJ/Services/AppDataArtifactCleanupQueue.swift`
- Modify: `WGJ/Services/UserDataCloudBackupService.swift:19-27,130-235,435-end`
- Modify: `WGJ/Services/HistoryProjectionRepository.swift`
- Modify: `WGJ/Services/WorkoutSessionRepository.swift:980-1055`
- Modify: `WGJ/Services/ActiveWorkoutRuntime.swift:491-625`
- Test: `WGJTests/UserDataCloudBackupServiceTests.swift`

**Interfaces:**
- Produces: `UserDataCloudRestoreCheckpoint` and dependencies
- Produces: `ValidatedUserDataCloudBackup`
- Produces: `UserDataCloudRestoreTransaction.commit(_:replacingLocalData:)`
- Produces: `AppDataArtifactCleanupQueue`
- Produces: `UserDataCloudBackupRestoreResult.cleanupWarnings`
- Produces: `ActiveWorkoutSnapshotStore.invalidateSnapshotsSavedBefore(_:)`
- Consumes: `AppDataDeletionService.stageLocalDataDeletion()` from Task 1

- [ ] **Step 1: Add payload validation tests**

Move `UserDataCloudBackupPayload` and its DTOs from the backup service into the new payload file so `@testable import WGJ` tests can construct invalid payloads. Add tests for unsupported schema version, duplicate IDs, and every parent chain: template→folder; template cardio/group/exercise→template; component/set→template exercise; template drop stage→template set; workout cardio/group/exercise→completed session; workout set→workout exercise; workout drop stage→workout set; superset membership→group.

```swift
func testRestoreValidationRejectsOrphanedWorkoutSet() throws {
    var payload = UserDataCloudBackupPayload.emptyForTests
    payload.workoutSets = [
        .fixture(id: fixedSetID, sessionExerciseID: missingExerciseID)
    ]

    XCTAssertThrowsError(try payload.validated()) { error in
        XCTAssertEqual(
            error as? UserDataCloudRestoreValidationError,
            .missingParent(
                childEntity: "WorkoutSessionSet",
                childIdentifier: fixedSetID.uuidString,
                parentIdentifier: missingExerciseID.uuidString
            )
        )
    }
}
```

- [ ] **Step 2: Add checkpoint and artifact-failure tests**

Parameterize every pre-save checkpoint. After each injected failure, read through a new context and assert the exact original fingerprint. Add an artifact failure case that returns restore success with a warning and queryable restored rows:

```swift
private enum RestoreTestError: Error {
    case checkpoint(UserDataCloudRestoreCheckpoint)
    case artifactCleanup
}

func testReplacementRestoreFailuresPreserveOriginalData() throws {
    for checkpoint in UserDataCloudRestoreCheckpoint.allCases {
        let local = try makeInMemoryContainer()
        let localContext = ModelContext(local)
        localContext.insert(UserProfile(displayName: "Original"))
        try localContext.save()
        let source = try makeInMemoryContainer()
        let sourceContext = ModelContext(source)
        sourceContext.insert(UserProfile(displayName: "Restored"))
        try sourceContext.save()
        let validated = try UserDataCloudBackupPayload(context: sourceContext).validated()
        let transaction = UserDataCloudRestoreTransaction(
            container: local,
            dependencies: UserDataCloudRestoreDependencies(
                checkpoint: { reached in
                    if reached == checkpoint { throw RestoreTestError.checkpoint(reached) }
                },
                save: { try $0.save() }
            )
        )

        XCTAssertThrowsError(
            try transaction.commit(validated, replacingLocalData: true)
        )
        XCTAssertEqual(
            try ModelContext(local).fetch(FetchDescriptor<UserProfile>()).map(\.displayName),
            ["Original"]
        )
    }
}

func testReplacementRestoreArtifactFailureKeepsCommittedRestore() async throws {
    let source = try makeInMemoryContainer()
    let sourceContext = ModelContext(source)
    sourceContext.insert(UserProfile(displayName: "Restored"))
    try sourceContext.save()
    let backupStore = CapturingBackupStore()
    _ = try await UserDataCloudBackupService(localContainer: source, backupStore: backupStore).exportCurrentBackup()
    let local = try makeInMemoryContainer()
    let queue = AppDataArtifactCleanupQueue(
        defaults: UserDefaults(suiteName: UUID().uuidString)!,
        cleanup: { _ in throw RestoreTestError.artifactCleanup }
    )
    let service = UserDataCloudBackupService(
        localContainer: local,
        backupStore: backupStore,
        artifactCleanupQueue: queue
    )
    let result = try await service.restoreLatestBackup(replacingLocalData: true)
    XCTAssertEqual(result?.cleanupWarnings.count, 3)
    XCTAssertEqual(
        try ModelContext(local).fetch(FetchDescriptor<UserProfile>()).map(\.displayName),
        ["Restored"]
    )
}
```

- [ ] **Step 3: Run validation/transaction tests and verify missing interfaces**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,id=8624785A-FA03-43D6-A624-4192C8738D6A' -only-testing:WGJTests/UserDataCloudBackupServiceTests
```

Expected: compilation fails because validation, checkpoint, transaction, and cleanup-queue interfaces do not exist.

- [ ] **Step 4: Implement payload validation**

```swift
nonisolated enum UserDataCloudRestoreValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case duplicateIdentifier(entity: String, identifier: String)
    case missingParent(childEntity: String, childIdentifier: String, parentIdentifier: String)
    case invalidCompletedWorkoutStatus(UUID)
    case invalidSupersetMembership(UUID)
}

nonisolated struct ValidatedUserDataCloudBackup: Sendable {
    let payload: UserDataCloudBackupPayload
}

nonisolated extension UserDataCloudBackupPayload {
    func validated() throws -> ValidatedUserDataCloudBackup
    func mergeDatabaseGraph(into context: ModelContext) throws
    func relinkRelationships(in context: ModelContext) throws
}
```

`validated()` builds ID sets once, rejects duplicate IDs before relationship checks, verifies the exact parent chains from Step 1, requires restored workouts to be completed, and validates superset positions/group membership.

Make the payload and every nested backup DTO `Sendable`; they contain only UUIDs, strings, dates, numbers, booleans, enums, and arrays of those values.

- [ ] **Step 5: Implement the one-context restore transaction**

```swift
nonisolated enum UserDataCloudRestoreCheckpoint: CaseIterable, Equatable, Sendable {
    case afterValidation
    case afterDeletionStaged
    case afterGraphMerge
    case afterRelationshipLink
    case afterProjectionRebuild
    case beforeSave
}

nonisolated struct UserDataCloudRestoreDependencies {
    var checkpoint: (UserDataCloudRestoreCheckpoint) throws -> Void = { _ in }
    var save: (ModelContext) throws -> Void = { try $0.save() }
}

nonisolated final class UserDataCloudRestoreTransaction {
    private let container: ModelContainer
    private let dependencies: UserDataCloudRestoreDependencies

    init(container: ModelContainer, dependencies: UserDataCloudRestoreDependencies = .init()) {
        self.container = container
        self.dependencies = dependencies
    }

    func commit(_ backup: ValidatedUserDataCloudBackup, replacingLocalData: Bool) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            try dependencies.checkpoint(.afterValidation)
            if replacingLocalData {
                try AppDataDeletionService(modelContext: context).stageLocalDataDeletion()
                try dependencies.checkpoint(.afterDeletionStaged)
            }
            try backup.payload.mergeDatabaseGraph(into: context)
            try dependencies.checkpoint(.afterGraphMerge)
            try backup.payload.relinkRelationships(in: context)
            try dependencies.checkpoint(.afterRelationshipLink)
            try rebuildCompletedSessionSummariesAndFacts(in: context)
            try dependencies.checkpoint(.afterProjectionRebuild)
            try dependencies.checkpoint(.beforeSave)
            if context.hasChanges { try dependencies.save(context) }
        } catch {
            context.rollback()
            throw error
        }
    }

    private func rebuildCompletedSessionSummariesAndFacts(in context: ModelContext) throws {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.status == .completed }
        let repository = WorkoutSessionRepository(modelContext: context, autoSaveChanges: false)
        for session in sessions {
            try repository.recalculateSessionSummary(sessionID: session.id)
        }
    }
}

struct UserDataCloudBackupRestoreResult: Equatable, Sendable {
    let restoredAt: Date
    let cleanupWarnings: [AppDataArtifactCleanupWarning]
}
```

The rebuild helper uses non-saving `WorkoutSessionRepository`/`HistoryProjectionRepository` primitives for every restored session, so summaries and `CompletedSetFact` rows join the same save.

- [ ] **Step 6: Add retryable post-commit artifact cleanup**

```swift
nonisolated enum AppDataArtifact: String, CaseIterable, Hashable, Codable, Sendable {
    case activeWorkoutSnapshot
    case weeklyGoalWidgetSnapshot
    case exerciseImageCache
}

nonisolated struct AppDataArtifactCleanupWarning: Equatable, Sendable {
    let artifact: AppDataArtifact
    let description: String
}

actor AppDataArtifactCleanupQueue {
    static let shared = AppDataArtifactCleanupQueue(cleanup: { artifact in
        switch artifact {
        case .activeWorkoutSnapshot:
            try await ActiveWorkoutSnapshotStore.shared.delete()
        case .weeklyGoalWidgetSnapshot:
            WeeklyGoalWidgetPublisher()?.clear()
        case .exerciseImageCache:
            AppDataDeletionService.removeExerciseImageCacheDirectory()
        }
    })

    private let defaults: UserDefaults
    private let cleanup: @Sendable (AppDataArtifact) async throws -> Void

    init(
        defaults: UserDefaults = .standard,
        cleanup: @escaping @Sendable (AppDataArtifact) async throws -> Void
    ) {
        self.defaults = defaults
        self.cleanup = cleanup
    }

    func enqueue(_ artifacts: Set<AppDataArtifact>) async -> [AppDataArtifactCleanupWarning]
    func retryPending() async -> [AppDataArtifactCleanupWarning]
}
```

Persist pending artifact raw values in `UserDefaults`. Remove each only after successful cleanup. Retry at the next durable launch and diagnostics screen appearance. Before cleanup, call `invalidateSnapshotsSavedBefore(.now)` so a failed file delete cannot resurrect the old workout.

Add `artifactCleanupQueue: AppDataArtifactCleanupQueue = .shared` and `restoreTransaction: UserDataCloudRestoreTransaction? = nil` to `UserDataCloudBackupService.init`; create the live transaction from `localContainer` when no transaction is injected.

- [ ] **Step 7: Route the service through validation, transaction, and cleanup**

Use this order in `restoreLatestBackup`:

```swift
let payload = try Self.makeDecoder().decode(UserDataCloudBackupPayload.self, from: record.payloadData)
let validated = try payload.validated()
if !replacingLocalData {
    let checkContext = ModelContext(localContainer)
    guard try Self.isLocalUserDataEmpty(context: checkContext) else { return nil }
}
try restoreTransaction.commit(validated, replacingLocalData: replacingLocalData)
ExerciseSearchService.invalidateCatalogIndex(for: ModelContext(localContainer))
HistoryAnalyticsCache.shared.clear()
await ActiveWorkoutSnapshotStore.shared.invalidateSnapshotsSavedBefore(.now)
let warnings = await artifactCleanupQueue.enqueue(Set(AppDataArtifact.allCases))
NotificationCenter.default.post(name: .wgjUserDataRestoreDidComplete, object: nil)
return UserDataCloudBackupRestoreResult(
    restoredAt: record.updatedAt,
    cleanupWarnings: warnings
)
```

Post exactly one restore-completed notification after save. Remove the two manual broadcaster posts in `AppStorageDiagnosticsView`; subscribers refresh from the single event.

- [ ] **Step 8: Run the full backup test class**

Run the class-level test command from Task 1.

Expected: validation, checkpoint, derived-data, cleanup-warning, single-event, and existing restore/export tests pass.

- [ ] **Step 9: Commit transactional restore**

```bash
git add WGJ/Services/UserDataCloudBackupPayload.swift WGJ/Services/UserDataCloudRestoreTransaction.swift WGJ/Services/AppDataArtifactCleanupQueue.swift WGJ/Services/UserDataCloudBackupService.swift WGJ/Services/HistoryProjectionRepository.swift WGJ/Services/WorkoutSessionRepository.swift WGJ/Services/ActiveWorkoutRuntime.swift WGJ/Views/Profile/AppStorageDiagnosticsView.swift WGJTests/UserDataCloudBackupServiceTests.swift
git commit -m "fix(backup): restore local data transactionally"
```

### Task 3: Expose Durable Versus Diagnostic Persistence

**Files:**
- Create: `WGJ/Models/AppPersistenceMode.swift`
- Create: `WGJ/Views/AppStorageRecoveryView.swift`
- Modify: `WGJ/Services/AppLaunchBootstrap.swift:7-198`
- Modify: `WGJ/WGJApp.swift:7-125`
- Modify: `WGJ/ContentView.swift:1-40`
- Modify: `WGJ/Views/MainTabView.swift:230-260`
- Test: `WGJTests/AppLaunchBootstrapTests.swift`

**Interfaces:**
- Produces: `AppPersistenceMode`
- Produces: `AppStorageRecoveryState`
- Produces: `AppLaunchBootstrapState.retry()` and `enterDiagnosticMode(using:)`
- Produces: environment value `appPersistenceMode`

- [ ] **Step 1: Write launch-state tests**

```swift
@MainActor
final class AppLaunchBootstrapTests: XCTestCase {
    private enum TestError: Error { case storeOpen }

    func testPersistentStoreFailureShowsRecoveryInsteadOfReadyContent() async {
        let state = AppLaunchBootstrapState()
        state.resolveIfNeeded(resolver: { throw TestError.storeOpen })
        await waitUntil { state.recoveryState != nil }

        XCTAssertNil(state.resolvedBootstrap)
        XCTAssertEqual(state.recoveryState?.canMutateUserData, false)
    }

    func testRetryCanResolveDurableStore() async throws {
        let state = AppLaunchBootstrapState()
        state.resolveIfNeeded(resolver: { throw TestError.storeOpen })
        await waitUntil { state.recoveryState != nil }
        let schema = Schema([UserProfile.self])
        let configuration = ModelConfiguration("LaunchTests", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition did not become true within one second")
    }
}
```

- [ ] **Step 2: Run the new test class and confirm missing state APIs**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,id=8624785A-FA03-43D6-A624-4192C8738D6A' -only-testing:WGJTests/AppLaunchBootstrapTests
```

Expected: compilation fails for missing persistence and recovery types.

- [ ] **Step 3: Add typed persistence state and environment access**

```swift
nonisolated enum AppPersistenceMode: Equatable, Sendable {
    case durable
    case volatileDiagnostic(reason: String)

    var canMutateUserData: Bool {
        if case .durable = self { return true }
        return false
    }
}

nonisolated struct AppStorageRecoveryState: Equatable, Sendable {
    let message: String
    let diagnosticReport: String
    let canMutateUserData = false
}

private struct AppPersistenceModeKey: EnvironmentKey {
    static let defaultValue: AppPersistenceMode = .durable
}

extension EnvironmentValues {
    var appPersistenceMode: AppPersistenceMode {
        get { self[AppPersistenceModeKey.self] }
        set { self[AppPersistenceModeKey.self] = newValue }
    }
}
```

Add `persistenceMode` to `ModelContainerBootstrap`; every normal and UI-test bootstrap sets `.durable`, while user-entered diagnostic mode sets `.volatileDiagnostic(reason:)`.

- [ ] **Step 4: Replace automatic emergency fallback with recovery state**

In `AppLaunchBootstrapState`, store the failed error as `recoveryState`, clear it on successful resolution, and expose retry. Remove `failureFallback` from the automatic `resolveIfNeeded` path. `WGJApp.body` uses this order:

```swift
if let resolved = launchBootstrapState.resolvedBootstrap {
    ContentView()
        .environment(\.appPersistenceMode, resolved.bootstrap.persistenceMode)
        .modelContainer(resolved.bootstrap.container)
} else if let recovery = launchBootstrapState.recoveryState {
    AppStorageRecoveryView(
        state: recovery,
        onRetry: { launchBootstrapState.retry(resolver: Self.makeContainerBootstrap) },
        onEnterDiagnosticMode: {
            launchBootstrapState.enterDiagnosticMode(using: Self.makeEmergencyBootstrap)
        }
    )
} else {
    SplashView()
        .task { launchBootstrapState.resolveIfNeeded(resolver: Self.makeContainerBootstrap) }
}
```

`AppStorageRecoveryView` renders the message, Retry, and a `ShareLink` for `diagnosticReport`. Diagnostic mode is secondary and explicitly labeled “Temporary diagnostics — changes cannot be saved.” Do not put normal workout/template navigation on the recovery screen.

- [ ] **Step 5: Gate mutation entry points in diagnostic mode**

Read `appPersistenceMode` in `ContentView` and `MainTabView`. In diagnostic mode, present the diagnostics/status shell and exclude Start Workout, Save Template, history editing, profile editing, and deletion controls. The durable path remains unchanged. Ensure sync copy uses “Temporary diagnostics” rather than “Saved locally.”

- [ ] **Step 6: Run launch tests and compile the app**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,id=8624785A-FA03-43D6-A624-4192C8738D6A' -only-testing:WGJTests/AppLaunchBootstrapTests
xcodebuild build -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Expected: launch tests and build pass; no path automatically enters an editable in-memory app after durable-store failure.

- [ ] **Step 7: Commit explicit storage recovery**

```bash
git add WGJ/Models/AppPersistenceMode.swift WGJ/Views/AppStorageRecoveryView.swift WGJ/Services/AppLaunchBootstrap.swift WGJ/WGJApp.swift WGJ/ContentView.swift WGJ/Views/MainTabView.swift WGJTests/AppLaunchBootstrapTests.swift
git commit -m "fix(storage): block edits when durable storage fails"
```

### Task 4: Make Workout Completion Idempotent

**Files:**
- Create: `WGJ/Services/WorkoutCompletionRepository.swift`
- Modify: `WGJ/Services/ActiveWorkoutRuntime.swift:900-1045`
- Modify: `WGJ/Models/AppRuntimeConfig.swift:1000-1060`
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift:1900-1970`
- Test: `WGJTests/UserDataCloudBackupServiceTests.swift`

**Interfaces:**
- Produces: `WorkoutCompletionCommitResult`
- Produces: `WorkoutCompletionDisposition`
- Produces: `ActiveWorkoutRestorePolicy`

- [ ] **Step 1: Write idempotence and retained-snapshot tests**

```swift
func testCompletionRepositoryReturnsExistingCompletedSessionWithoutDuplicateInsert() throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    let fixedSessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let runtime = ActiveWorkoutRuntimeSession(id: fixedSessionID, name: "Push")
    let writer = WorkoutCompletionRepository(modelContext: context)

    let first = try writer.completeWorkout(session: runtime)
    let second = try writer.completeWorkout(session: runtime)

    XCTAssertEqual(first, WorkoutCompletionCommitResult(sessionID: fixedSessionID, disposition: .inserted))
    XCTAssertEqual(second, WorkoutCompletionCommitResult(sessionID: fixedSessionID, disposition: .alreadyCompleted))
    XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
}

func testRestorePolicyRejectsSnapshotForCompletedSession() {
    let fixedSessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    XCTAssertFalse(
        ActiveWorkoutRestorePolicy.shouldRestore(
            snapshotSessionID: fixedSessionID,
            completedSessionIDs: [fixedSessionID]
        )
    )
}
```

- [ ] **Step 2: Run both focused tests and confirm failure**

Run the `UserDataCloudBackupServiceTests` class command with both method selectors.

Expected: compilation fails because completion still returns `UUID` and restore policy does not exist.

- [ ] **Step 3: Add result types and early completed-session lookup**

```swift
nonisolated enum WorkoutCompletionDisposition: Equatable, Sendable {
    case inserted
    case alreadyCompleted
}

nonisolated struct WorkoutCompletionCommitResult: Equatable, Sendable {
    let sessionID: UUID
    let disposition: WorkoutCompletionDisposition
}
```

Move the existing materialization from `ActiveWorkoutCompletionWriter` into `WorkoutCompletionRepository.completeWorkout(session:notes:)`. Fetch `WorkoutSession` by runtime ID first. Return `.alreadyCompleted` when its status is completed; throw `.invalidSessionState` for any other matching status. Only the `.inserted` branch inserts children, saves, emits history events, and schedules backup.

- [ ] **Step 4: Reject stale snapshots during bootstrap restore**

Add a pure policy:

```swift
nonisolated enum ActiveWorkoutRestorePolicy {
    static func shouldRestore(
        snapshotSessionID: UUID,
        completedSessionIDs: Set<UUID>
    ) -> Bool {
        !completedSessionIDs.contains(snapshotSessionID)
    }
}
```

Before publishing a loaded snapshot in `AppRuntimeConfig`, query a background context for a completed session with that ID. If found, delete the snapshot and return no active session. Update `ActiveWorkoutView` to accept both completion dispositions as success and delete the snapshot best-effort.

- [ ] **Step 5: Run the full active-workout test class**

Expected: the completion/restore tests pass and exactly one completed graph exists after repeated completion.

- [ ] **Step 6: Commit idempotent completion**

```bash
git add WGJ/Services/WorkoutCompletionRepository.swift WGJ/Services/ActiveWorkoutRuntime.swift WGJ/Models/AppRuntimeConfig.swift WGJ/Views/Workout/ActiveWorkoutView.swift WGJTests/UserDataCloudBackupServiceTests.swift
git commit -m "fix(workout): make completion idempotent"
```

### Task 5: Commit History Mutations and Summaries Atomically

**Files:**
- Create: `WGJ/Services/WorkoutHistoryMutationService.swift`
- Modify: `WGJ/Services/WorkoutSessionRepository.swift:25-65,560-650,980-1045`
- Modify: `WGJ/Views/History/HistoryDetailView.swift:590-880`
- Test: `WGJTests/WorkoutHistoryMutationServiceTests.swift`

**Interfaces:**
- Produces: `WorkoutHistoryMutationService.addExercise(sessionID:selection:)`
- Produces: `WorkoutHistoryMutationService.removeExercise(sessionID:exerciseID:)`
- Produces: deferred `WorkoutSessionRepository.finalizeDeferredUserDataChangesIfNeeded()`

- [ ] **Step 1: Write atomic remove/reload and rollback tests**

```swift
func testRemovingOnlyExerciseCommitsZeroSummaryAndNoFacts() async throws {
    let container = try makeCompletedWorkoutContainer()
    let service = WorkoutHistoryMutationService(backgroundStore: AppBackgroundStore(container: container))

    try await service.removeExercise(sessionID: sessionID, exerciseID: exerciseID)

    let context = ModelContext(container)
    let session = try XCTUnwrap(fetchSession(sessionID, context: context))
    XCTAssertEqual(session.totalVolume, 0)
    XCTAssertEqual(session.prHitsCount, 0)
    XCTAssertTrue(try context.fetch(FetchDescriptor<CompletedSetFact>()).isEmpty)
}

func testHistoryMutationFailureRollsBackStructureAndSummary() async throws {
    let container = try makeCompletedWorkoutContainer()
    let service = WorkoutHistoryMutationService(
        backgroundStore: AppBackgroundStore(container: container),
        beforeSave: { throw HistoryMutationTestError.beforeSave }
    )

    await XCTAssertThrowsErrorAsync {
        try await service.removeExercise(sessionID: sessionID, exerciseID: exerciseID)
    }

    let context = ModelContext(container)
    XCTAssertEqual(try fetchSession(sessionID, context: context)?.exercises?.count, 1)
}
```

- [ ] **Step 2: Run the new test class and verify missing service failure**

Run the standard test command with `-only-testing:WGJTests/WorkoutHistoryMutationServiceTests`.

Expected: compilation fails because the mutation service does not exist.

- [ ] **Step 3: Add deferred repository save semantics**

Extend `WorkoutSessionRepository` with `autoSaveChanges`, a pending-effect set, `saveOrDefer(_:)`, and:

```swift
func finalizeDeferredUserDataChangesIfNeeded() throws {
    guard !autoSaveChanges, modelContext.hasChanges else { return }
    try modelContext.save()
    applyPendingPostCommitEffects()
    pendingPostCommitEffects.removeAll()
}
```

When `autoSaveChanges` is false, add/remove/recalculate methods mutate only and record required cache, projection, widget, history-broadcast, and backup effects. They never save or publish early.

- [ ] **Step 4: Implement one-context history commands**

```swift
nonisolated struct WorkoutHistoryMutationService: Sendable {
    let backgroundStore: AppBackgroundStore
    let beforeSave: @Sendable () throws -> Void

    init(
        backgroundStore: AppBackgroundStore,
        beforeSave: @escaping @Sendable () throws -> Void = {}
    ) {
        self.backgroundStore = backgroundStore
        self.beforeSave = beforeSave
    }

    func removeExercise(sessionID: UUID, exerciseID: UUID) async throws {
        try await backgroundStore.perform("history.exercise.remove") { context in
            let repository = WorkoutSessionRepository(modelContext: context, autoSaveChanges: false)
            do {
                try repository.removeExercise(sessionID: sessionID, sessionExerciseID: exerciseID)
                try repository.recalculateSessionSummary(sessionID: sessionID)
                try beforeSave()
                try repository.finalizeDeferredUserDataChangesIfNeeded()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    func addExercise(sessionID: UUID, selection: ExerciseCatalogSelection) async throws {
        try await backgroundStore.perform("history.exercise.add") { context in
            let repository = WorkoutSessionRepository(modelContext: context, autoSaveChanges: false)
            do {
                try repository.addExercise(sessionID: sessionID, selection: selection)
                try repository.recalculateSessionSummary(sessionID: sessionID)
                try beforeSave()
                try repository.finalizeDeferredUserDataChangesIfNeeded()
            } catch {
                context.rollback()
                throw error
            }
        }
    }
}
```

Add the value-snapshot overload `addExercise(sessionID:selection:)` to avoid sending `ExerciseCatalogItem` across contexts.

- [ ] **Step 5: Route `HistoryDetailView` through the service**

Replace synchronous repository add/remove calls and `hasPendingSummaryRebuild` toggling with one async service command, then reload the detail snapshot. Keep staged text fields behind the existing Save action, but make that Save use one deferred repository finalization as well.

- [ ] **Step 6: Run history and backup regression tests**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,id=8624785A-FA03-43D6-A624-4192C8738D6A' -only-testing:WGJTests/WorkoutHistoryMutationServiceTests -only-testing:WGJTests/UserDataCloudBackupServiceTests
```

Expected: both classes pass and no mutation exposes a stale summary from a new context.

- [ ] **Step 7: Commit atomic history editing**

```bash
git add WGJ/Services/WorkoutHistoryMutationService.swift WGJ/Services/WorkoutSessionRepository.swift WGJ/Views/History/HistoryDetailView.swift WGJTests/WorkoutHistoryMutationServiceTests.swift
git commit -m "fix(history): commit edits and summaries atomically"
```

### Task 6: Finalize the Template Editor Save Boundary

**Files:**
- Modify: `WGJ/Views/Templates/TemplateEditorView.swift:1478-1511`
- Modify: `WGJ/Services/TemplateRepository.swift:320-369`
- Test: `WGJTests/TemplateEditorPersistenceTests.swift`

**Interfaces:**
- Consumes: existing `TemplateRepository.finalizeDeferredUserDataChangesIfNeeded()`
- Produces: `TemplateSaveBoundaryEffects`

- [ ] **Step 1: Write the persistence regression test**

```swift
func testTemplateEditorSaveCommitsCreatedTemplate() throws {
    let container = try makeInMemoryContainer()
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let request = TemplateEditorSaveRequest(
        folderID: nil,
        templateID: nil,
        name: "Upper",
        notes: "",
        exerciseDrafts: [],
        cardioDrafts: []
    )

    _ = try TemplateEditorPersistence.save(request, modelContext: context)

    let verificationContext = ModelContext(container)
    XCTAssertEqual(try verificationContext.fetch(FetchDescriptor<WorkoutTemplate>()).map(\.name), ["Upper"])
}
```

Pass recording boundary effects and assert one library event and one `.templateSaved` backup request. Add existing-template and thrown-validation cases with counts `1/1` and `0/0` respectively.

- [ ] **Step 2: Run the test and verify the new context sees no template**

Run the standard test command with `-only-testing:WGJTests/TemplateEditorPersistenceTests`.

Expected: the durable-read assertion fails before finalization is added.

- [ ] **Step 3: Add injectable boundary effects**

```swift
nonisolated struct TemplateSaveBoundaryEffects {
    let postLibraryChange: @Sendable () -> Void
    let scheduleBackup: @Sendable (ModelContainer, BoundaryCloudBackupReason) -> Void

    static let live = TemplateSaveBoundaryEffects(
        postLibraryChange: { TemplateLibraryChangeBroadcaster.post() },
        scheduleBackup: { container, reason in
            BoundaryCloudBackupScheduler.exportBestEffort(container: container, reason: reason)
        }
    )
}
```

Add `boundaryEffects: TemplateSaveBoundaryEffects = .live` to `TemplateRepository.init`. Both immediate saves and deferred finalization invoke these effects only after `modelContext.save()` succeeds.

- [ ] **Step 4: Finalize before returning success**

Add `boundaryEffects: TemplateSaveBoundaryEffects = .live` to `TemplateEditorPersistence.save`, pass it to the repository, and insert exactly one finalization call after create/update mutations and before constructing the result:

```swift
try repository.finalizeDeferredUserDataChangesIfNeeded()

return .saved(TemplateEditorSaveResult(
    templateID: savedTemplateID,
    name: request.name.trimmingCharacters(in: .whitespacesAndNewlines),
    notes: request.notes.trimmingCharacters(in: .whitespacesAndNewlines)
))
```

- [ ] **Step 5: Run template and backup tests**

Expected: the new test and existing `UserDataCloudBackupServiceTests` pass with one notification and one backup request.

- [ ] **Step 6: Commit the template boundary fix**

```bash
git add WGJ/Views/Templates/TemplateEditorView.swift WGJ/Services/TemplateRepository.swift WGJTests/TemplateEditorPersistenceTests.swift
git commit -m "fix(templates): finalize editor saves at boundary"
```

### Task 7: Verify the Complete Persistence Workstream

**Files:**
- Verify only: all files changed in Tasks 1-6

**Interfaces:**
- Verifies all interfaces produced by this plan.

- [ ] **Step 1: Run all unit tests**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,id=8624785A-FA03-43D6-A624-4192C8738D6A' -only-testing:WGJTests
```

Expected: all `WGJTests` pass.

- [ ] **Step 2: Build every product without signing**

```bash
xcodebuild build-for-testing -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/WGJDataIntegrityBuild CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 3: Re-run targeted failure cases three times**

Run the two transactional restore tests, the completion idempotence test, and history rollback test three times using `-test-iterations 3`.

Expected: all iterations pass without ordering-dependent failures.

- [ ] **Step 4: Review save and backup boundaries**

```bash
rg -n "modelContext\.save\(|BoundaryCloudBackupScheduler\.exportBestEffort|TemplateLibraryChangeBroadcaster\.post|WorkoutHistoryChangeBroadcaster\.post" WGJ/Services WGJ/Views/Templates/TemplateEditorView.swift WGJ/Views/History/HistoryDetailView.swift
```

Expected: restore has one database save, template/history command paths finalize once, and backup calls appear only after successful local commits.

- [ ] **Step 5: Commit any test-only corrections**

```bash
git add WGJ WGJTests
git commit -m "test(storage): cover atomic persistence boundaries"
```

Skip this commit when Step 1-4 require no corrections.
