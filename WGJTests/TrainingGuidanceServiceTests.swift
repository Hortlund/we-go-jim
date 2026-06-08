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
        #expect(cue?.suggestedNextLoad == 102.5)
        #expect(cue?.suggestedLoadUnit == .kg)
        #expect(cue?.suggestedRepRange == 6...8)
        let increaseWeightText = "\(WGJFormatters.decimalString(102.5)) kg"
        #expect(cue?.summary == "You cleared the whole range. Move to \(increaseWeightText) next time and work back into 6-8 clean reps.")
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
        #expect(cue?.suggestedNextLoad == 137.5)
        #expect(cue?.suggestedLoadUnit == .kg)
        #expect(cue?.suggestedRepRange == 5...8)
        let decreaseWeightText = "\(WGJFormatters.decimalString(137.5)) kg"
        #expect(cue?.summary == "You missed the floor. Drop to \(decreaseWeightText) next time and rebuild 5-8 clean reps.")
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
        #expect(cue?.suggestedNextLoad == 100)
        #expect(cue?.suggestedLoadUnit == .kg)
        #expect(cue?.suggestedRepRange == 6...8)
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
        let cue = service.progressiveOverloadCue(
            for: snapshot,
            targetRepMin: 6,
            targetRepMax: 8,
            setDrafts: [
                makeWorkoutSet(reps: 9, weight: 100, completed: true),
                makeWorkoutSet(reps: 10, weight: 100, completed: true),
            ]
        )

        let presentation = ActiveWorkoutExerciseGuidancePresentation.make(cue: cue)

        #expect(presentation?.title == "Increase the load next time")
        let nextWeightText = "\(WGJFormatters.decimalString(102.5)) kg"
        #expect(presentation?.summary == "You cleared the whole range. Move to \(nextWeightText) next time and work back into 6-8 clean reps.")
        #expect(presentation?.tone == .success)
        #expect(presentation?.badge.title == "Increase Load")
        #expect(presentation?.badge.subtitle == "Next: \(nextWeightText)")
        #expect(presentation?.badge.systemImage == "arrow.up.circle.fill")
    }

    @Test
    func activeWorkoutGuidanceIsNilWithoutOverloadCue() {
        let presentation = ActiveWorkoutExerciseGuidancePresentation.make(cue: nil)

        #expect(presentation == nil)
    }

    @Test
    func activeWorkoutGuidanceShowsStayCourseCueWhenCompletedInsideRange() {
        let snapshot = TrainingGuidanceCatalogSnapshot(
            exerciseName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            primaryMuscleNames: "Chest"
        )
        let cue = service.progressiveOverloadCue(
            for: snapshot,
            targetRepMin: 6,
            targetRepMax: 8,
            setDrafts: [
                makeWorkoutSet(reps: 6, weight: 100, completed: true),
                makeWorkoutSet(reps: 8, weight: 100, completed: true),
            ]
        )

        let presentation = ActiveWorkoutExerciseGuidancePresentation.make(cue: cue)

        #expect(presentation?.title == "Keep the load the same")
        #expect(presentation?.summary == "100 kg is in the right spot for now. Keep every work set inside 6-8 before you increase it.")
        #expect(presentation?.tone == .accent)
        #expect(presentation?.badge.title == "Keep Load")
        #expect(presentation?.badge.subtitle == "Next: 100 kg")
        #expect(presentation?.badge.systemImage == "equal.circle.fill")
    }

    @Test
    func activeWorkoutGuidanceShowsSetupCueBeforeWorkingSets() {
        let presentation = service.activeWorkoutGuidance(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Bench Press",
                categoryName: "Chest",
                equipmentSummary: "Barbell",
                primaryMuscleNames: "Chest, Triceps"
            ),
            targetRepMin: 6,
            targetRepMax: 8,
            setDrafts: []
        )

        #expect(presentation.title == "Warm up and set your shoulders")
        #expect(presentation.summary == "Take 1-2 ramp-up sets before the work sets. Pack the shoulders, repeat the same bar path, and aim for 6-8 reps.")
        #expect(presentation.tone == .accent)
        #expect(presentation.badge.title == "Warm Up")
        #expect(presentation.badge.subtitle == "1-2 ramp sets")
        #expect(presentation.badge.systemImage == "flame.circle.fill")
    }

    @Test
    func activeWorkoutGuidanceUsesNextSetCueBeforeExerciseIsFinished() {
        let presentation = service.activeWorkoutGuidance(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Bench Press",
                categoryName: "Chest",
                equipmentSummary: "Barbell",
                primaryMuscleNames: "Chest, Triceps"
            ),
            targetRepMin: 6,
            targetRepMax: 8,
            setDrafts: [
                makeWorkoutSet(reps: 7, weight: 100, completed: true),
                makeWorkoutSet(reps: nil, weight: nil, completed: false),
            ]
        )

        #expect(presentation.title == "Add a rep before increasing load")
        #expect(presentation.summary == "100 kg is still working well. Try to beat 7 with the same setup and keep it inside 6-8.")
        #expect(presentation.tone == .accent)
        #expect(presentation.badge.title == "Reps Up")
        #expect(presentation.badge.subtitle == "Same 100 kg")
        #expect(presentation.badge.systemImage == "arrow.up.circle.fill")
    }

    @Test
    func activeWorkoutGuidanceSupportsBodyweightExercises() {
        let presentation = service.activeWorkoutGuidance(
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

        #expect(presentation.title == "Make the variation harder")
        #expect(presentation.summary == "That set hit 10 reps. Slow the lowering, add a pause, or progress the variation so the next one comes back into 6-8 clean reps.")
        #expect(presentation.tone == .accent)
        #expect(presentation.badge.title == "Reps Down")
        #expect(presentation.badge.subtitle == "Harder variation")
        #expect(presentation.badge.systemImage == "arrow.down.circle.fill")
    }

    @Test
    func activeWorkoutGuidanceUsesRepsUpBadgeWhenSetDropsBelowRange() {
        let presentation = service.activeWorkoutGuidance(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: "Bench Press",
                categoryName: "Chest",
                equipmentSummary: "Barbell",
                primaryMuscleNames: "Chest, Triceps"
            ),
            targetRepMin: 6,
            targetRepMax: 8,
            setDrafts: [
                makeWorkoutSet(reps: 4, weight: 100, completed: true),
                makeWorkoutSet(reps: nil, weight: nil, completed: false),
            ]
        )

        #expect(presentation.title == "Get the reps back")
        #expect(presentation.summary == "That set dropped to 4 reps. Take a little more rest or reduce the load so the next set gets back into 6-8 clean reps.")
        #expect(presentation.tone == .caution)
        #expect(presentation.badge.title == "Reps Up")
        #expect(presentation.badge.subtitle == "Rest or reduce load")
        #expect(presentation.badge.systemImage == "arrow.up.circle.fill")
    }

    @Test
    func activeWorkoutControllerKeepsExerciseExpandedWhenItCompletes() {
        let first = UUID()
        let second = UUID()
        var controller = ActiveWorkoutExerciseCardStateController()

        controller.sync(
            exerciseIDs: [first, second],
            completedExerciseIDs: [],
            firstIncompleteExerciseID: first
        )

        #expect(!controller.isExpanded(for: first))
        #expect(!controller.isExpanded(for: second))

        controller.setExpanded(true, for: first)
        controller.updateCompletion(for: first, isCompleted: true)
        #expect(controller.isExpanded(for: first))

        controller.setExpanded(false, for: first)
        controller.updateCompletion(for: first, isCompleted: true)
        #expect(!controller.isExpanded(for: first))

        controller.updateCompletion(for: first, isCompleted: false)
        controller.setExpanded(true, for: first)
        controller.updateCompletion(for: first, isCompleted: true)
        #expect(controller.isExpanded(for: first))
    }

    @Test
    func activeWorkoutControllerDoesNotOpenNextIncompleteExerciseWhenCurrentCompletes() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        var controller = ActiveWorkoutExerciseCardStateController()

        controller.sync(
            exerciseIDs: [first, second, third],
            completedExerciseIDs: [],
            firstIncompleteExerciseID: first
        )

        controller.updateCompletion(
            for: first,
            isCompleted: true
        )

        #expect(!controller.isExpanded(for: first))
        #expect(!controller.isExpanded(for: second))
        #expect(!controller.isExpanded(for: third))
    }

    @Test
    func activeWorkoutControllerDoesNotOpenFirstIncompleteAfterGateUnlocks() {
        let first = UUID()
        let second = UUID()
        var controller = ActiveWorkoutExerciseCardStateController()

        controller.sync(
            exerciseIDs: [first, second],
            completedExerciseIDs: [],
            firstIncompleteExerciseID: nil
        )

        controller.expandFirstIncompleteIfNeeded(first)

        #expect(!controller.isExpanded(for: first))
        #expect(!controller.isExpanded(for: second))
    }

    @Test
    func activeWorkoutCompletionScrollPolicyDoesNotReanchorWhenExerciseCompletes() {
        let exerciseID = UUID()

        #expect(ActiveWorkoutCompletionScrollPolicy.targetAfterCompletionChange(
            exerciseID: exerciseID,
            didTransitionToCompleted: true
        ) == nil)

        #expect(ActiveWorkoutCompletionScrollPolicy.targetAfterCompletionChange(
            exerciseID: exerciseID,
            didTransitionToCompleted: false
        ) == nil)
    }

    @Test
    func activeWorkoutMinimizeRestorePolicyUsesVisibleExerciseInsteadOfLastExercise() {
        let first = UUID()
        let middle = UUID()
        let last = UUID()

        let target = ActiveWorkoutMinimizeScrollRestorePolicy.target(
            currentScrollTarget: .exercise(middle),
            expandedExerciseIDs: [],
            orderedExerciseIDs: [first, middle, last],
            hasPreWorkoutCardio: false,
            hasPostWorkoutCardio: false
        )

        #expect(target == .exercise(middle))
    }

    @Test
    func activeWorkoutMinimizeRestorePolicyFallsBackToExpandedExerciseBeforeFirstExercise() {
        let first = UUID()
        let expanded = UUID()
        let last = UUID()

        let target = ActiveWorkoutMinimizeScrollRestorePolicy.target(
            currentScrollTarget: nil,
            expandedExerciseIDs: [expanded],
            orderedExerciseIDs: [first, expanded, last],
            hasPreWorkoutCardio: false,
            hasPostWorkoutCardio: false
        )

        #expect(target == .exercise(expanded))
    }

    @Test
    func activeWorkoutControllerRestoresExpandedExercisesAcrossMinimize() {
        let first = UUID()
        let second = UUID()
        var controller = ActiveWorkoutExerciseCardStateController()

        controller.sync(
            exerciseIDs: [first, second],
            completedExerciseIDs: [],
            firstIncompleteExerciseID: first
        )
        controller.setExpanded(true, for: second)

        let expandedIDs = controller.expandedExerciseIDs()
        var restored = ActiveWorkoutExerciseCardStateController()
        restored.sync(
            exerciseIDs: [first, second],
            completedExerciseIDs: [],
            firstIncompleteExerciseID: first
        )
        restored.restoreExpandedExerciseIDs(expandedIDs)

        #expect(!restored.isExpanded(for: first))
        #expect(restored.isExpanded(for: second))
    }

    @Test
    func activeWorkoutControllerRestoresCompletedExpandedExercisesAcrossMinimize() {
        let first = UUID()
        let second = UUID()
        var controller = ActiveWorkoutExerciseCardStateController()

        controller.sync(
            exerciseIDs: [first, second],
            completedExerciseIDs: [],
            firstIncompleteExerciseID: first
        )
        controller.setExpanded(true, for: first)
        controller.updateCompletion(for: first, isCompleted: true)

        let expandedIDs = controller.expandedExerciseIDs()
        var restored = ActiveWorkoutExerciseCardStateController()
        restored.sync(
            exerciseIDs: [first, second],
            completedExerciseIDs: [first],
            firstIncompleteExerciseID: second
        )
        restored.restoreExpandedExerciseIDs(expandedIDs)

        #expect(restored.isExpanded(for: first))
        #expect(!restored.isExpanded(for: second))
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
