import Foundation
import Observation

nonisolated struct UserSettingsDraft: Equatable, Sendable {
    var weeklyWorkoutGoal: Int
    var isTrainingGuidanceEnabled: Bool
    var keepsScreenAwake: Bool
    var preferredWeightUnit: PreferredWeightUnit
    var preferredDistanceUnit: WorkoutDistanceUnit
    var workoutNotificationStyle: WorkoutNotificationStyle
    var automaticallyClosesCompletedExercises: Bool
    var showsCalorieEstimates: Bool

    static let `default` = UserSettingsDraft(
        weeklyWorkoutGoal: 4,
        isTrainingGuidanceEnabled: true,
        keepsScreenAwake: false,
        preferredWeightUnit: .kg,
        preferredDistanceUnit: .regionalDefault(locale: .current),
        workoutNotificationStyle: .timeSensitive,
        automaticallyClosesCompletedExercises: true,
        showsCalorieEstimates: true
    )

    init(
        weeklyWorkoutGoal: Int,
        isTrainingGuidanceEnabled: Bool,
        keepsScreenAwake: Bool,
        preferredWeightUnit: PreferredWeightUnit,
        preferredDistanceUnit: WorkoutDistanceUnit = .regionalDefault(locale: .current),
        workoutNotificationStyle: WorkoutNotificationStyle,
        automaticallyClosesCompletedExercises: Bool = true,
        showsCalorieEstimates: Bool = true
    ) {
        self.weeklyWorkoutGoal = weeklyWorkoutGoal
        self.isTrainingGuidanceEnabled = isTrainingGuidanceEnabled
        self.keepsScreenAwake = keepsScreenAwake
        self.preferredWeightUnit = preferredWeightUnit
        self.preferredDistanceUnit = preferredDistanceUnit
        self.workoutNotificationStyle = workoutNotificationStyle
        self.automaticallyClosesCompletedExercises = automaticallyClosesCompletedExercises
        self.showsCalorieEstimates = showsCalorieEstimates
    }

    init(profile: UserProfile) {
        self.init(
            weeklyWorkoutGoal: profile.weeklyWorkoutGoal,
            isTrainingGuidanceEnabled: profile.isTrainingGuidanceEnabled,
            keepsScreenAwake: profile.keepsScreenAwake,
            preferredWeightUnit: profile.preferredWeightUnit,
            preferredDistanceUnit: profile.preferredDistanceUnit,
            workoutNotificationStyle: profile.workoutNotificationStyle,
            automaticallyClosesCompletedExercises: profile.automaticallyClosesCompletedExercises,
            showsCalorieEstimates: profile.showsCalorieEstimates
        )
    }

    mutating func apply(_ patch: UserSettingsPatch) {
        if let value = patch.weeklyWorkoutGoal {
            weeklyWorkoutGoal = max(1, min(14, value))
        }
        if let value = patch.isTrainingGuidanceEnabled {
            isTrainingGuidanceEnabled = value
        }
        if let value = patch.keepsScreenAwake {
            keepsScreenAwake = value
        }
        if let value = patch.preferredWeightUnit {
            preferredWeightUnit = value
        }
        if let value = patch.preferredDistanceUnit {
            preferredDistanceUnit = value
        }
        if let value = patch.workoutNotificationStyle {
            workoutNotificationStyle = value
        }
        if let value = patch.automaticallyClosesCompletedExercises {
            automaticallyClosesCompletedExercises = value
        }
        if let value = patch.showsCalorieEstimates {
            showsCalorieEstimates = value
        }
    }
}

