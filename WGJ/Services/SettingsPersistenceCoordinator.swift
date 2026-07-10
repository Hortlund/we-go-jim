import Foundation
import Observation

nonisolated struct UserSettingsDraft: Equatable, Sendable {
    var weeklyWorkoutGoal: Int
    var isTrainingGuidanceEnabled: Bool
    var keepsScreenAwake: Bool
    var preferredWeightUnit: PreferredWeightUnit
    var workoutNotificationStyle: WorkoutNotificationStyle

    static let `default` = UserSettingsDraft(
        weeklyWorkoutGoal: 4,
        isTrainingGuidanceEnabled: true,
        keepsScreenAwake: false,
        preferredWeightUnit: .kg,
        workoutNotificationStyle: .timeSensitive
    )

    init(
        weeklyWorkoutGoal: Int,
        isTrainingGuidanceEnabled: Bool,
        keepsScreenAwake: Bool,
        preferredWeightUnit: PreferredWeightUnit,
        workoutNotificationStyle: WorkoutNotificationStyle
    ) {
        self.weeklyWorkoutGoal = weeklyWorkoutGoal
        self.isTrainingGuidanceEnabled = isTrainingGuidanceEnabled
        self.keepsScreenAwake = keepsScreenAwake
        self.preferredWeightUnit = preferredWeightUnit
        self.workoutNotificationStyle = workoutNotificationStyle
    }

    init(profile: UserProfile) {
        self.init(
            weeklyWorkoutGoal: profile.weeklyWorkoutGoal,
            isTrainingGuidanceEnabled: profile.isTrainingGuidanceEnabled,
            keepsScreenAwake: profile.keepsScreenAwake,
            preferredWeightUnit: profile.preferredWeightUnit,
            workoutNotificationStyle: profile.workoutNotificationStyle
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
        if let value = patch.workoutNotificationStyle {
            workoutNotificationStyle = value
        }
    }
}

nonisolated struct UserSettingsPatch: Equatable, Sendable {
    var weeklyWorkoutGoal: Int?
    var isTrainingGuidanceEnabled: Bool?
    var keepsScreenAwake: Bool?
    var preferredWeightUnit: PreferredWeightUnit?
    var workoutNotificationStyle: WorkoutNotificationStyle?

    init(
        weeklyWorkoutGoal: Int? = nil,
        isTrainingGuidanceEnabled: Bool? = nil,
        keepsScreenAwake: Bool? = nil,
        preferredWeightUnit: PreferredWeightUnit? = nil,
        workoutNotificationStyle: WorkoutNotificationStyle? = nil
    ) {
        self.weeklyWorkoutGoal = weeklyWorkoutGoal
        self.isTrainingGuidanceEnabled = isTrainingGuidanceEnabled
        self.keepsScreenAwake = keepsScreenAwake
        self.preferredWeightUnit = preferredWeightUnit
        self.workoutNotificationStyle = workoutNotificationStyle
    }

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
                    await onCommit(write.revision, write, draft)
                }
            } catch {
                lastFailedWrite = write
                if write.revision == newestSubmittedRevision {
                    await onFailure(write, String(describing: error))
                }
            }
        }
        workerTask = nil
        if pendingWrite != nil {
            startWorkerIfNeeded()
        }
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
    private(set) var revision: UInt64 = 0

    @ObservationIgnored private var writer: OrderedSettingsWriter?
    @ObservationIgnored private var submissionTask: Task<Void, Never>?

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
        guard revision == self.revision else { return }
        errorDescription = nil
        latestCommit = RevisionedSettingsCommit(
            revision: revision,
            write: write,
            persistedDraft: draft
        )
    }

    private func receiveFailure(_ description: String) {
        errorDescription = description
    }
}
