import XCTest
@testable import WGJ

final class SettingsPersistenceCoordinatorTests: XCTestCase {
    func testPreferredDistanceUnitDefaultsFromLocaleAndCopiesProfile() {
        let fallback = WorkoutDistanceUnit.regionalDefault(locale: .current)
        XCTAssertEqual(UserSettingsDraft.default.preferredDistanceUnit, fallback)

        let profile = UserProfile(displayName: "Peter", preferredDistanceUnit: .miles)
        XCTAssertEqual(UserSettingsDraft(profile: profile).preferredDistanceUnit, .miles)
    }

    func testPreferredDistanceUnitPatchChangesOnlyDistancePreference() {
        var draft = UserSettingsDraft.default
        let weightUnit = draft.preferredWeightUnit

        draft.apply(.init(preferredDistanceUnit: .meters))

        XCTAssertEqual(draft.preferredDistanceUnit, .meters)
        XCTAssertEqual(draft.preferredWeightUnit, weightUnit)
    }

    func testAutoCloseCompletedExercisesDefaultsOnAndCopiesProfileValue() {
        XCTAssertTrue(UserSettingsDraft.default.automaticallyClosesCompletedExercises)

        let profile = UserProfile(
            displayName: "Peter",
            automaticallyClosesCompletedExercises: false
        )

        XCTAssertFalse(UserSettingsDraft(profile: profile).automaticallyClosesCompletedExercises)
    }

    func testAutoCloseCompletedExercisesPatchUpdatesDraft() {
        var draft = UserSettingsDraft.default

        draft.apply(.init(automaticallyClosesCompletedExercises: false))

        XCTAssertFalse(draft.automaticallyClosesCompletedExercises)
        XCTAssertEqual(draft.weeklyWorkoutGoal, 4)
    }

    func testCalorieEstimatesDefaultOnAndCopiesDisabledProfileValue() {
        XCTAssertTrue(UserSettingsDraft.default.showsCalorieEstimates)

        let profile = UserProfile(
            displayName: "Peter",
            showsCalorieEstimates: false
        )

        XCTAssertFalse(UserSettingsDraft(profile: profile).showsCalorieEstimates)
    }

    func testCalorieEstimatesPatchChangesOnlyCaloriePreference() {
        var draft = UserSettingsDraft.default
        let weeklyWorkoutGoal = draft.weeklyWorkoutGoal

        draft.apply(.init(showsCalorieEstimates: false))

        XCTAssertFalse(draft.showsCalorieEstimates)
        XCTAssertEqual(draft.weeklyWorkoutGoal, weeklyWorkoutGoal)
    }

    func testNewerCaloriePreferencePersistsAfterDelayedOlderWriteAndOwnsSideEffects() async throws {
        let store = SettingsTestStore(
            draft: UserSettingsDraft(
                weeklyWorkoutGoal: 4,
                isTrainingGuidanceEnabled: true,
                keepsScreenAwake: true,
                preferredWeightUnit: .kg,
                workoutNotificationStyle: .timeSensitive
            ),
            delayedRevision: 1
        )
        let commits = SettingsCommitRecorder()
        let writer = OrderedSettingsWriter(
            persist: { try await store.persist($0) },
            onCommit: { revision, write, draft in
                await commits.record(revision: revision, write: write, draft: draft)
            },
            onFailure: { _, _ in }
        )

        await writer.submit(RevisionedSettingsWrite(
            revision: 1,
            patch: UserSettingsPatch(showsCalorieEstimates: false)
        ))
        await store.waitUntilDelayedWriteStarts()
        await writer.submit(RevisionedSettingsWrite(
            revision: 2,
            patch: UserSettingsPatch(showsCalorieEstimates: true)
        ))
        await store.releaseDelayedWrite()
        await writer.flush()

        let persisted = await store.currentDraft()
        let committedRevisions = await commits.revisions()
        let committedCaloriePreferences = await commits.caloriePreferences()
        XCTAssertEqual(persisted.showsCalorieEstimates, true)
        XCTAssertEqual(committedRevisions, [2])
        XCTAssertEqual(committedCaloriePreferences, [true])
    }

