import Foundation

enum TrainingGuidanceTone: Equatable {
    case accent
    case success
    case caution
}

enum TrainingExerciseClassification: Equatable {
    case lowerBodyCompound
    case upperBodyCompound
    case isolation
    case core
    case conditioning
    case unknown
}

enum ProgressiveOverloadDirection: Equatable {
    case increaseLoad
    case decreaseLoad
    case stayCourse
}

struct TemplateExerciseRecommendation: Equatable {
    let classification: TrainingExerciseClassification
    let tone: TrainingGuidanceTone
    let title: String
    let summary: String
    let suggestedWarmupSets: ClosedRange<Int>
    let suggestedWorkingSets: ClosedRange<Int>
    let suggestedRepRange: ClosedRange<Int>
    let suggestedRestSeconds: ClosedRange<Int>
}

struct ProgressiveOverloadCue: Equatable {
    let classification: TrainingExerciseClassification
    let tone: TrainingGuidanceTone
    let title: String
    let summary: String
    let direction: ProgressiveOverloadDirection
    let suggestedPercentRange: ClosedRange<Double>?
}

struct ActiveWorkoutExerciseGuidancePresentation: Equatable {
    let title: String
    let summary: String
    let tone: TrainingGuidanceTone

    static func make(
        recommendation: TemplateExerciseRecommendation,
        cue: ProgressiveOverloadCue?,
        isExerciseCompleted: Bool
    ) -> ActiveWorkoutExerciseGuidancePresentation {
        guard isExerciseCompleted, let cue else {
            return ActiveWorkoutExerciseGuidancePresentation(
                title: recommendation.title,
                summary: recommendation.summary,
                tone: recommendation.tone
            )
        }

        switch cue.direction {
        case .increaseLoad:
            let summary = cue.suggestedPercentRange.map { percentRange in
                "Add \(formattedPercentRange(percentRange)) next time, or use the smallest clean plate jump."
            } ?? cue.summary
            return ActiveWorkoutExerciseGuidancePresentation(
                title: cue.title,
                summary: summary,
                tone: cue.tone
            )
        case .decreaseLoad:
            let summary = cue.suggestedPercentRange.map { percentRange in
                "Reduce \(formattedPercentRange(percentRange)) next time, or take the smallest clean plate drop."
            } ?? cue.summary
            return ActiveWorkoutExerciseGuidancePresentation(
                title: cue.title,
                summary: summary,
                tone: cue.tone
            )
        case .stayCourse:
            return ActiveWorkoutExerciseGuidancePresentation(
                title: cue.title,
                summary: cue.summary,
                tone: cue.tone
            )
        }
    }

    private static func formattedPercentRange(_ range: ClosedRange<Double>) -> String {
        "\(WGJFormatters.oneDecimalString(range.lowerBound))-\(WGJFormatters.oneDecimalString(range.upperBound))%"
    }
}

struct TrainingGuidanceCatalogSnapshot: Equatable {
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

    init(exercise: ExerciseCatalogItem) {
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

struct TrainingGuidanceService {
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
        let percentRange = suggestedPercentRange(for: classification)
        let actualReps = qualifyingSets.compactMap(\.actualReps)

        if actualReps.allSatisfy({ $0 > targetRepMax }) {
            let summary = overloadSummary(
                prefix: "You beat the top of the range on every working set.",
                percentRange: percentRange,
                fallback: "Increase the load next time."
            )

            return ProgressiveOverloadCue(
                classification: classification,
                tone: .success,
                title: "Increase load next time",
                summary: summary,
                direction: .increaseLoad,
                suggestedPercentRange: percentRange
            )
        }

        if actualReps.allSatisfy({ $0 < targetRepMin }) {
            let summary = overloadSummary(
                prefix: "You landed below the bottom of the range on every working set.",
                percentRange: percentRange,
                fallback: "Reduce the load next time."
            )

            return ProgressiveOverloadCue(
                classification: classification,
                tone: .caution,
                title: "Reduce load next time",
                summary: summary,
                direction: .decreaseLoad,
                suggestedPercentRange: percentRange
            )
        }

        return ProgressiveOverloadCue(
            classification: classification,
            tone: .accent,
            title: "Stay here until you own the range",
            summary: "Keep the load steady until your working sets consistently land inside \(targetRepMin)-\(targetRepMax) reps.",
            direction: .stayCourse,
            suggestedPercentRange: nil
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

    private func suggestedPercentRange(for classification: TrainingExerciseClassification) -> ClosedRange<Double>? {
        switch classification {
        case .lowerBodyCompound:
            return 5...10
        case .upperBodyCompound, .isolation, .core, .unknown:
            return 2.5...5
        case .conditioning:
            return nil
        }
    }

    private func overloadSummary(prefix: String, percentRange: ClosedRange<Double>?, fallback: String) -> String {
        guard let percentRange else {
            return "\(prefix) \(fallback)"
        }

        let lowerBound = WGJFormatters.oneDecimalString(percentRange.lowerBound)
        let upperBound = WGJFormatters.oneDecimalString(percentRange.upperBound)
        return "\(prefix) Try \(lowerBound)-\(upperBound)% more load, or the smallest available plate jump."
    }
}
