import Foundation
import SwiftData

enum HistoryDetailSnapshotBuilder {
    nonisolated struct Snapshot: Equatable, Sendable {
        let session: SessionSnapshot
        let cardioBlocks: [CardioBlockSnapshot]
        let exercises: [ExerciseSnapshot]
        let preferredLoadUnit: TemplateLoadUnit
        let localState: LocalState
        let hydrationPayloadByExerciseID: [UUID: ExerciseHydrationPayload]
        let muscleHeatmap: WorkoutMuscleHeatmapSnapshot
        let personalRecordHighlights: [PersonalRecordHighlight]
    }

    nonisolated struct SessionSnapshot: Identifiable, Equatable, Sendable {
        let id: UUID
        let name: String
        let startedAt: Date
        let endedAt: Date?
        let durationSeconds: Int
        let prHitsCount: Int
        let notes: String
        let updatedAt: Date

        nonisolated init(model: WorkoutSession) {
            id = model.id
            name = model.name
            startedAt = model.startedAt
            endedAt = model.endedAt
            durationSeconds = model.durationSeconds
            prHitsCount = model.prHitsCount
            notes = model.notes
            updatedAt = model.updatedAt
        }

        var resolvedDurationSeconds: Int {
            if durationSeconds > 0 {
                return durationSeconds
            }
            guard let endedAt else { return 0 }
            return max(0, Int(endedAt.timeIntervalSince(startedAt)))
        }
    }

    nonisolated struct CardioBlockSnapshot: Identifiable, Equatable, Sendable {
        let id: UUID
        let phase: WorkoutCardioPhase
        let role: WorkoutCardioRole
        let sortOrder: Int
        let catalogExerciseUUID: String
        let exerciseNameSnapshot: String
        let categorySnapshot: String
        let muscleSummarySnapshot: String
        let trackingProfile: WorkoutCardioTrackingProfile
        let targetDurationSeconds: Int
        let actualDurationSeconds: Int?
        let actualDistanceMeters: Double?
        let preferredDistanceUnit: WorkoutDistanceUnit
        let inclinePercent: Double?
        let resistanceLevel: Double?
        let notes: String
        let isCompleted: Bool
        let updatedAt: Date
        let resultSummary: WorkoutCardioResultSummary

        nonisolated init(model: WorkoutSessionCardioBlock) {
            id = model.id
            phase = model.phase
            role = model.role
            sortOrder = model.sortOrder
            catalogExerciseUUID = model.catalogExerciseUUID
            exerciseNameSnapshot = model.exerciseNameSnapshot
            categorySnapshot = model.categorySnapshot
            muscleSummarySnapshot = model.muscleSummarySnapshot
            let resolvedTrackingProfile = WorkoutCardioTrackingProfileResolver.resolved(
                storedProfile: model.trackingProfile,
                identity: "\(model.catalogExerciseUUID) \(model.exerciseNameSnapshot)",
                hasDistance: model.actualDistanceMeters != nil || model.targetDistanceMeters != nil
            )
            trackingProfile = resolvedTrackingProfile
            targetDurationSeconds = model.targetDurationSeconds
            actualDurationSeconds = model.actualDurationSeconds
            actualDistanceMeters = model.actualDistanceMeters
            preferredDistanceUnit = model.preferredDistanceUnit ?? .kilometers
            inclinePercent = model.inclinePercent
            resistanceLevel = model.resistanceLevel
            notes = model.cardioNotes
            isCompleted = model.isCompleted
            updatedAt = model.updatedAt
            resultSummary = WorkoutCardioResultSummaryFormatter.summary(
                durationSeconds: model.actualDurationSeconds,
                distanceMeters: model.actualDistanceMeters,
                displayUnit: model.preferredDistanceUnit ?? .kilometers,
                profile: resolvedTrackingProfile,
                inclinePercent: model.inclinePercent,
                resistanceLevel: model.resistanceLevel,
                notes: model.cardioNotes
            )
        }

        var resultDraft: WorkoutCardioResultDraft {
            WorkoutCardioResultDraft(
                actualDurationSeconds: actualDurationSeconds,
                actualDistanceMeters: actualDistanceMeters,
                distanceUnit: preferredDistanceUnit,
                inclinePercent: inclinePercent,
                resistanceLevel: resistanceLevel,
                notes: notes,
                trackingProfile: trackingProfile
            )
        }

    }