nonisolated struct UserSettingsPatch: Equatable, Sendable {
    var weeklyWorkoutGoal: Int?
    var isTrainingGuidanceEnabled: Bool?
    var keepsScreenAwake: Bool?
    var preferredWeightUnit: PreferredWeightUnit?
    var preferredDistanceUnit: WorkoutDistanceUnit?
    var workoutNotificationStyle: WorkoutNotificationStyle?
    var automaticallyClosesCompletedExercises: Bool?
    var showsCalorieEstimates: Bool?

    init(
        weeklyWorkoutGoal: Int? = nil,
        isTrainingGuidanceEnabled: Bool? = nil,
        keepsScreenAwake: Bool? = nil,
        preferredWeightUnit: PreferredWeightUnit? = nil,
        preferredDistanceUnit: WorkoutDistanceUnit? = nil,
        workoutNotificationStyle: WorkoutNotificationStyle? = nil,
        automaticallyClosesCompletedExercises: Bool? = nil,
        showsCalorieEstimates: Bool? = nil
    ) {
        self.weeklyWorkoutGoal = weeklyWorkoutGoal
        self.isTrainingGuidanceEnabled = isTrainingGuidanceEnabled
        self.keepsScreenAwake = keepsScreenAwake
        self.preferredWeightUnit = preferredWeightUnit
        self.preferredDistanceUnit = preferredDistanceUnit
        self.workoutNotificationStyle = workoutNotificationStyle
        self.automaticallyClosesCompletedExercises = automaticallyClosesCompletedExercises
        self.showsCalorieEstimates = showsCalorieEstimates
    }

    mutating func merge(_ newer: UserSettingsPatch) {
        if let value = newer.weeklyWorkoutGoal { weeklyWorkoutGoal = value }
        if let value = newer.isTrainingGuidanceEnabled { isTrainingGuidanceEnabled = value }
        if let value = newer.keepsScreenAwake { keepsScreenAwake = value }
        if let value = newer.preferredWeightUnit { preferredWeightUnit = value }
        if let value = newer.preferredDistanceUnit { preferredDistanceUnit = value }
        if let value = newer.workoutNotificationStyle { workoutNotificationStyle = value }
        if let value = newer.automaticallyClosesCompletedExercises {
            automaticallyClosesCompletedExercises = value
        }
        if let value = newer.showsCalorieEstimates {
            showsCalorieEstimates = value
        }
    }
}

nonisolated struct RevisionedSettingsWrite: Equatable, Sendable {
    let revision: UInt64
    let patch: UserSettingsPatch
}

actor OrderedSettingsWriter {
    typealias Persist = @Sendable (RevisionedSettingsWrite) async throws -> UserSettingsDraft
    typealias Commit = @Sendable (UInt64, RevisionedSettingsWrite, UserSettingsDraft) async -> Void
    typealias Failure = @Sendable (RevisionedSettingsWrite, String) async -> Void

    private let persist: Persist
    private let onCommit: Commit
    private let onFailure: Failure
    private var newestSubmittedRevision: UInt64 = 0
    private var pendingWrite: RevisionedSettingsWrite?
    private var workerTask: Task<Void, Never>?
    private var lastFailedWrite: RevisionedSettingsWrite?
    private var undeliveredPersistedPatch: UserSettingsPatch?
    private var undeliveredPersistedDraft: UserSettingsDraft?

    init(
        persist: @escaping Persist,
        onCommit: @escaping Commit,
        onFailure: @escaping Failure
    ) {
        self.persist = persist
        self.onCommit = onCommit
        self.onFailure = onFailure
    }

    func submit(_ write: RevisionedSettingsWrite) {
        newestSubmittedRevision = max(newestSubmittedRevision, write.revision)
        if let pendingWrite {
            var mergedPatch = pendingWrite.patch
            mergedPatch.merge(write.patch)
            self.pendingWrite = RevisionedSettingsWrite(
                revision: write.revision,
                patch: mergedPatch
            )
        } else {
            pendingWrite = write
        }
        startWorkerIfNeeded()
    }

    func flush() async {
        while let workerTask {
            await workerTask.value
        }
    }

    func retryLatest(as revision: UInt64) {
        guard let lastFailedWrite else { return }
        self.lastFailedWrite = nil
        submit(RevisionedSettingsWrite(revision: revision, patch: lastFailedWrite.patch))
    }

    private func startWorkerIfNeeded() {
        guard workerTask == nil else { return }
        workerTask = Task { [weak self] in
            await self?.runWorker()
        }
    }

    private func runWorker() async {
        while let write = pendingWrite {
            pendingWrite = nil
            do {
                let draft = try await persist(write)
                lastFailedWrite = nil
                if write.revision == newestSubmittedRevision {
                    var deliveredPatch = undeliveredPersistedPatch ?? UserSettingsPatch()
                    deliveredPatch.merge(write.patch)
                    undeliveredPersistedPatch = nil
                    undeliveredPersistedDraft = nil
                    await onCommit(
                        write.revision,
                        RevisionedSettingsWrite(
                            revision: write.revision,
                            patch: deliveredPatch
                        ),
                        draft
                    )
                } else if var undeliveredPersistedPatch {
                    undeliveredPersistedPatch.merge(write.patch)
                    self.undeliveredPersistedPatch = undeliveredPersistedPatch
                    undeliveredPersistedDraft = draft
                } else {
                    undeliveredPersistedPatch = write.patch
                    undeliveredPersistedDraft = draft
                }
            } catch {
                if mergeFailedWriteIntoPending(write) {
                    continue
                }
                lastFailedWrite = write
                if write.revision == newestSubmittedRevision {
                    await deliverUndeliveredPersistedWrite(as: write.revision)
                    await onFailure(write, String(describing: error))
                }
            }
        }
        workerTask = nil
        if pendingWrite != nil {
            startWorkerIfNeeded()
        }
    }

    private func mergeFailedWriteIntoPending(_ failedWrite: RevisionedSettingsWrite) -> Bool {
        guard let pendingWrite else { return false }
        var mergedPatch = failedWrite.patch
        mergedPatch.merge(pendingWrite.patch)
        self.pendingWrite = RevisionedSettingsWrite(
            revision: pendingWrite.revision,
            patch: mergedPatch
        )
        return true
    }

    private func deliverUndeliveredPersistedWrite(as revision: UInt64) async {
        guard let patch = undeliveredPersistedPatch,
              let draft = undeliveredPersistedDraft else {
            return
        }
        undeliveredPersistedPatch = nil
        undeliveredPersistedDraft = nil
        await onCommit(
            revision,
            RevisionedSettingsWrite(revision: revision, patch: patch),
            draft
        )
    }
}

