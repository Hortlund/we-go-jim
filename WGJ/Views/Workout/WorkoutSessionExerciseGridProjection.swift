import Foundation

nonisolated struct WorkoutDropStageLocation: Equatable, Sendable {
    let setIndex: Int
    let stageIndex: Int
}

nonisolated struct WorkoutSessionExerciseSetRowDisplaySnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let index: Int
    let set: WorkoutSessionSetDraft
    let badgeTitle: String
    let title: String
    let previousSummary: String
    let metadataLine: String?
    let inlineHintPresentation: WorkoutSetInlineHintPresentation?
    let completionButtonTitle: String
}

nonisolated struct WorkoutSessionExerciseGridProjection: Equatable, Sendable {
    let rows: [WorkoutSessionExerciseSetRowDisplaySnapshot]
    let indexBySetID: [UUID: Int]
    let workingSetNumberBySetID: [UUID: Int]
    let dropStageLocationByID: [UUID: WorkoutDropStageLocation]
    let completedSetCount: Int

    static let empty = WorkoutSessionExerciseGridProjection(
        rows: [],
        indexBySetID: [:],
        workingSetNumberBySetID: [:],
        dropStageLocationByID: [:],
        completedSetCount: 0
    )

    func updatingCompletedSetCount(_ count: Int) -> WorkoutSessionExerciseGridProjection {
        WorkoutSessionExerciseGridProjection(
            rows: rows,
            indexBySetID: indexBySetID,
            workingSetNumberBySetID: workingSetNumberBySetID,
            dropStageLocationByID: dropStageLocationByID,
            completedSetCount: count
        )
    }
}

nonisolated enum WorkoutSessionExerciseGridProjectionBuilder {
    typealias RowBuilder = (
        _ draft: WorkoutSessionSetDraft,
        _ index: Int,
        _ workingSetNumber: Int
    ) -> WorkoutSessionExerciseSetRowDisplaySnapshot

    static func build(
        setDrafts: [WorkoutSessionSetDraft],
        rowBuilder: RowBuilder
    ) -> WorkoutSessionExerciseGridProjection {
        var rows: [WorkoutSessionExerciseSetRowDisplaySnapshot] = []
        var indexBySetID: [UUID: Int] = [:]
        var workingSetNumberBySetID: [UUID: Int] = [:]
        var dropStageLocationByID: [UUID: WorkoutDropStageLocation] = [:]
        rows.reserveCapacity(setDrafts.count)
        indexBySetID.reserveCapacity(setDrafts.count)
        workingSetNumberBySetID.reserveCapacity(setDrafts.count)
        dropStageLocationByID.reserveCapacity(
            setDrafts.reduce(0) { $0 + $1.dropStages.count }
        )

        var workingSetNumber = 0
        var completedSetCount = 0
        for (index, draft) in setDrafts.enumerated() {
            if !draft.isWarmup {
                workingSetNumber += 1
            }
            if draft.isCycleCompleted {
                completedSetCount += 1
            }
            indexBySetID[draft.id] = index
            workingSetNumberBySetID[draft.id] = workingSetNumber
            for (stageIndex, stage) in draft.dropStages.enumerated() {
                dropStageLocationByID[stage.id] = WorkoutDropStageLocation(
                    setIndex: index,
                    stageIndex: stageIndex
                )
            }
            rows.append(rowBuilder(draft, index, workingSetNumber))
        }

        return WorkoutSessionExerciseGridProjection(
            rows: rows,
            indexBySetID: indexBySetID,
            workingSetNumberBySetID: workingSetNumberBySetID,
            dropStageLocationByID: dropStageLocationByID,
            completedSetCount: completedSetCount
        )
    }

    static func build(
        setDrafts: [WorkoutSessionSetDraft]
    ) -> WorkoutSessionExerciseGridProjection {
        build(setDrafts: setDrafts) { draft, index, workingSetNumber in
            WorkoutSessionExerciseSetRowDisplaySnapshot(
                id: draft.id,
                index: index,
                set: draft,
                badgeTitle: draft.isWarmup ? "W" : "\(workingSetNumber)",
                title: draft.isWarmup ? "Warmup Set" : "Working Set \(workingSetNumber)",
                previousSummary: "",
                metadataLine: nil,
                inlineHintPresentation: nil,
                completionButtonTitle: ""
            )
        }
    }
}