    nonisolated struct ExerciseSnapshot: Identifiable, Equatable, Sendable {
        let id: UUID
        let catalogExerciseUUID: String
        let exerciseNameSnapshot: String
        let categorySnapshot: String
        let muscleSummarySnapshot: String
        let notes: String
        let targetRepMin: Int?
        let targetRepMax: Int?
        let restSeconds: Int
        let totalSetCount: Int
        let completedSetCount: Int
        let hasDropsets: Bool
        let supersetGroupID: UUID?
        let supersetPosition: SupersetExercisePosition?
        let updatedAt: Date
        let usesAddedWeight: Bool
        let usesAssistance: Bool

        nonisolated init(model: WorkoutSessionExercise, usesAddedWeight: Bool = false, usesAssistance: Bool = false) {
            self.usesAddedWeight = usesAddedWeight
            self.usesAssistance = usesAssistance
            id = model.id
            catalogExerciseUUID = model.catalogExerciseUUID
            exerciseNameSnapshot = model.exerciseNameSnapshot
            categorySnapshot = model.categorySnapshot
            muscleSummarySnapshot = model.muscleSummarySnapshot
            notes = model.notes
            targetRepMin = model.targetRepMin
            targetRepMax = model.targetRepMax
            restSeconds = model.restSeconds
            totalSetCount = model.totalSetCount
            completedSetCount = model.completedSetCount
            hasDropsets = model.hasDropsets
            supersetGroupID = model.supersetGroupID
            supersetPosition = model.supersetPosition
            updatedAt = model.updatedAt
        }
    }

    nonisolated struct LocalState: Equatable, Sendable {
        let setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
        let restByExerciseID: [UUID: Int]
        let notesByExerciseID: [UUID: String]

        static let empty = LocalState(
            setDraftsByExerciseID: [:],
            restByExerciseID: [:],
            notesByExerciseID: [:]
        )
    }

    nonisolated struct ExerciseHydrationPayload: Equatable, Sendable {
        let previousPerformanceResolution: WorkoutPreviousPerformanceResolution
        let personalRecords: HistoryExercisePersonalRecordPresentation
    }

    nonisolated struct PersonalRecordHighlight: Identifiable, Equatable, Sendable {
        let id: String
        let sessionExerciseID: UUID
        let setID: UUID
        let exerciseName: String
        let setTitle: String
        let performanceText: String
        let detailText: String
        let kinds: [WorkoutPersonalRecordKind]
    }

    nonisolated static func load(
        modelContext: ModelContext,
        sessionID: UUID,
        hydrationExerciseIDs: Set<UUID>? = nil
    ) throws -> Snapshot {
        let repository = WorkoutSessionRepository(modelContext: modelContext)
        guard let session = try repository.session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let exercises = try repository.sessionExercises(sessionID: sessionID)
        let addedWeightIDs = try repository.addedWeightExerciseIDs(Set(exercises.map(\.catalogExerciseUUID)))
        let assistanceIDs = try repository.assistanceExerciseIDs(Set(exercises.map(\.catalogExerciseUUID)))
        let cardioBlocks = try repository.sessionCardioBlocks(sessionID: sessionID)
        let preferredLoadUnit = (try? ProfileRepository(modelContext: modelContext)
            .currentProfile()?.preferredLoadUnit) ?? .kg
        let localState = try localState(for: exercises, repository: repository)
        let requestedHydrationIDs = hydrationExerciseIDs ?? Set(exercises.map(\.id))
        let hydrationExercises = exercises.filter { requestedHydrationIDs.contains($0.id) }
        let personalRecordAchievements: [SessionSetPRAchievement]
        if exercises.isEmpty {
            personalRecordAchievements = []
        } else {
            personalRecordAchievements = try WorkoutMetricsService(modelContext: modelContext)
                .sessionSetPRAchievements(sessionID: session.id)
        }
        let hydrationPayloadByExerciseID = try hydrationPayloads(
            modelContext: modelContext,
            session: session,
            exercises: hydrationExercises,
            draftsByExerciseID: localState.setDraftsByExerciseID,
            personalRecordAchievements: personalRecordAchievements
        )
        let muscleHeatmap: WorkoutMuscleHeatmapSnapshot = if exercises.isEmpty {
            .empty
        } else {
            try muscleHeatmap(
                modelContext: modelContext,
                exercises: exercises,
                repository: repository
            )
        }
        let personalRecordHighlights = personalRecordHighlights(
            from: personalRecordAchievements,
            draftsByExerciseID: localState.setDraftsByExerciseID
        )

        return Snapshot(
            session: SessionSnapshot(model: session),
            cardioBlocks: cardioBlocks.map(CardioBlockSnapshot.init(model:)),
            exercises: exercises.map { ExerciseSnapshot(model: $0, usesAddedWeight: addedWeightIDs.contains($0.catalogExerciseUUID), usesAssistance: assistanceIDs.contains($0.catalogExerciseUUID)) },
            preferredLoadUnit: preferredLoadUnit,
            localState: localState,
            hydrationPayloadByExerciseID: hydrationPayloadByExerciseID,
            muscleHeatmap: muscleHeatmap,
            personalRecordHighlights: personalRecordHighlights
        )
    }

