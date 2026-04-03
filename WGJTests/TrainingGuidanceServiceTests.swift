import Foundation
import Testing
@testable import WGJ

@MainActor
struct TrainingGuidanceServiceTests {
    private let service = TrainingGuidanceService()

    @Test
    func lowerBodyCompoundRecommendationUsesHeavyDefaults() {
        let recommendation = service.templateRecommendation(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Back Squat",
                categoryName: "Legs",
                equipmentSummary: "Barbell",
                primaryMuscleNames: "Quads, Glutes"
            )
        )

        #expect(recommendation.classification == .lowerBodyCompound)
        #expect(recommendation.suggestedWarmupSets == 2...2)
        #expect(recommendation.suggestedWorkingSets == 3...4)
        #expect(recommendation.suggestedRepRange == 5...8)
        #expect(recommendation.suggestedRestSeconds == 120...180)
    }

    @Test
    func upperBodyCompoundRecommendationUsesModerateDefaults() {
        let recommendation = service.templateRecommendation(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Bench Press",
                categoryName: "Chest",
                equipmentSummary: "Barbell",
                primaryMuscleNames: "Chest, Triceps"
            )
        )

        #expect(recommendation.classification == .upperBodyCompound)
        #expect(recommendation.suggestedWarmupSets == 1...2)
        #expect(recommendation.suggestedRepRange == 6...10)
    }

    @Test
    func isolationRecommendationUsesHigherRepDefaults() {
        let recommendation = service.templateRecommendation(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Cable Curl",
                categoryName: "Arms",
                equipmentSummary: "Cable",
                primaryMuscleNames: "Biceps"
            )
        )

        #expect(recommendation.classification == .isolation)
        #expect(recommendation.suggestedWarmupSets == 0...1)
        #expect(recommendation.suggestedRepRange == 10...15)
        #expect(recommendation.suggestedRestSeconds == 45...90)
    }

    @Test
    func coreRecommendationUsesCoreDefaults() {
        let recommendation = service.templateRecommendation(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Cable Crunch",
                categoryName: "Core",
                equipmentSummary: "Cable",
                primaryMuscleNames: "Abs"
            )
        )

        #expect(recommendation.classification == .core)
        #expect(recommendation.suggestedWarmupSets == 0...1)
        #expect(recommendation.suggestedRepRange == 8...15)
    }

    @Test
    func conditioningRecommendationUsesConditioningDefaults() {
        let recommendation = service.templateRecommendation(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Assault Bike Sprint",
                categoryName: "Conditioning",
                equipmentSummary: "Bike",
                primaryMuscleNames: ""
            )
        )

        #expect(recommendation.classification == .conditioning)
        #expect(recommendation.suggestedWarmupSets == 1...2)
        #expect(recommendation.suggestedWorkingSets == 3...5)
        #expect(recommendation.suggestedRepRange == 8...20)
        #expect(recommendation.suggestedRestSeconds == 45...90)
    }

    @Test
    func unknownRecommendationFallsBackToGeneralDefaults() {
        let recommendation = service.templateRecommendation(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Machine Thing",
                categoryName: "",
                equipmentSummary: "",
                primaryMuscleNames: ""
            )
        )

        #expect(recommendation.classification == .unknown)
        #expect(recommendation.suggestedWarmupSets == 1...2)
        #expect(recommendation.suggestedWorkingSets == 3...3)
        #expect(recommendation.suggestedRepRange == 8...12)
        #expect(recommendation.suggestedRestSeconds == 60...120)
    }

    @Test
    func overloadCueRecommendsIncreaseWhenAllSetsBeatTopRange() {
        let cue = service.progressiveOverloadCue(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Bench Press",
                categoryName: "Chest",
                equipmentSummary: "Barbell",
                primaryMuscleNames: "Chest"
            ),
            targetRepMin: 6,
            targetRepMax: 8,
            setDrafts: [
                makeWorkoutSet(reps: 9, weight: 100, completed: true),
                makeWorkoutSet(reps: 10, weight: 100, completed: true),
            ]
        )

        #expect(cue?.direction == .increaseLoad)
        #expect(cue?.suggestedPercentRange == 2.5...5)
    }

    @Test
    func overloadCueRecommendsDecreaseWhenAllSetsMissBottomRange() {
        let cue = service.progressiveOverloadCue(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Back Squat",
                categoryName: "Legs",
                equipmentSummary: "Barbell",
                primaryMuscleNames: "Quads"
            ),
            targetRepMin: 5,
            targetRepMax: 8,
            setDrafts: [
                makeWorkoutSet(reps: 3, weight: 140, completed: true),
                makeWorkoutSet(reps: 4, weight: 140, completed: true),
            ]
        )

        #expect(cue?.direction == .decreaseLoad)
        #expect(cue?.suggestedPercentRange == 5...10)
    }

    @Test
    func overloadCueUsesNeutralGuidanceInsideRange() {
        let cue = service.progressiveOverloadCue(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Bench Press",
                categoryName: "Chest",
                equipmentSummary: "Barbell",
                primaryMuscleNames: "Chest"
            ),
            targetRepMin: 6,
            targetRepMax: 8,
            setDrafts: [
                makeWorkoutSet(reps: 6, weight: 100, completed: true),
                makeWorkoutSet(reps: 8, weight: 100, completed: true),
            ]
        )

        #expect(cue?.direction == .stayCourse)
        #expect(cue?.suggestedPercentRange == nil)
    }

    @Test
    func overloadCueRequiresLoggedReps() {
        let cue = service.progressiveOverloadCue(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Bench Press",
                categoryName: "Chest",
                equipmentSummary: "Barbell",
                primaryMuscleNames: "Chest"
            ),
            targetRepMin: 6,
            targetRepMax: 8,
            setDrafts: [
                makeWorkoutSet(reps: nil, weight: 100, completed: true),
            ]
        )

        #expect(cue == nil)
    }

    @Test
    func overloadCueRequiresLoggedLoad() {
        let cue = service.progressiveOverloadCue(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Bench Press",
                categoryName: "Chest",
                equipmentSummary: "Barbell",
                primaryMuscleNames: "Chest"
            ),
            targetRepMin: 6,
            targetRepMax: 8,
            setDrafts: [
                makeWorkoutSet(reps: 10, weight: nil, completed: true),
            ]
        )

        #expect(cue == nil)
    }

    @Test
    func overloadCueIgnoresBodyweightSets() {
        let cue = service.progressiveOverloadCue(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Pull Up",
                categoryName: "Back",
                equipmentSummary: "Pull-up Bar",
                primaryMuscleNames: "Lats"
            ),
            targetRepMin: 6,
            targetRepMax: 8,
            setDrafts: [
                makeWorkoutSet(reps: 10, weight: 0, unit: .bodyweight, completed: true),
            ]
        )

        #expect(cue == nil)
    }

    @Test
    func activeWorkoutGuidanceUpgradesToIncreaseCueWhenCompleted() {
        let snapshot = TrainingGuidanceCatalogSnapshot(
            exerciseName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            primaryMuscleNames: "Chest"
        )
        let recommendation = service.templateRecommendation(for: snapshot)
        let cue = service.progressiveOverloadCue(
            for: snapshot,
            targetRepMin: 6,
            targetRepMax: 8,
            setDrafts: [
                makeWorkoutSet(reps: 9, weight: 100, completed: true),
                makeWorkoutSet(reps: 10, weight: 100, completed: true),
            ]
        )

        let presentation = ActiveWorkoutExerciseGuidancePresentation.make(
            recommendation: recommendation,
            cue: cue,
            isExerciseCompleted: true
        )

        let expectedRange = "\(WGJFormatters.oneDecimalString(2.5))-5%"
        #expect(presentation.title == "Increase load next time")
        #expect(presentation.summary == "Add \(expectedRange) next time, or use the smallest clean plate jump.")
        #expect(presentation.tone == .success)
    }

    @Test
    func activeWorkoutGuidanceUsesRecommendationUntilExerciseCompletes() {
        let snapshot = TrainingGuidanceCatalogSnapshot(
            exerciseName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            primaryMuscleNames: "Chest"
        )
        let recommendation = service.templateRecommendation(for: snapshot)
        let cue = service.progressiveOverloadCue(
            for: snapshot,
            targetRepMin: 6,
            targetRepMax: 8,
            setDrafts: [
                makeWorkoutSet(reps: 9, weight: 100, completed: true),
                makeWorkoutSet(reps: 10, weight: 100, completed: false),
            ]
        )

        let presentation = ActiveWorkoutExerciseGuidancePresentation.make(
            recommendation: recommendation,
            cue: cue,
            isExerciseCompleted: false
        )

        #expect(presentation.title == recommendation.title)
        #expect(presentation.summary == recommendation.summary)
        #expect(presentation.tone == recommendation.tone)
    }

    @Test
    func activeWorkoutGuidanceShowsStayCourseCueWhenCompletedInsideRange() {
        let snapshot = TrainingGuidanceCatalogSnapshot(
            exerciseName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            primaryMuscleNames: "Chest"
        )
        let recommendation = service.templateRecommendation(for: snapshot)
        let cue = service.progressiveOverloadCue(
            for: snapshot,
            targetRepMin: 6,
            targetRepMax: 8,
            setDrafts: [
                makeWorkoutSet(reps: 6, weight: 100, completed: true),
                makeWorkoutSet(reps: 8, weight: 100, completed: true),
            ]
        )

        let presentation = ActiveWorkoutExerciseGuidancePresentation.make(
            recommendation: recommendation,
            cue: cue,
            isExerciseCompleted: true
        )

        #expect(presentation.title == "Stay here until you own the range")
        #expect(presentation.summary == "Keep the load steady until your working sets consistently land inside 6-8 reps.")
        #expect(presentation.tone == .accent)
    }

    @Test
    func activeWorkoutControllerCollapsesOnCompletionAndAllowsRepeatCycle() {
        let first = UUID()
        let second = UUID()
        var controller = ActiveWorkoutExerciseCardStateController()

        controller.sync(
            exerciseIDs: [first, second],
            completedExerciseIDs: [],
            firstIncompleteExerciseID: first
        )

        #expect(controller.isExpanded(for: first))
        #expect(!controller.isExpanded(for: second))

        controller.updateCompletion(for: first, isCompleted: true)
        #expect(!controller.isExpanded(for: first))

        controller.setExpanded(true, for: first)
        #expect(controller.isExpanded(for: first))

        controller.updateCompletion(for: first, isCompleted: true)
        #expect(controller.isExpanded(for: first))

        controller.updateCompletion(for: first, isCompleted: false)
        controller.updateCompletion(for: first, isCompleted: true)
        #expect(!controller.isExpanded(for: first))
    }

    @Test
    func activeWorkoutControllerOpensNextIncompleteExerciseWhenCurrentCompletes() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        var controller = ActiveWorkoutExerciseCardStateController()

        controller.sync(
            exerciseIDs: [first, second, third],
            completedExerciseIDs: [],
            firstIncompleteExerciseID: first
        )

        let nextExerciseID = controller.updateCompletion(
            for: first,
            isCompleted: true,
            orderedExerciseIDs: [first, second, third],
            completedExerciseIDs: [first, second]
        )

        #expect(nextExerciseID == third)
        #expect(!controller.isExpanded(for: first))
        #expect(!controller.isExpanded(for: second))
        #expect(controller.isExpanded(for: third))
    }

    private func makeWorkoutSet(
        reps: Int?,
        weight: Double?,
        unit: TemplateLoadUnit = .kg,
        completed: Bool,
        isWarmup: Bool = false
    ) -> WorkoutSessionSetDraft {
        WorkoutSessionSetDraft(
            isWarmup: isWarmup,
            restSeconds: 120,
            targetReps: nil,
            targetWeight: nil,
            targetLoadUnit: unit,
            actualReps: reps,
            actualWeight: weight,
            actualLoadUnit: unit,
            isCompleted: completed,
            isLocked: false
        )
    }
}