nonisolated struct RevisionedSettingsCommit: Equatable, Sendable {
    let revision: UInt64
    let write: RevisionedSettingsWrite
    let persistedDraft: UserSettingsDraft
}

@MainActor
@Observable
final class SettingsDraftCoordinator {
    private(set) var latestCommit: RevisionedSettingsCommit?
    private(set) var errorDescription: String?
    private(set) var reconciliationDraft: UserSettingsDraft?
    private(set) var revision: UInt64 = 0

    @ObservationIgnored private var writer: OrderedSettingsWriter?
    @ObservationIgnored private var submissionTask: Task<Void, Never>?
    @ObservationIgnored private var lastPersistedDraft: UserSettingsDraft?

    func configure(
        persist: @escaping OrderedSettingsWriter.Persist
    ) {
        guard writer == nil else { return }
        writer = OrderedSettingsWriter(
            persist: persist,
            onCommit: { [weak self] revision, write, draft in
                await self?.receiveCommit(revision: revision, write: write, draft: draft)
            },
            onFailure: { [weak self] _, description in
                await self?.receiveFailure(description)
            }
        )
    }

    func synchronizePersistedDraft(_ draft: UserSettingsDraft) {
        lastPersistedDraft = draft
        reconciliationDraft = nil
    }

    @discardableResult
    func submit(_ patch: UserSettingsPatch) -> UInt64 {
        guard let writer else { return revision }
        revision &+= 1
        let write = RevisionedSettingsWrite(revision: revision, patch: patch)
        let previousSubmission = submissionTask
        submissionTask = Task {
            await previousSubmission?.value
            await writer.submit(write)
        }
        errorDescription = nil
        reconciliationDraft = nil
        return revision
    }

    func flush() async {
        await submissionTask?.value
        submissionTask = nil
        await writer?.flush()
    }

    func retryLatest() {
        guard let writer else { return }
        revision &+= 1
        let retryRevision = revision
        Task {
            await writer.retryLatest(as: retryRevision)
        }
    }

    private func receiveCommit(
        revision: UInt64,
        write: RevisionedSettingsWrite,
        draft: UserSettingsDraft
    ) {
        lastPersistedDraft = draft
        guard revision == self.revision else { return }
        errorDescription = nil
        latestCommit = RevisionedSettingsCommit(
            revision: revision,
            write: write,
            persistedDraft: draft
        )
    }

    private func receiveFailure(_ description: String) {
        reconciliationDraft = lastPersistedDraft
        errorDescription = description
    }
}