    nonisolated static func loadHydrationPayloads(
        modelContext: ModelContext,
        sessionID: UUID,
        exerciseIDs: Set<UUID>
    ) throws -> [UUID: ExerciseHydrationPayload] {
        guard !exerciseIDs.isEmpty else { return [:] }

        let repository = WorkoutSessionRepository(modelContext: modelContext)
        guard let session = try repository.session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let exercises = try repository.sessionExercises(sessionID: sessionID)
            .filter { exerciseIDs.contains($0.id) }
        guard !exercises.isEmpty else { return [:] }

        let localState = try localState(for: exercises, repository: repository)
        return try hydrationPayloads(
            modelContext: modelContext,
            session: session,
            exercises: exercises,
            draftsByExerciseID: localState.setDraftsByExerciseID,
            personalRecordAchievements: try WorkoutMetricsService(modelContext: modelContext)
                .sessionSetPRAchievements(sessionID: session.id)
        )
    }

    nonisolated static func orderedSessionSets(for exercise: WorkoutSessionExercise) -> [WorkoutSessionSet] {
        (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    nonisolated static func makeDrafts(from exercise: WorkoutSessionExercise) -> [WorkoutSessionSetDraft] {
        orderedSessionSets(for: exercise).map(WorkoutSessionSetDraft.init(model:))
    }

    nonisolated private static func makeDrafts(
        from exercise: WorkoutSessionExercise,
        repository: WorkoutSessionRepository
    ) throws -> [WorkoutSessionSetDraft] {
        try repository.sessionSets(sessionExerciseID: exercise.id).map(WorkoutSessionSetDraft.init(model:))
    }

    nonisolated private static func localState(
        for exercises: [WorkoutSessionExercise],
        repository: WorkoutSessionRepository
    ) throws -> LocalState {
        LocalState(
            setDraftsByExerciseID: Dictionary(
                try exercises.map { ($0.id, try makeDrafts(from: $0, repository: repository)) },
                uniquingKeysWith: { first, _ in first }
            ),
            restByExerciseID: Dictionary(
                exercises.map { ($0.id, $0.restSeconds) },
                uniquingKeysWith: { first, _ in first }
            ),
            notesByExerciseID: Dictionary(
                exercises.map { ($0.id, $0.notes) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    nonisolated private static func hydrationPayloads(
        modelContext: ModelContext,
        session: WorkoutSession,
        exercises: [WorkoutSessionExercise],
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]],
        personalRecordAchievements: [SessionSetPRAchievement]
    ) throws -> [UUID: ExerciseHydrationPayload] {
        guard !exercises.isEmpty else { return [:] }

        let exerciseIDs = Set(exercises.map(\.id))
        let personalRecords = HistoryExercisePersonalRecordPresentation.presentationsByExerciseID(
            from: personalRecordAchievements,
            exerciseIDs: exerciseIDs
        )
        let previousResolutions = try WorkoutPreviousPerformanceLookup(modelContext: modelContext).load(
            requests: exercises.map { .init(id: $0.id, catalogExerciseUUID: $0.catalogExerciseUUID,
                templateExerciseID: $0.templateExerciseID, drafts: draftsByExerciseID[$0.id] ?? makeDrafts(from: $0)) },
            templateID: session.templateID, before: session.startedAt, excludingSessionID: session.id
        )

        var payloadByExerciseID: [UUID: ExerciseHydrationPayload] = [:]
        payloadByExerciseID.reserveCapacity(exercises.count)

        for exercise in exercises {
            payloadByExerciseID[exercise.id] = ExerciseHydrationPayload(
                previousPerformanceResolution: previousResolutions[exercise.id] ?? .resolved([:]),
                personalRecords: personalRecords[exercise.id]
                    ?? HistoryExercisePersonalRecordPresentation(summaryKinds: [], setKindsBySetID: [:])
            )
        }

        return payloadByExerciseID
    }

    nonisolated private static func personalRecordHighlights(
        from achievements: [SessionSetPRAchievement],
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) -> [PersonalRecordHighlight] {
        achievements.map { achievement in
            PersonalRecordHighlight(
                id: achievement.id,
                sessionExerciseID: achievement.sessionExerciseID,
                setID: achievement.setID,
                exerciseName: achievement.exerciseName,
                setTitle: setTitle(for: achievement, draftsByExerciseID: draftsByExerciseID),
                performanceText: performanceText(for: achievement),
                detailText: detailText(for: achievement),
                kinds: achievement.kinds
            )
        }
    }

    nonisolated private static func setTitle(
        for achievement: SessionSetPRAchievement,
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) -> String {
        guard let drafts = draftsByExerciseID[achievement.sessionExerciseID],
              let index = drafts.firstIndex(where: { $0.id == achievement.setID })
        else {
            return "PR Set"
        }

        if drafts[index].isWarmup {
            return "Warmup Set"
        }

        let workingSetNumber = drafts.prefix(index + 1).filter { !$0.isWarmup }.count
        return "Working Set \(max(workingSetNumber, 1))"
    }

    nonisolated private static func performanceText(for achievement: SessionSetPRAchievement) -> String {
        achievement.performanceText
    }

    nonisolated private static func detailText(for achievement: SessionSetPRAchievement) -> String {
        achievement.detailText
    }

    nonisolated private static func muscleHeatmap(
        modelContext: ModelContext,
        exercises: [WorkoutSessionExercise],
        repository: WorkoutSessionRepository
    ) throws -> WorkoutMuscleHeatmapSnapshot {
        guard !exercises.isEmpty else { return .empty }

        let catalogMappings = try WorkoutMuscleHeatmapBuilder.catalogMappings(modelContext: modelContext)
        var scores: [ExerciseBodyMapRegion: Double] = [:]
        for exercise in exercises {
            let exerciseScores = WorkoutMuscleHeatmapBuilder.scores(
                for: exercise,
                sets: try repository.sessionSets(sessionExerciseID: exercise.id),
                catalogMappings: catalogMappings
            )
            for (region, score) in exerciseScores {
                scores[region, default: 0] += score
            }
        }
        return WorkoutMuscleHeatmapBuilder.snapshot(scores: scores)
    }

}

nonisolated struct HistoryDetailPreservedExerciseEditState: Equatable, Sendable {
    let baseline: HistoryDetailSnapshotBuilder.LocalState
    let drafts: WorkoutExerciseDraftStateSnapshot
}

nonisolated enum HistoryDetailCardioRefreshPolicy {
    static func preserveExerciseEdits(
        baseline: HistoryDetailSnapshotBuilder.LocalState,
        drafts: WorkoutExerciseDraftStateSnapshot,
        keeping exerciseIDs: Set<UUID>
    ) -> HistoryDetailPreservedExerciseEditState {
        HistoryDetailPreservedExerciseEditState(
            baseline: HistoryDetailSnapshotBuilder.LocalState(
                setDraftsByExerciseID: baseline.setDraftsByExerciseID.filter {
                    exerciseIDs.contains($0.key)
                },
                restByExerciseID: baseline.restByExerciseID.filter {
                    exerciseIDs.contains($0.key)
                },
                notesByExerciseID: baseline.notesByExerciseID.filter {
                    exerciseIDs.contains($0.key)
                }
            ),
            drafts: WorkoutExerciseDraftStateSnapshot(
                draftsByExerciseID: drafts.draftsByExerciseID.filter {
                    exerciseIDs.contains($0.key)
                },
                restsByExerciseID: drafts.restsByExerciseID.filter {
                    exerciseIDs.contains($0.key)
                },
                notesByExerciseID: drafts.notesByExerciseID.filter {
                    exerciseIDs.contains($0.key)
                }
            )
        )
    }

    static func isDirty(
        exerciseID: UUID,
        state: HistoryDetailPreservedExerciseEditState
    ) -> Bool {
        state.drafts.draftsByExerciseID[exerciseID]
            != state.baseline.setDraftsByExerciseID[exerciseID]
            || state.drafts.restsByExerciseID[exerciseID]
                != state.baseline.restByExerciseID[exerciseID]
            || state.drafts.notesByExerciseID[exerciseID]
                != state.baseline.notesByExerciseID[exerciseID]
    }
}