    func testDelayedCalorieDisableCarriesBroadcastIntoNewerUnrelatedCommit() async throws {
        let store = SettingsTestStore(
            draft: UserSettingsDraft(
                weeklyWorkoutGoal: 4,
                isTrainingGuidanceEnabled: true,
                keepsScreenAwake: true,
                preferredWeightUnit: .kg,
                workoutNotificationStyle: .timeSensitive,
                showsCalorieEstimates: true
            ),
            delayedRevision: 1
        )
        let commits = SettingsCommitRecorder()
        let writer = OrderedSettingsWriter(
            persist: { try await store.persist($0) },
            onCommit: { revision, write, draft in
                await commits.record(revision: revision, write: write, draft: draft)
            },
            onFailure: { _, _ in }
        )

        await writer.submit(.init(
            revision: 1,
            patch: .init(showsCalorieEstimates: false)
        ))
        await store.waitUntilDelayedWriteStarts()
        await writer.submit(.init(
            revision: 2,
            patch: .init(keepsScreenAwake: false)
        ))
        await store.releaseDelayedWrite()
        await writer.flush()

        let persisted = await store.currentDraft()
        let committedRevisions = await commits.revisions()
        let effectCounts = await commits.calorieEffectCounts()
        XCTAssertFalse(persisted.showsCalorieEstimates)
        XCTAssertFalse(persisted.keepsScreenAwake)
        XCTAssertEqual(committedRevisions, [2])
        XCTAssertEqual(effectCounts.historyBroadcasts, 1)
        XCTAssertEqual(effectCounts.backfillSchedules, 0)
    }

    func testDelayedCalorieEnableCarriesBroadcastAndBackfillIntoNewerUnrelatedCommit() async throws {
        let store = SettingsTestStore(
            draft: UserSettingsDraft(
                weeklyWorkoutGoal: 4,
                isTrainingGuidanceEnabled: true,
                keepsScreenAwake: false,
                preferredWeightUnit: .kg,
                workoutNotificationStyle: .timeSensitive,
                showsCalorieEstimates: false
            ),
            delayedRevision: 1
        )
        let commits = SettingsCommitRecorder()
        let writer = OrderedSettingsWriter(
            persist: { try await store.persist($0) },
            onCommit: { revision, write, draft in
                await commits.record(revision: revision, write: write, draft: draft)
            },
            onFailure: { _, _ in }
        )

        await writer.submit(.init(
            revision: 1,
            patch: .init(showsCalorieEstimates: true)
        ))
        await store.waitUntilDelayedWriteStarts()
        await writer.submit(.init(
            revision: 2,
            patch: .init(keepsScreenAwake: true)
        ))
        await store.releaseDelayedWrite()
        await writer.flush()

        let persisted = await store.currentDraft()
        let committedRevisions = await commits.revisions()
        let effectCounts = await commits.calorieEffectCounts()
        XCTAssertTrue(persisted.showsCalorieEstimates)
        XCTAssertTrue(persisted.keepsScreenAwake)
        XCTAssertEqual(committedRevisions, [2])
        XCTAssertEqual(effectCounts.historyBroadcasts, 1)
        XCTAssertEqual(effectCounts.backfillSchedules, 1)
    }

    func testOlderFailedCalorieWriteMergesIntoNewerSuccessfulUnrelatedWrite() async throws {
        let store = SettingsTestStore(
            draft: UserSettingsDraft(
                weeklyWorkoutGoal: 4,
                isTrainingGuidanceEnabled: true,
                keepsScreenAwake: true,
                preferredWeightUnit: .kg,
                workoutNotificationStyle: .timeSensitive,
                showsCalorieEstimates: true
            ),
            delayedRevision: 1,
            failingRevisions: [1]
        )
        let events = SettingsCommitRecorder()
        let writer = OrderedSettingsWriter(
            persist: { try await store.persist($0) },
            onCommit: { revision, write, draft in
                await events.record(revision: revision, write: write, draft: draft)
            },
            onFailure: { write, _ in
                await events.recordFailure(revision: write.revision)
            }
        )

        await writer.submit(.init(
            revision: 1,
            patch: .init(showsCalorieEstimates: false)
        ))
        await store.waitUntilDelayedWriteStarts()
        await writer.submit(.init(
            revision: 2,
            patch: .init(keepsScreenAwake: false)
        ))
        await store.releaseDelayedWrite()
        await writer.flush()

        let persisted = await store.currentDraft()
        let committedRevisions = await events.revisions()
        let failedRevisions = await events.failureRevisions()
        let caloriePreferences = await events.caloriePreferences()
        XCTAssertFalse(persisted.showsCalorieEstimates)
        XCTAssertFalse(persisted.keepsScreenAwake)
        XCTAssertEqual(committedRevisions, [2])
        XCTAssertEqual(failedRevisions, [])
        XCTAssertEqual(caloriePreferences, [false])
    }

