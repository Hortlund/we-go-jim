import Foundation

nonisolated enum TrainingGuidanceTone: Equatable, Sendable {
    case accent
    case success
    case caution
}

nonisolated enum TrainingExerciseClassification: Equatable, Sendable {
    case lowerBodyCompound
    case upperBodyCompound
    case isolation
    case core
    case conditioning
    case unknown
}

nonisolated enum ProgressiveOverloadDirection: Equatable, Sendable {
    case increaseLoad
    case decreaseLoad
    case stayCourse
}

nonisolated struct TemplateExerciseRecommendation: Equatable, Sendable {
    let classification: TrainingExerciseClassification
    let tone: TrainingGuidanceTone
    let title: String
    let summary: String
    let suggestedWarmupSets: ClosedRange<Int>
    let suggestedWorkingSets: ClosedRange<Int>
    let suggestedRepRange: ClosedRange<Int>
    let suggestedRestSeconds: ClosedRange<Int>
}

nonisolated struct ActiveWorkoutGuidanceBadgePresentation: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let systemImage: String
}

nonisolated struct ProgressiveOverloadCue: Equatable, Sendable {
    let classification: TrainingExerciseClassification
    let tone: TrainingGuidanceTone
    let title: String
    let summary: String
    let direction: ProgressiveOverloadDirection
    let suggestedNextLoad: Double?
    let suggestedLoadUnit: TemplateLoadUnit?
    let suggestedRepRange: ClosedRange<Int>?
}

nonisolated struct ActiveWorkoutExerciseGuidancePresentation: Equatable, Sendable {
    let title: String
    let summary: String
    let tone: TrainingGuidanceTone
    let badge: ActiveWorkoutGuidanceBadgePresentation

    static func make(
        cue: ProgressiveOverloadCue?
    ) -> ActiveWorkoutExerciseGuidancePresentation? {
        guard let cue else { return nil }

        return ActiveWorkoutExerciseGuidancePresentation(
            title: cue.title,
            summary: cue.summary,
            tone: cue.tone,
            badge: badge(for: cue)
        )
    }

    private static func badge(for cue: ProgressiveOverloadCue) -> ActiveWorkoutGuidanceBadgePresentation {
        let suggestedLoadText = trainingGuidanceLoadText(
            load: cue.suggestedNextLoad,
            unit: cue.suggestedLoadUnit
        )

        switch cue.direction {
        case .increaseLoad:
            return ActiveWorkoutGuidanceBadgePresentation(
                title: "Increase Load",
                subtitle: suggestedLoadText.map { "Next: \($0)" } ?? "Next workout",
                systemImage: "arrow.up.circle.fill"
            )
        case .decreaseLoad:
            return ActiveWorkoutGuidanceBadgePresentation(
                title: "Reduce Load",
                subtitle: suggestedLoadText.map { "Next: \($0)" } ?? "Next workout",
                systemImage: "arrow.down.circle.fill"
            )
        case .stayCourse:
            return ActiveWorkoutGuidanceBadgePresentation(
                title: "Keep Load",
                subtitle: suggestedLoadText.map { "Next: \($0)" }
                    ?? cue.suggestedRepRange.map { "\($0.lowerBound)-\($0.upperBound) clean" },
                systemImage: "equal.circle.fill"
            )
        }
    }
}

nonisolated private func trainingGuidanceLoadText(load: Double?, unit: TemplateLoadUnit?) -> String? {
    guard
        let load,
        let unit
    else {
        return nil
    }

    return "\(WGJFormatters.decimalString(load)) \(unit.shortLabel)"
}

nonisolated struct TrainingGuidanceCatalogSnapshot: Equatable, Sendable {
    let exerciseName: String
    let categoryName: String
    let equipmentSummary: String
    let primaryMuscleNames: String

    init(exerciseName: String, categoryName: String, equipmentSummary: String, primaryMuscleNames: String) {
        self.exerciseName = exerciseName
        self.categoryName = categoryName
        self.equipmentSummary = equipmentSummary
        self.primaryMuscleNames = primaryMuscleNames
    }

    nonisolated init(exercise: ExerciseCatalogItem) {
        self.init(
            exerciseName: exercise.displayName,
            categoryName: exercise.categoryName,
            equipmentSummary: exercise.equipmentSummary,
            primaryMuscleNames: exercise.primaryMuscleNames
        )
    }
}

