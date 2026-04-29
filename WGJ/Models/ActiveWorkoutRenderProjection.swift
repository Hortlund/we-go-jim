import Foundation

nonisolated struct ActiveWorkoutSupersetContext: Equatable, Sendable {
    let position: SupersetExercisePosition
    let roundRestSeconds: Int
    let pairedExerciseID: UUID
}

nonisolated struct ActiveWorkoutRenderProjection {
    var session: ActiveWorkoutRuntimeSession?
    var sessionExercises: [ActiveWorkoutRuntimeExercise]
    var orderedCardioBlocks: [ActiveWorkoutRuntimeCardioBlock]
    var exerciseDisplayGroups: [WorkoutExerciseDisplayGroup<ActiveWorkoutRuntimeExercise>]
    var exerciseIDs: [UUID]
    var preWorkoutCardio: ActiveWorkoutRuntimeCardioBlock?
    var postWorkoutCardio: ActiveWorkoutRuntimeCardioBlock?
    var cardioByPhase: [WorkoutCardioPhase: ActiveWorkoutRuntimeCardioBlock]
    var missingCardioPhases: [WorkoutCardioPhase]
    var areMainExercisesUnlocked: Bool
    var areAllMainExercisesCompleted: Bool
    var isPostWorkoutCardioUnlocked: Bool
    var hasWorkoutContent: Bool
    var supersetContextByExerciseID: [UUID: ActiveWorkoutSupersetContext]

    static let empty = ActiveWorkoutRenderProjection(
        session: nil,
        sessionExercises: [],
        orderedCardioBlocks: [],
        exerciseDisplayGroups: [],
        exerciseIDs: [],
        preWorkoutCardio: nil,
        postWorkoutCardio: nil,
        cardioByPhase: [:],
        missingCardioPhases: WorkoutCardioPhase.allCases,
        areMainExercisesUnlocked: true,
        areAllMainExercisesCompleted: true,
        isPostWorkoutCardioUnlocked: true,
        hasWorkoutContent: false,
        supersetContextByExerciseID: [:]
    )
}

nonisolated enum ActiveWorkoutRenderProjectionBuilder {
    static func build(
        session: ActiveWorkoutRuntimeSession?,
        setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]],
        pendingCardioCompletionsByPhase: [WorkoutCardioPhase: Bool]
    ) -> ActiveWorkoutRenderProjection {
        guard let session else {
            return .empty
        }

        let exercises = session.exercises.sorted { $0.sortOrder < $1.sortOrder }
        let cardioBlocks = session.cardioBlocks
            .map { cardioBlock in
                var updated = cardioBlock
                if let completion = pendingCardioCompletionsByPhase[cardioBlock.phase] {
                    updated.isCompleted = completion
                }
                return updated
            }
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
        let cardioByPhase = Dictionary(
            cardioBlocks.map { ($0.phase, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let preWorkoutCardio = cardioByPhase[.preWorkout]
        let postWorkoutCardio = cardioByPhase[.postWorkout]
        let areMainExercisesUnlocked = preWorkoutCardio?.isCompleted ?? true
        let areAllMainExercisesCompleted = exercises.allSatisfy { exercise in
            let drafts = setDraftsByExerciseID[exercise.id] ?? exercise.setDrafts
            return isExerciseCompleted(drafts)
        }
        let displayGroups = WorkoutExerciseDisplayGrouping.build(
            items: exercises,
            membership: { exercise in
                exercise.superset
            }
        )

        return ActiveWorkoutRenderProjection(
            session: session,
            sessionExercises: exercises,
            orderedCardioBlocks: cardioBlocks,
            exerciseDisplayGroups: displayGroups,
            exerciseIDs: exercises.map(\.id),
            preWorkoutCardio: preWorkoutCardio,
            postWorkoutCardio: postWorkoutCardio,
            cardioByPhase: cardioByPhase,
            missingCardioPhases: WorkoutCardioPhase.allCases.filter { cardioByPhase[$0] == nil },
            areMainExercisesUnlocked: areMainExercisesUnlocked,
            areAllMainExercisesCompleted: areAllMainExercisesCompleted,
            isPostWorkoutCardioUnlocked: areMainExercisesUnlocked && areAllMainExercisesCompleted,
            hasWorkoutContent: !exercises.isEmpty || !cardioBlocks.isEmpty,
            supersetContextByExerciseID: supersetContextByExerciseID(from: displayGroups)
        )
    }

    private static func isExerciseCompleted(_ drafts: [WorkoutSessionSetDraft]) -> Bool {
        !drafts.isEmpty && drafts.allSatisfy(\.isCycleCompleted)
    }

    private static func supersetContextByExerciseID(
        from groups: [WorkoutExerciseDisplayGroup<ActiveWorkoutRuntimeExercise>]
    ) -> [UUID: ActiveWorkoutSupersetContext] {
        var contexts: [UUID: ActiveWorkoutSupersetContext] = [:]

        for group in groups {
            guard case .superset(let superset) = group else { continue }
            contexts[superset.first.id] = ActiveWorkoutSupersetContext(
                position: .first,
                roundRestSeconds: superset.roundRestSeconds,
                pairedExerciseID: superset.second.id
            )
            contexts[superset.second.id] = ActiveWorkoutSupersetContext(
                position: .second,
                roundRestSeconds: superset.roundRestSeconds,
                pairedExerciseID: superset.first.id
            )
        }

        return contexts
    }
}