    func testOlderSuccessfulCalorieWriteDeliversEffectsBeforeNewerUnrelatedFailure() async throws {
        let store = SettingsTestStore(
            draft: UserSettingsDraft(
                weeklyWorkoutGoal: 4,
                isTrainingGuidanceEnabled: true,
                keepsScreenAwake: false,
                preferredWeightUnit: .kg,
                workoutNotificationStyle: .timeSensitive,
                showsCalorieEstimates: false
            ),
            delayedRevision: 1,
            failingRevisions: [2]
        )
        let events = SettingsCommitRecorder()
        let writer = OrderedSettingsWriter(
            persist: { try await store.persist($0) },
            onCommit: { revision, write, draft in
                await events.record(revision: revision, write: write, draft: draft)
            },
            onFailure: { write, _ in
                await events.recordFailure(revision: write.revision)
            }
        )

        await writer.submit(.init(
            revision: 1,
            patch: .init(showsCalorieEstimates: true)
        ))
        await store.waitUntilDelayedWriteStarts()
        await writer.submit(.init(
            revision: 2,
            patch: .init(keepsScreenAwake: true)
        ))
        await store.releaseDelayedWrite()
        await writer.flush()

        let persisted = await store.currentDraft()
        let effectCounts = await events.calorieEffectCounts()
        let committedRevisions = await events.revisions()
        let failedRevisions = await events.failureRevisions()
        let deliveryOrder = await events.deliveryOrder()
        XCTAssertTrue(persisted.showsCalorieEstimates)
        XCTAssertFalse(persisted.keepsScreenAwake)
        XCTAssertEqual(committedRevisions, [2])
        XCTAssertEqual(failedRevisions, [2])
        XCTAssertEqual(deliveryOrder, ["commit-2", "failure-2"])
        XCTAssertEqual(effectCounts.historyBroadcasts, 1)
        XCTAssertEqual(effectCounts.backfillSchedules, 1)
    }

    @MainActor
    func testLoneCalorieWriteFailurePublishesPersistedDraftForViewReconciliation() async {
        let persistedDraft = UserSettingsDraft(
            weeklyWorkoutGoal: 4,
            isTrainingGuidanceEnabled: true,
            keepsScreenAwake: false,
            preferredWeightUnit: .kg,
            workoutNotificationStyle: .timeSensitive,
            showsCalorieEstimates: false
        )
        let store = SettingsTestStore(
            draft: persistedDraft,
            failingRevisions: [1]
        )
        let coordinator = SettingsDraftCoordinator()
        coordinator.configure { try await store.persist($0) }
        coordinator.synchronizePersistedDraft(persistedDraft)

        coordinator.submit(.init(showsCalorieEstimates: true))
        await coordinator.flush()

        let storeDraft = await store.currentDraft()
        XCTAssertNotNil(coordinator.errorDescription)
        XCTAssertEqual(coordinator.reconciliationDraft, persistedDraft)
        XCTAssertEqual(storeDraft, persistedDraft)
    }

    func testRapidFalseTrueFalseEndsFalse() async throws {
        let store = SettingsTestStore(draft: .default)
        let writer = OrderedSettingsWriter(
            persist: { try await store.persist($0) },
            onCommit: { _, _, _ in },
            onFailure: { _, _ in }
        )

        await writer.submit(.init(revision: 1, patch: .init(keepsScreenAwake: false)))
        await writer.submit(.init(revision: 2, patch: .init(keepsScreenAwake: true)))
        await writer.submit(.init(revision: 3, patch: .init(keepsScreenAwake: false)))
        await writer.flush()

        let persisted = await store.currentDraft()
        XCTAssertEqual(persisted.keepsScreenAwake, false)
    }