struct ActiveWorkoutExerciseCardStateController: Equatable {
    private(set) var isExpandedByExerciseID: [UUID: Bool] = [:]
    private(set) var completedInCurrentCycle: Set<UUID> = []

    mutating func sync(exerciseIDs: [UUID], completedExerciseIDs: Set<UUID>, firstIncompleteExerciseID: UUID?) {
        let validIDs = Set(exerciseIDs)
        isExpandedByExerciseID = isExpandedByExerciseID.filter { validIDs.contains($0.key) }
        completedInCurrentCycle = completedInCurrentCycle.intersection(validIDs)

        for exerciseID in exerciseIDs {
            guard isExpandedByExerciseID[exerciseID] == nil else { continue }

            let isCompleted = completedExerciseIDs.contains(exerciseID)
            isExpandedByExerciseID[exerciseID] = !isCompleted && exerciseID == firstIncompleteExerciseID
            if isCompleted {
                completedInCurrentCycle.insert(exerciseID)
            }
        }
    }

    mutating func setExpanded(_ isExpanded: Bool, for exerciseID: UUID) {
        guard isExpandedByExerciseID[exerciseID] != isExpanded else { return }
        isExpandedByExerciseID[exerciseID] = isExpanded
    }

    mutating func updateCompletion(for exerciseID: UUID, isCompleted: Bool) {
        _ = updateCompletion(
            for: exerciseID,
            isCompleted: isCompleted,
            orderedExerciseIDs: [],
            completedExerciseIDs: []
        )
    }

    mutating func updateCompletion(
        for exerciseID: UUID,
        isCompleted: Bool,
        orderedExerciseIDs: [UUID],
        completedExerciseIDs: Set<UUID>
    ) -> UUID? {
        if isCompleted {
            guard !completedInCurrentCycle.contains(exerciseID) else { return nil }
            completedInCurrentCycle.insert(exerciseID)
            isExpandedByExerciseID[exerciseID] = false
            guard
                let nextExerciseID = nextIncompleteExerciseID(
                    after: exerciseID,
                    orderedExerciseIDs: orderedExerciseIDs,
                    completedExerciseIDs: completedExerciseIDs
                )
            else {
                return nil
            }
            isExpandedByExerciseID[nextExerciseID] = true
            return nextExerciseID
        } else {
            completedInCurrentCycle.remove(exerciseID)
            return nil
        }
    }

    func didCompleteCurrentCycle(for exerciseID: UUID) -> Bool {
        completedInCurrentCycle.contains(exerciseID)
    }

    func isExpanded(for exerciseID: UUID, default defaultValue: Bool = false) -> Bool {
        isExpandedByExerciseID[exerciseID] ?? defaultValue
    }

    private func nextIncompleteExerciseID(
        after exerciseID: UUID,
        orderedExerciseIDs: [UUID],
        completedExerciseIDs: Set<UUID>
    ) -> UUID? {
        guard let currentIndex = orderedExerciseIDs.firstIndex(of: exerciseID) else { return nil }

        for nextIndex in orderedExerciseIDs.index(after: currentIndex)..<orderedExerciseIDs.endIndex {
            let nextExerciseID = orderedExerciseIDs[nextIndex]
            if !completedExerciseIDs.contains(nextExerciseID) {
                return nextExerciseID
            }
        }

        return nil
    }
}

