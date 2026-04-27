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
        let catalogExerciseUUID: String
        let exerciseNameSnapshot: String
        let categorySnapshot: String
        let muscleSummarySnapshot: String
        let targetDurationSeconds: Int
        let isCompleted: Bool
        let updatedAt: Date

        nonisolated init(model: WorkoutSessionCardioBlock) {
            id = model.id
            phase = model.phase
            catalogExerciseUUID = model.catalogExerciseUUID
            exerciseNameSnapshot = model.exerciseNameSnapshot
            categorySnapshot = model.categorySnapshot
            muscleSummarySnapshot = model.muscleSummarySnapshot
            targetDurationSeconds = model.targetDurationSeconds
            isCompleted = model.isCompleted
            updatedAt = model.updatedAt
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

        nonisolated init(model: WorkoutSessionExercise) {
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

    nonisolated static func load(
        modelContext: ModelContext,
        sessionID: UUID
    ) throws -> Snapshot {
        let repository = WorkoutSessionRepository(modelContext: modelContext)
        guard let session = try repository.session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let exercises = try repository.sessionExercises(sessionID: sessionID)
        let cardioBlocks = try repository.sessionCardioBlocks(sessionID: sessionID)
        let preferredLoadUnit = (try? ProfileRepository(modelContext: modelContext)
            .currentProfile()?.preferredLoadUnit) ?? .kg
        let localState = localState(for: exercises)
        let hydrationPayloadByExerciseID = try hydrationPayloads(
            modelContext: modelContext,
            session: session,
            exercises: exercises,
            draftsByExerciseID: localState.setDraftsByExerciseID
        )

        return Snapshot(
            session: SessionSnapshot(model: session),
            cardioBlocks: cardioBlocks.map(CardioBlockSnapshot.init(model:)),
            exercises: exercises.map(ExerciseSnapshot.init(model:)),
            preferredLoadUnit: preferredLoadUnit,
            localState: localState,
            hydrationPayloadByExerciseID: hydrationPayloadByExerciseID
        )
    }

    nonisolated static func orderedSessionSets(for exercise: WorkoutSessionExercise) -> [WorkoutSessionSet] {
        (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    nonisolated static func makeDrafts(from exercise: WorkoutSessionExercise) -> [WorkoutSessionSetDraft] {
        orderedSessionSets(for: exercise).map(WorkoutSessionSetDraft.init(model:))
    }

    nonisolated private static func localState(for exercises: [WorkoutSessionExercise]) -> LocalState {
        LocalState(
            setDraftsByExerciseID: Dictionary(
                exercises.map { ($0.id, makeDrafts(from: $0)) },
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
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) throws -> [UUID: ExerciseHydrationPayload] {
        guard !exercises.isEmpty else { return [:] }

        let exerciseIDs = Set(exercises.map(\.id))
        let personalRecords = try HistoryExercisePersonalRecordPresentation.presentationsByExerciseID(
            from: WorkoutMetricsService(modelContext: modelContext)
                .sessionSetPRAchievements(sessionID: session.id),
            exerciseIDs: exerciseIDs
        )
        let previousMaps = try WorkoutSessionRepository(modelContext: modelContext).previousSetMaps(
            forExercises: Array(Set(exercises.map(\.catalogExerciseUUID))),
            before: session.startedAt,
            excludingSessionID: session.id
        )

        var payloadByExerciseID: [UUID: ExerciseHydrationPayload] = [:]
        payloadByExerciseID.reserveCapacity(exercises.count)

        for exercise in exercises {
            let drafts = draftsByExerciseID[exercise.id] ?? makeDrafts(from: exercise)
            payloadByExerciseID[exercise.id] = ExerciseHydrationPayload(
                previousPerformanceResolution: .resolved(
                    resolvedPreviousMap(
                        baseMap: previousMaps[exercise.catalogExerciseUUID] ?? [:],
                        maxSetCount: drafts.count
                    )
                ),
                personalRecords: personalRecords[exercise.id]
                    ?? HistoryExercisePersonalRecordPresentation(summaryKinds: [], setKindsBySetID: [:])
            )
        }

        return payloadByExerciseID
    }

    nonisolated private static func resolvedPreviousMap(
        baseMap: [Int: WorkoutPreviousSetSnapshot],
        maxSetCount: Int
    ) -> [Int: WorkoutPreviousSetSnapshot] {
        guard maxSetCount > 0, !baseMap.isEmpty else { return [:] }

        let fallback = baseMap[(baseMap.keys.max() ?? 0)]
        var resolved: [Int: WorkoutPreviousSetSnapshot] = [:]
        resolved.reserveCapacity(maxSetCount)

        for index in 0..<maxSetCount {
            if let exact = baseMap[index] {
                resolved[index] = exact
            } else if let fallback {
                resolved[index] = fallback
            }
        }

        return resolved
    }
}