    func testUnrelatedPatchDoesNotPersistUnsavedWeeklyGoal() async throws {
        let initial = UserSettingsDraft(
            weeklyWorkoutGoal: 7,
            isTrainingGuidanceEnabled: true,
            keepsScreenAwake: false,
            preferredWeightUnit: .kg,
            workoutNotificationStyle: .timeSensitive
        )
        let store = SettingsTestStore(draft: initial)
        let writer = OrderedSettingsWriter(
            persist: { try await store.persist($0) },
            onCommit: { _, _, _ in },
            onFailure: { _, _ in }
        )

        await writer.submit(.init(
            revision: 1,
            patch: .init(isTrainingGuidanceEnabled: false)
        ))
        await writer.flush()

        let persisted = await store.currentDraft()
        XCTAssertEqual(persisted.weeklyWorkoutGoal, 7)
        XCTAssertEqual(persisted.isTrainingGuidanceEnabled, false)
    }
}

private enum SettingsTestError: Error {
    case persistence
}

private actor SettingsTestStore {
    private var draft: UserSettingsDraft
    private let delayedRevision: UInt64?
    private let failingRevisions: Set<UInt64>
    private var delayedContinuation: CheckedContinuation<Void, Never>?
    private var delayedStartContinuations: [CheckedContinuation<Void, Never>] = []
    private var delayedWriteDidStart = false
    private var delayWasReleased = false

    init(
        draft: UserSettingsDraft,
        delayedRevision: UInt64? = nil,
        failingRevisions: Set<UInt64> = []
    ) {
        self.draft = draft
        self.delayedRevision = delayedRevision
        self.failingRevisions = failingRevisions
    }

    func persist(_ write: RevisionedSettingsWrite) async throws -> UserSettingsDraft {
        if write.revision == delayedRevision, !delayWasReleased {
            delayedWriteDidStart = true
            delayedStartContinuations.forEach { $0.resume() }
            delayedStartContinuations.removeAll()
            await withCheckedContinuation { continuation in
                delayedContinuation = continuation
            }
        }
        if failingRevisions.contains(write.revision) {
            throw SettingsTestError.persistence
        }
        draft.apply(write.patch)
        return draft
    }

    func waitUntilDelayedWriteStarts() async {
        guard !delayedWriteDidStart else { return }
        await withCheckedContinuation { continuation in
            delayedStartContinuations.append(continuation)
        }
    }

    func releaseDelayedWrite() {
        delayWasReleased = true
        delayedContinuation?.resume()
        delayedContinuation = nil
    }

    func currentDraft() -> UserSettingsDraft {
        draft
    }
}

private actor SettingsCommitRecorder {
    private var committedRevisions: [UInt64] = []
    private var committedCaloriePreferences: [Bool] = []
    private var historyBroadcastCount = 0
    private var backfillScheduleCount = 0
    private var failedRevisions: [UInt64] = []
    private var orderedDeliveries: [String] = []

    func record(
        revision: UInt64,
        write: RevisionedSettingsWrite,
        draft: UserSettingsDraft
    ) {
        _ = draft
        committedRevisions.append(revision)
        orderedDeliveries.append("commit-\(revision)")
        if let showsCalorieEstimates = write.patch.showsCalorieEstimates {
            committedCaloriePreferences.append(showsCalorieEstimates)
            historyBroadcastCount += 1
            if showsCalorieEstimates {
                backfillScheduleCount += 1
            }
        }
    }

    func recordFailure(revision: UInt64) {
        failedRevisions.append(revision)
        orderedDeliveries.append("failure-\(revision)")
    }

    func revisions() -> [UInt64] {
        committedRevisions
    }

    func caloriePreferences() -> [Bool] {
        committedCaloriePreferences
    }

    func calorieEffectCounts() -> (historyBroadcasts: Int, backfillSchedules: Int) {
        (historyBroadcastCount, backfillScheduleCount)
    }

    func failureRevisions() -> [UInt64] {
        failedRevisions
    }

    func deliveryOrder() -> [String] {
        orderedDeliveries
    }
}
