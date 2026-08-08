import Foundation

nonisolated struct ActiveWorkoutSupersetContext: Equatable, Sendable {
    let position: SupersetExercisePosition
    let roundRestSeconds: Int
    let pairedExerciseID: UUID
}

nonisolated struct ActiveWorkoutRenderProjection: Sendable {
    var session: ActiveWorkoutRuntimeSession?
    var sessionExercises: [ActiveWorkoutRuntimeExercise]
    var orderedCardioBlocks: [ActiveWorkoutRuntimeCardioBlock]
    var exerciseDisplayGroups: [WorkoutExerciseDisplayGroup<ActiveWorkoutRuntimeExercise>]
    var cardioByRole: [WorkoutCardioRole: [ActiveWorkoutRuntimeCardioBlock]]
    var areAllMainExercisesCompleted: Bool
    var hasWorkoutContent: Bool
    var supersetContextByExerciseID: [UUID: ActiveWorkoutSupersetContext]
    var exerciseHydrationStamp: ActiveWorkoutExerciseInteractionStamp

    static let empty = ActiveWorkoutRenderProjection(
        session: nil,
        sessionExercises: [],
        orderedCardioBlocks: [],
        exerciseDisplayGroups: [],
        cardioByRole: [:],
        areAllMainExercisesCompleted: true,
        hasWorkoutContent: false,
        supersetContextByExerciseID: [:],
        exerciseHydrationStamp: ActiveWorkoutExerciseInteractionStamp(entries: [])
    )
}

nonisolated enum ActiveWorkoutRenderProjectionBuilder {
    static func build(
        session: ActiveWorkoutRuntimeSession?,
        setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]],
        pendingCardioCompletionsByID: [UUID: Bool]
    ) -> ActiveWorkoutRenderProjection {
        guard let session else {
            return .empty
        }

        let exercises = session.exercises.sorted { $0.sortOrder < $1.sortOrder }
        let cardioBlocks = session.cardioBlocks
            .map { cardioBlock in
                var updated = cardioBlock
                if let completion = pendingCardioCompletionsByID[cardioBlock.id] {
                    updated.isCompleted = completion
                }
                return updated
            }
            .sorted(by: ActiveWorkoutRuntimeCardioBlock.areInIncreasingOrder)
        let cardioByRole = Dictionary(grouping: cardioBlocks, by: \.role)
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
            cardioByRole: cardioByRole,
            areAllMainExercisesCompleted: areAllMainExercisesCompleted,
            hasWorkoutContent: !exercises.isEmpty || !cardioBlocks.isEmpty,
            supersetContextByExerciseID: supersetContextByExerciseID(from: displayGroups),
            exerciseHydrationStamp: exerciseHydrationStamp(
                from: exercises,
                setDraftsByExerciseID: setDraftsByExerciseID
            )
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

    private static func exerciseHydrationStamp(
        from exercises: [ActiveWorkoutRuntimeExercise],
        setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) -> ActiveWorkoutExerciseInteractionStamp {
        ActiveWorkoutExerciseInteractionStamp(
            entries: exercises.map { exercise in
                let setDrafts = setDraftsByExerciseID[exercise.id] ?? exercise.setDrafts
                return ActiveWorkoutExerciseInteractionStamp.Entry(
                    id: exercise.id,
                    catalogExerciseUUID: exercise.catalogExerciseUUID,
                    restSeconds: exercise.restSeconds,
                    targetRepMin: exercise.targetRepMin,
                    targetRepMax: exercise.targetRepMax,
                    setDraftIDs: setDrafts.map(\.id),
                    supersetGroupID: exercise.supersetGroupID,
                    supersetPositionRaw: exercise.supersetPositionRaw
                )
            }
        )
    }
}

nonisolated enum ActiveWorkoutRuntimeCardioPlanReducer {
    static func appending(
        _ activity: ActiveWorkoutRuntimeCardioBlock,
        to activities: [ActiveWorkoutRuntimeCardioBlock]
    ) -> [ActiveWorkoutRuntimeCardioBlock] {
        let existing = normalized(activities.filter { $0.id != activity.id })
        var appended = activity
        appended.sortOrder = existing.lazy.filter { $0.role == appended.role }.count
        return normalized(existing + [appended])
    }

    static func updating(
        _ activity: ActiveWorkoutRuntimeCardioBlock,
        in activities: [ActiveWorkoutRuntimeCardioBlock]
    ) -> [ActiveWorkoutRuntimeCardioBlock] {
        var ordered = normalized(activities)
        guard let previousIndex = ordered.firstIndex(where: { $0.id == activity.id }) else {
            return appending(activity, to: activities)
        }

        let previous = ordered[previousIndex]
        var updated = activity
        if previous.role == updated.role {
            updated.sortOrder = previous.sortOrder
            ordered[previousIndex] = updated
            return normalized(ordered)
        }

        let remaining = ordered.filter { $0.id != activity.id }
        updated.sortOrder = remaining.lazy.filter { $0.role == updated.role }.count
        return normalized(remaining + [updated])
    }

    static func removing(
        activityID: UUID,
        from activities: [ActiveWorkoutRuntimeCardioBlock]
    ) -> [ActiveWorkoutRuntimeCardioBlock] {
        normalized(activities.filter { $0.id != activityID })
    }

    static func normalized(
        _ activities: [ActiveWorkoutRuntimeCardioBlock]
    ) -> [ActiveWorkoutRuntimeCardioBlock] {
        WorkoutCardioRole.allCases.flatMap { role in
            activities.enumerated()
                .filter { $0.element.role == role }
                .sorted { lhs, rhs in
                    if lhs.element.sortOrder != rhs.element.sortOrder {
                        return lhs.element.sortOrder < rhs.element.sortOrder
                    }
                    if lhs.element.createdAt != rhs.element.createdAt {
                        return lhs.element.createdAt < rhs.element.createdAt
                    }
                    return lhs.offset < rhs.offset
                }
                .enumerated()
                .map { sortOrder, indexedActivity in
                    var activity = indexedActivity.element
                    activity.role = role
                    activity.phase = TemplateCardioDraftReducer.legacyPhase(for: role)
                    activity.sortOrder = sortOrder
                    return activity
                }
        }
    }
}

nonisolated enum ActiveWorkoutRenderProjectionRefreshPolicy {
    static func shouldRefreshImmediately(
        changeSummary: ActiveWorkoutSetDraftChangeSummary,
        isMetricInputFocused: Bool
    ) -> Bool {
        guard isMetricInputFocused else { return true }
        return changeSummary.hasStructuralChange || changeSummary.hasCompletionChange
    }
}
