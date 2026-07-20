import XCTest
@testable import WGJ

final class SettingsPersistenceCoordinatorTests: XCTestCase {
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

    func testNewerRevisionPersistsAfterDelayedOlderWriteAndOwnsSideEffects() async throws {
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
            patch: UserSettingsPatch(keepsScreenAwake: false)
        ))
        await writer.submit(RevisionedSettingsWrite(
            revision: 2,
            patch: UserSettingsPatch(keepsScreenAwake: true)
        ))
        await store.releaseDelayedWrite()
        await writer.flush()

        let persisted = await store.currentDraft()
        let committedRevisions = await commits.revisions()
        XCTAssertEqual(persisted.keepsScreenAwake, true)
        XCTAssertEqual(committedRevisions, [2])
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

private actor SettingsTestStore {
    private var draft: UserSettingsDraft
    private let delayedRevision: UInt64?
    private var delayedContinuation: CheckedContinuation<Void, Never>?
    private var delayWasReleased = false

    init(draft: UserSettingsDraft, delayedRevision: UInt64? = nil) {
        self.draft = draft
        self.delayedRevision = delayedRevision
    }

    func persist(_ write: RevisionedSettingsWrite) async throws -> UserSettingsDraft {
        if write.revision == delayedRevision, !delayWasReleased {
            await withCheckedContinuation { continuation in
                delayedContinuation = continuation
            }
        }
        draft.apply(write.patch)
        return draft
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

    func record(
        revision: UInt64,
        write: RevisionedSettingsWrite,
        draft: UserSettingsDraft
    ) {
        _ = write
        _ = draft
        committedRevisions.append(revision)
    }

    func revisions() -> [UInt64] {
        committedRevisions
    }
}