nonisolated struct TrainingGuidanceService {
    private let lowerCompoundKeywords = [
        "hack squat",
        "hip thrust",
        "leg press",
        "split squat",
        "step-up",
        "deadlift",
        "lunge",
        "squat",
        "rdl",
    ]

    private let upperCompoundKeywords = [
        "pull-up",
        "chin-up",
        "pulldown",
        "push-up",
        "bench",
        "press",
        "row",
        "dip",
    ]

    private let isolationKeywords = [
        "pressdown",
        "kickback",
        "extension",
        "raise",
        "curl",
        "fly",
    ]

    func templateRecommendation(for exercise: ExerciseCatalogItem?) -> TemplateExerciseRecommendation {
        guard let exercise else {
            return templateRecommendation(
                for: TrainingGuidanceCatalogSnapshot(
                    exerciseName: "",
                    categoryName: "",
                    equipmentSummary: "",
                    primaryMuscleNames: ""
                )
            )
        }
        return templateRecommendation(for: TrainingGuidanceCatalogSnapshot(exercise: exercise))
    }

    func templateRecommendation(for exercise: TrainingGuidanceCatalogSnapshot) -> TemplateExerciseRecommendation {
        switch classification(for: exercise) {
        case .lowerBodyCompound:
            return TemplateExerciseRecommendation(
                classification: .lowerBodyCompound,
                tone: .accent,
                title: "Progressive overload sweet spot",
                summary: "Try 2 warmups, 3-4 working sets, 5-8 reps, and 120-180 sec rest. Adjust freely.",
                suggestedWarmupSets: 2...2,
                suggestedWorkingSets: 3...4,
                suggestedRepRange: 5...8,
                suggestedRestSeconds: 120...180
            )
        case .upperBodyCompound:
            return TemplateExerciseRecommendation(
                classification: .upperBodyCompound,
                tone: .accent,
                title: "Solid default structure",
                summary: "Try 1-2 warmups, 3-4 working sets, 6-10 reps, and 90-150 sec rest. Adjust freely.",
                suggestedWarmupSets: 1...2,
                suggestedWorkingSets: 3...4,
                suggestedRepRange: 6...10,
                suggestedRestSeconds: 90...150
            )
        case .isolation:
            return TemplateExerciseRecommendation(
                classification: .isolation,
                tone: .accent,
                title: "Keep isolation work simple",
                summary: "Try 0-1 warmups, 2-4 working sets, 10-15 reps, and 45-90 sec rest. Adjust freely.",
                suggestedWarmupSets: 0...1,
                suggestedWorkingSets: 2...4,
                suggestedRepRange: 10...15,
                suggestedRestSeconds: 45...90
            )
        case .core:
            return TemplateExerciseRecommendation(
                classification: .core,
                tone: .accent,
                title: "Core work usually needs less setup",
                summary: "Try 0-1 warmups, 2-4 working sets, 8-15 reps, and 45-75 sec rest. Adjust freely.",
                suggestedWarmupSets: 0...1,
                suggestedWorkingSets: 2...4,
                suggestedRepRange: 8...15,
                suggestedRestSeconds: 45...75
            )
        case .conditioning:
            return TemplateExerciseRecommendation(
                classification: .conditioning,
                tone: .accent,
                title: "Keep conditioning repeatable",
                summary: "Try 1-2 ramp-up rounds, 3-5 hard rounds, 8-20 reps or 20-60 sec efforts, and 45-90 sec recovery.",
                suggestedWarmupSets: 1...2,
                suggestedWorkingSets: 3...5,
                suggestedRepRange: 8...20,
                suggestedRestSeconds: 45...90
            )
        case .unknown:
            return TemplateExerciseRecommendation(
                classification: .unknown,
                tone: .accent,
                title: "Solid default structure",
                summary: "Try 1-2 warmups, 3 working sets, 8-12 reps, and 60-120 sec rest. Adjust once the lift settles in.",
                suggestedWarmupSets: 1...2,
                suggestedWorkingSets: 3...3,
                suggestedRepRange: 8...12,
                suggestedRestSeconds: 60...120
            )
        }
    }

    func progressiveOverloadCue(
        for exercise: ExerciseCatalogItem?,
        targetRepMin: Int?,
        targetRepMax: Int?,
        setDrafts: [WorkoutSessionSetDraft]
    ) -> ProgressiveOverloadCue? {
        guard let exercise else { return nil }
        return progressiveOverloadCue(
            for: TrainingGuidanceCatalogSnapshot(exercise: exercise),
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            setDrafts: setDrafts
        )
    }

    func progressiveOverloadCue(
        for exercise: TrainingGuidanceCatalogSnapshot,
        targetRepMin: Int?,
        targetRepMax: Int?,
        setDrafts: [WorkoutSessionSetDraft]
    ) -> ProgressiveOverloadCue? {
        guard let targetRepMin, let targetRepMax, targetRepMin <= targetRepMax else {
            return nil
        }

        let qualifyingSets = setDrafts.filter {
            $0.isCompleted
                && !$0.isWarmup
                && $0.actualLoadUnit != .bodyweight
                && $0.actualWeight != nil
                && $0.actualReps != nil
        }

        guard !qualifyingSets.isEmpty else {
            return nil
        }

        let classification = classification(for: exercise)
        let actualReps = qualifyingSets.compactMap(\.actualReps)
        let repRange = targetRepMin...targetRepMax
        let referenceSet = qualifyingSets.last

        if actualReps.allSatisfy({ $0 > targetRepMax }) {
            let summary = increaseLoadSummary(referenceSet: referenceSet, repRange: repRange)

            return ProgressiveOverloadCue(
                classification: classification,
                tone: .success,
                title: "Increase the load next time",
                summary: summary,
                direction: .increaseLoad,
                suggestedNextLoad: adjustedLoad(for: referenceSet, direction: .increaseLoad),
                suggestedLoadUnit: referenceSet?.actualLoadUnit,
                suggestedRepRange: repRange
            )
        }

        if actualReps.allSatisfy({ $0 < targetRepMin }) {
            let summary = decreaseLoadSummary(referenceSet: referenceSet, repRange: repRange)

            return ProgressiveOverloadCue(
                classification: classification,
                tone: .caution,
                title: "Reduce the load next time",
                summary: summary,
                direction: .decreaseLoad,
                suggestedNextLoad: adjustedLoad(for: referenceSet, direction: .decreaseLoad),
                suggestedLoadUnit: referenceSet?.actualLoadUnit,
                suggestedRepRange: repRange
            )
        }

        return ProgressiveOverloadCue(
            classification: classification,
            tone: .accent,
            title: "Keep the load the same",
            summary: stayCourseSummary(referenceSet: referenceSet, repRange: repRange),
            direction: .stayCourse,
            suggestedNextLoad: referenceSet?.actualWeight,
            suggestedLoadUnit: referenceSet?.actualLoadUnit,
            suggestedRepRange: repRange
        )
    }

    func activeWorkoutGuidance(
        for exercise: ExerciseCatalogItem?,
        targetRepMin: Int?,
        targetRepMax: Int?,
        setDrafts: [WorkoutSessionSetDraft]
    ) -> ActiveWorkoutExerciseGuidancePresentation {
        let snapshot: TrainingGuidanceCatalogSnapshot
        if let exercise {
            snapshot = TrainingGuidanceCatalogSnapshot(exercise: exercise)
        } else {
            snapshot = TrainingGuidanceCatalogSnapshot(
                exerciseName: "",
                categoryName: "",
                equipmentSummary: "",
                primaryMuscleNames: ""
            )
        }

        return activeWorkoutGuidance(
            for: snapshot,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            setDrafts: setDrafts
        )
    }

    func activeWorkoutGuidance(
        for exercise: TrainingGuidanceCatalogSnapshot,
        targetRepMin: Int?,
        targetRepMax: Int?,
        setDrafts: [WorkoutSessionSetDraft]
    ) -> ActiveWorkoutExerciseGuidancePresentation {
        let completedWorkingSets = setDrafts.filter { $0.isCompleted && !$0.isWarmup }
        let hasWorkingSets = setDrafts.contains { !$0.isWarmup }
        let isExerciseComplete = hasWorkingSets && setDrafts.allSatisfy(\.isCompleted)

        if isExerciseComplete,
           let cue = progressiveOverloadCue(
                for: exercise,
                targetRepMin: targetRepMin,
                targetRepMax: targetRepMax,
                setDrafts: setDrafts
           ),
           let presentation = ActiveWorkoutExerciseGuidancePresentation.make(cue: cue)
        {
            return presentation
        }

        let recommendation = templateRecommendation(for: exercise)
        let classification = classification(for: exercise)
        let repRange = resolvedRepRange(
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            recommendation: recommendation
        )
        let completedWarmupCount = setDrafts.filter { $0.isCompleted && $0.isWarmup }.count

        guard let lastCompletedWorkingSet = completedWorkingSets.last else {
            return initialActiveWorkoutGuidance(
                classification: classification,
                recommendation: recommendation,
                repRange: repRange,
                completedWarmupCount: completedWarmupCount
            )
        }

        guard let lastReps = lastCompletedWorkingSet.actualReps else {
            return inProgressGenericGuidance(
                classification: classification,
                repRange: repRange
            )
        }

        if lastCompletedWorkingSet.actualLoadUnit == .bodyweight || lastCompletedWorkingSet.actualWeight == nil {
            return bodyweightGuidance(
                repRange: repRange,
                lastReps: lastReps
            )
        }

        if lastReps < repRange.lowerBound {
            return guidancePresentation(
                title: "Get the reps back",
                summary: "That set dropped to \(lastReps) reps. Take a little more rest or reduce the load so the next set gets back into \(repRangeText(repRange)) clean reps.",
                tone: .caution,
                badgeTitle: "Reps Up",
                badgeSubtitle: "Rest or reduce load",
                badgeSystemImage: "arrow.up.circle.fill"
            )
        }

        if lastReps > repRange.upperBound {
            return guidancePresentation(
                title: "Keep the reps in range",
                summary: "That set hit \(lastReps) reps. Keep the next set inside \(repRangeText(repRange)) clean reps. If the rest of the work sets still clear the top, increase the load next session.",
                tone: .success,
                badgeTitle: "Reps Down",
                badgeSubtitle: "Keep \(repRangeText(repRange))",
                badgeSystemImage: "arrow.down.circle.fill"
            )
        }

        if let loadText = loggedLoadText(for: lastCompletedWorkingSet) {
            if lastReps < repRange.upperBound {
                return guidancePresentation(
                    title: "Add a rep before increasing load",
                    summary: "\(loadText) is still working well. Try to beat \(lastReps) with the same setup and keep it inside \(repRangeText(repRange)).",
                    tone: .accent,
                    badgeTitle: "Reps Up",
                    badgeSubtitle: "Same \(loadText)",
                    badgeSystemImage: "arrow.up.circle.fill"
                )
            }

            return guidancePresentation(
                title: "Keep that load",
                summary: "\(loadText) is right on target. Match it again clean before you increase it.",
                tone: .accent,
                badgeTitle: "Keep Load",
                badgeSubtitle: loadText,
                badgeSystemImage: "equal.circle.fill"
            )
        }

        return inProgressGenericGuidance(
            classification: classification,
            repRange: repRange
        )
    }

    func classification(for exercise: ExerciseCatalogItem?) -> TrainingExerciseClassification {
        guard let exercise else { return .unknown }
        return classification(for: TrainingGuidanceCatalogSnapshot(exercise: exercise))
    }

    func classification(for exercise: TrainingGuidanceCatalogSnapshot) -> TrainingExerciseClassification {
        let name = normalizedTerms(from: exercise.exerciseName)
        let category = normalizedTerms(from: exercise.categoryName)
        let equipment = normalizedTerms(from: exercise.equipmentSummary)
        let muscles = normalizedTerms(from: exercise.primaryMuscleNames)
        let searchSpace = [name, category, equipment, muscles].joined(separator: " ")

        if category.contains("conditioning") {
            return .conditioning
        }

        if category.contains("core") || muscles.contains("abs") || muscles.contains("core") {
            return .core
        }

        if matchesAny(isolationKeywords, in: searchSpace) {
            return .isolation
        }

        if matchesAny(lowerCompoundKeywords, in: searchSpace) {
            return .lowerBodyCompound
        }

        if matchesAny(upperCompoundKeywords, in: searchSpace) {
            return .upperBodyCompound
        }

        return .unknown
    }

    private func normalizedTerms(from value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: ",", with: " ")
    }

    private func matchesAny(_ keywords: [String], in haystack: String) -> Bool {
        keywords.contains { haystack.contains($0) }
    }

    private func adjustedLoad(
        for referenceSet: WorkoutSessionSetDraft?,
        direction: ProgressiveOverloadDirection
    ) -> Double? {
        guard
            let referenceSet,
            let weight = referenceSet.actualWeight,
            let step = referenceSet.actualLoadUnit.progressiveLoadStep
        else {
            return nil
        }

        switch direction {
        case .increaseLoad:
            return weight + step
        case .decreaseLoad:
            return max(0, weight - step)
        case .stayCourse:
            return weight
        }
    }

    private func increaseLoadSummary(
        referenceSet: WorkoutSessionSetDraft?,
        repRange: ClosedRange<Int>
    ) -> String {
        guard let loadText = adjustedLoadText(for: referenceSet, direction: .increaseLoad) else {
            return "You cleared the whole range. Add a little load next time and bring it back to \(repRangeText(repRange)) clean reps."
        }

        return "You cleared the whole range. Move to \(loadText) next time and work back into \(repRangeText(repRange)) clean reps."
    }

    private func decreaseLoadSummary(
        referenceSet: WorkoutSessionSetDraft?,
        repRange: ClosedRange<Int>
    ) -> String {
        guard let loadText = adjustedLoadText(for: referenceSet, direction: .decreaseLoad) else {
            return "You missed the floor. Pull the load back a touch next time and rebuild \(repRangeText(repRange)) clean reps."
        }

        return "You missed the floor. Drop to \(loadText) next time and rebuild \(repRangeText(repRange)) clean reps."
    }

    private func stayCourseSummary(
        referenceSet: WorkoutSessionSetDraft?,
        repRange: ClosedRange<Int>
    ) -> String {
        guard
            let referenceSet,
            let weight = referenceSet.actualWeight
        else {
            return "Stay here until every work set lands inside \(repRangeText(repRange)) with the same clean standard."
        }

        let loadText = trainingGuidanceLoadText(
            load: weight,
            unit: referenceSet.actualLoadUnit
        ) ?? "\(WGJFormatters.decimalString(weight)) \(referenceSet.actualLoadUnit.shortLabel)"
        return "\(loadText) is in the right spot for now. Keep every work set inside \(repRangeText(repRange)) before you increase it."
    }

    private func adjustedLoadText(
        for referenceSet: WorkoutSessionSetDraft?,
        direction: ProgressiveOverloadDirection
    ) -> String? {
        guard
            let referenceSet,
            let adjustedLoad = adjustedLoad(for: referenceSet, direction: direction)
        else {
            return nil
        }

        return trainingGuidanceLoadText(
            load: adjustedLoad,
            unit: referenceSet.actualLoadUnit
        )
    }

    private func repRangeText(_ repRange: ClosedRange<Int>) -> String {
        "\(repRange.lowerBound)-\(repRange.upperBound)"
    }

    private func resolvedRepRange(
        targetRepMin: Int?,
        targetRepMax: Int?,
        recommendation: TemplateExerciseRecommendation
    ) -> ClosedRange<Int> {
        guard
            let targetRepMin,
            let targetRepMax,
            targetRepMin <= targetRepMax
        else {
            return recommendation.suggestedRepRange
        }

        return targetRepMin...targetRepMax
    }

    private func initialActiveWorkoutGuidance(
        classification: TrainingExerciseClassification,
        recommendation: TemplateExerciseRecommendation,
        repRange: ClosedRange<Int>,
        completedWarmupCount: Int
    ) -> ActiveWorkoutExerciseGuidancePresentation {
        let warmupInstruction = warmupInstruction(
            completedWarmupCount: completedWarmupCount,
            suggestedWarmupSets: recommendation.suggestedWarmupSets
        )

        switch classification {
        case .lowerBodyCompound:
            return guidancePresentation(
                title: "Warm up and brace",
                summary: "\(warmupInstruction) Big lower-body lifts win when your torso stays locked and the first work set lands in \(repRangeText(repRange)) reps.",
                tone: .accent,
                badgeTitle: "Warm Up",
                badgeSubtitle: warmupBadgeSubtitle(
                    completedWarmupCount: completedWarmupCount,
                    suggestedWarmupSets: recommendation.suggestedWarmupSets
                ),
                badgeSystemImage: "flame.circle.fill"
            )
        case .upperBodyCompound:
            return guidancePresentation(
                title: "Warm up and set your shoulders",
                summary: "\(warmupInstruction) Pack the shoulders, repeat the same bar path, and aim for \(repRangeText(repRange)) reps.",
                tone: .accent,
                badgeTitle: "Warm Up",
                badgeSubtitle: warmupBadgeSubtitle(
                    completedWarmupCount: completedWarmupCount,
                    suggestedWarmupSets: recommendation.suggestedWarmupSets
                ),
                badgeSystemImage: "flame.circle.fill"
            )
        case .isolation:
            return guidancePresentation(
                title: "Warm up and stay controlled",
                summary: "\(warmupInstruction) Control the stretch, keep tension on the target muscle, and make \(repRangeText(repRange)) reps feel deliberate.",
                tone: .accent,
                badgeTitle: "Warm Up",
                badgeSubtitle: warmupBadgeSubtitle(
                    completedWarmupCount: completedWarmupCount,
                    suggestedWarmupSets: recommendation.suggestedWarmupSets
                ),
                badgeSystemImage: "flame.circle.fill"
            )
        case .core:
            return guidancePresentation(
                title: "Warm up and brace first",
                summary: "\(warmupInstruction) Keep ribs down, move slow, and make every rep in \(repRangeText(repRange)) look clean.",
                tone: .accent,
                badgeTitle: "Warm Up",
                badgeSubtitle: warmupBadgeSubtitle(
                    completedWarmupCount: completedWarmupCount,
                    suggestedWarmupSets: recommendation.suggestedWarmupSets
                ),
                badgeSystemImage: "flame.circle.fill"
            )
        case .conditioning:
            return guidancePresentation(
                title: "Warm up and pace the effort",
                summary: "\(warmupInstruction) Start smooth so the later rounds can still hit \(repRangeText(repRange)) reps with control.",
                tone: .accent,
                badgeTitle: "Warm Up",
                badgeSubtitle: warmupBadgeSubtitle(
                    completedWarmupCount: completedWarmupCount,
                    suggestedWarmupSets: recommendation.suggestedWarmupSets
                ),
                badgeSystemImage: "flame.circle.fill"
            )
        case .unknown:
            return guidancePresentation(
                title: "Warm up and find a consistent groove",
                summary: "\(warmupInstruction) Use the early sets to settle the pattern and aim for \(repRangeText(repRange)) clean reps.",
                tone: .accent,
                badgeTitle: "Warm Up",
                badgeSubtitle: warmupBadgeSubtitle(
                    completedWarmupCount: completedWarmupCount,
                    suggestedWarmupSets: recommendation.suggestedWarmupSets
                ),
                badgeSystemImage: "flame.circle.fill"
            )
        }
    }

    private func inProgressGenericGuidance(
        classification: TrainingExerciseClassification,
        repRange: ClosedRange<Int>
    ) -> ActiveWorkoutExerciseGuidancePresentation {
        let summary: String

        switch classification {
        case .lowerBodyCompound:
            summary = "Your work sets are in progress. Keep the brace solid and make the next one land in \(repRangeText(repRange)) clean reps."
        case .upperBodyCompound:
            summary = "Your work sets are in progress. Set the shoulders, repeat the same path, and keep the next one in \(repRangeText(repRange)) clean reps."
        case .isolation:
            summary = "Your work sets are in progress. Stay on the target muscle, avoid momentum, and keep the next one in \(repRangeText(repRange)) clean reps."
        case .core:
            summary = "Your work sets are in progress. Keep ribs down, brace first, and make the next one land in \(repRangeText(repRange)) clean reps."
        case .conditioning:
            summary = "Your work sets are in progress. Keep the early pace under control so the next effort still hits \(repRangeText(repRange)) reps."
        case .unknown:
            summary = "Your work sets are in progress. Repeat the same setup and keep the next one around \(repRangeText(repRange)) clean reps."
        }

        return guidancePresentation(
            title: "Keep the next set consistent",
            summary: summary,
            tone: .accent,
            badgeTitle: "Stay Consistent",
            badgeSubtitle: "\(repRangeText(repRange)) clean",
            badgeSystemImage: "scope"
        )
    }

    private func bodyweightGuidance(
        repRange: ClosedRange<Int>,
        lastReps: Int
    ) -> ActiveWorkoutExerciseGuidancePresentation {
        if lastReps < repRange.lowerBound {
            return guidancePresentation(
                title: "Get the reps back",
                summary: "That set dropped to \(lastReps) reps. Take a little more rest or use assistance so the next one gets back into \(repRangeText(repRange)) clean reps.",
                tone: .caution,
                badgeTitle: "Reps Up",
                badgeSubtitle: "Rest or assist",
                badgeSystemImage: "arrow.up.circle.fill"
            )
        }

        if lastReps > repRange.upperBound {
            return guidancePresentation(
                title: "Make the variation harder",
                summary: "That set hit \(lastReps) reps. Slow the lowering, add a pause, or progress the variation so the next one comes back into \(repRangeText(repRange)) clean reps.",
                tone: .accent,
                badgeTitle: "Reps Down",
                badgeSubtitle: "Harder variation",
                badgeSystemImage: "arrow.down.circle.fill"
            )
        }

        if lastReps < repRange.upperBound {
            return guidancePresentation(
                title: "Add reps before you progress the variation",
                summary: "That set was on target. Stay with the same variation and try to beat \(lastReps) while keeping it inside \(repRangeText(repRange)).",
                tone: .accent,
                badgeTitle: "Reps Up",
                badgeSubtitle: "Same variation",
                badgeSystemImage: "arrow.up.circle.fill"
            )
        }

        return guidancePresentation(
            title: "Repeat the top end",
            summary: "That set hit the top clean. Match it again before you make the variation harder.",
            tone: .accent,
            badgeTitle: "Match Reps",
            badgeSubtitle: "Match the set",
            badgeSystemImage: "equal.circle.fill"
        )
    }

    private func warmupInstruction(
        completedWarmupCount: Int,
        suggestedWarmupSets: ClosedRange<Int>
    ) -> String {
        if completedWarmupCount == 0 {
            if suggestedWarmupSets.upperBound == 0 {
                return "You can go straight into the work sets if the groove already feels ready."
            }

            if suggestedWarmupSets.lowerBound == suggestedWarmupSets.upperBound {
                let count = suggestedWarmupSets.lowerBound
                return "Take \(count) ramp-up \(count == 1 ? "set" : "sets") before the work sets."
            }

            return "Take \(suggestedWarmupSets.lowerBound)-\(suggestedWarmupSets.upperBound) ramp-up sets before the work sets."
        }

        if completedWarmupCount < suggestedWarmupSets.lowerBound {
            return "One more ramp-up set is worth it if the pattern still feels cold."
        }

        return "Warmups look covered, so make the first work set count."
    }

    private func warmupBadgeSubtitle(
        completedWarmupCount: Int,
        suggestedWarmupSets: ClosedRange<Int>
    ) -> String {
        if completedWarmupCount == 0 {
            if suggestedWarmupSets.upperBound == 0 {
                return "Optional ramp"
            }

            if suggestedWarmupSets.lowerBound == suggestedWarmupSets.upperBound {
                let count = suggestedWarmupSets.lowerBound
                return count == 1 ? "1 ramp set" : "\(count) ramp sets"
            }

            return "\(suggestedWarmupSets.lowerBound)-\(suggestedWarmupSets.upperBound) ramp sets"
        }

        if completedWarmupCount < suggestedWarmupSets.lowerBound {
            return "1 more ramp set"
        }

        return "First work set"
    }

    private func guidancePresentation(
        title: String,
        summary: String,
        tone: TrainingGuidanceTone,
        badgeTitle: String,
        badgeSubtitle: String?,
        badgeSystemImage: String
    ) -> ActiveWorkoutExerciseGuidancePresentation {
        ActiveWorkoutExerciseGuidancePresentation(
            title: title,
            summary: summary,
            tone: tone,
            badge: ActiveWorkoutGuidanceBadgePresentation(
                title: badgeTitle,
                subtitle: badgeSubtitle,
                systemImage: badgeSystemImage
            )
        )
    }

    private func loggedLoadText(for set: WorkoutSessionSetDraft?) -> String? {
        guard
            let set,
            let actualWeight = set.actualWeight,
            set.actualLoadUnit != .bodyweight
        else {
            return nil
        }

        return trainingGuidanceLoadText(
            load: actualWeight,
            unit: set.actualLoadUnit
        )
    }
}
