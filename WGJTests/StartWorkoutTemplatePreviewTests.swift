import Foundation
import Testing
@testable import WGJ

@MainActor
struct StartWorkoutTemplatePreviewTests {
    @Test
    func snapshotCopiesTemplateTextAndExerciseOrdering() {
        let template = WorkoutTemplate(
            folderID: TemplateRepository.unfiledFolderID,
            name: "Push Day",
            notes: "  Heavy compounds first  "
        )

        let shoulderPress = TemplateExercise(
            templateID: template.id,
            catalogExerciseUUID: "press-1",
            exerciseNameSnapshot: "Shoulder Press",
            categorySnapshot: "Shoulders",
            muscleSummarySnapshot: "  ",
            restSeconds: 90,
            sortOrder: 0,
            template: template
        )

        let inclinePress = TemplateExercise(
            templateID: template.id,
            catalogExerciseUUID: "incline-1",
            exerciseNameSnapshot: "Incline Press",
            categorySnapshot: "Chest",
            muscleSummarySnapshot: "Upper chest",
            targetRepMin: 8,
            targetRepMax: 10,
            restSeconds: 150,
            sortOrder: 1,
            template: template
        )

        let preCardio = TemplateCardioBlock(
            templateID: template.id,
            phase: .preWorkout,
            catalogExerciseUUID: "bike-1",
            exerciseNameSnapshot: "Bike",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Warmup",
            targetDurationSeconds: 300,
            template: template
        )

        let postCardio = TemplateCardioBlock(
            templateID: template.id,
            phase: .postWorkout,
            catalogExerciseUUID: "treadmill-1",
            exerciseNameSnapshot: "Incline Treadmill Walk",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Cooldown",
            targetDurationSeconds: 1200,
            template: template
        )

        inclinePress.prescribedSets = [
            TemplateExerciseSet(templateExerciseID: inclinePress.id, sortOrder: 0, templateExercise: inclinePress),
            TemplateExerciseSet(templateExerciseID: inclinePress.id, sortOrder: 1, templateExercise: inclinePress),
        ]
        template.cardioBlocks = [postCardio, preCardio]
        template.exercises = [inclinePress, shoulderPress]

        let snapshot = StartWorkoutTemplatePreview(template: template)

        #expect(snapshot.templateID == template.id)
        #expect(snapshot.folderID == TemplateRepository.unfiledFolderID)
        #expect(snapshot.name == "Push Day")
        #expect(snapshot.notes == "Heavy compounds first")
        #expect(snapshot.preWorkoutCardio?.exerciseName == "Bike")
        #expect(snapshot.preWorkoutCardio?.targetDurationSeconds == 300)
        #expect(snapshot.postWorkoutCardio?.exerciseName == "Incline Treadmill Walk")
        #expect(snapshot.postWorkoutCardio?.targetDurationSeconds == 1200)
        #expect(snapshot.exercises.map(\.exerciseName) == ["Shoulder Press", "Incline Press"])
        #expect(snapshot.exercises.map(\.plannedSetCount) == [3, 2])
        #expect(snapshot.exercises.map(\.descriptor) == ["Shoulders", "Upper chest"])
        #expect(snapshot.focusAreaSummary == "2 focus areas")
    }

    @Test
    func snapshotDropsBlankNotesAndDescriptorFallbacks() {
        let template = WorkoutTemplate(
            folderID: UUID(),
            name: "Leg Day",
            notes: "\n  \n"
        )

        let exercise = TemplateExercise(
            templateID: template.id,
            catalogExerciseUUID: "squat-1",
            exerciseNameSnapshot: "Back Squat",
            categorySnapshot: "   ",
            muscleSummarySnapshot: "",
            restSeconds: 120,
            sortOrder: 0,
            template: template
        )

        template.exercises = [exercise]

        let snapshot = StartWorkoutTemplatePreview(template: template)

        #expect(snapshot.notes == nil)
        #expect(snapshot.exercises.count == 1)
        #expect(snapshot.exercises[0].descriptor == nil)
        #expect(snapshot.exercises[0].plannedSetCount == 3)
        #expect(snapshot.focusAreaSummary == nil)
    }

    @Test
    func snapshotCountsUniqueFocusAreasOnce() {
        let template = WorkoutTemplate(
            folderID: UUID(),
            name: "Chest Day",
            notes: ""
        )

        let benchPress = TemplateExercise(
            templateID: template.id,
            catalogExerciseUUID: "bench-1",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Chest",
            muscleSummarySnapshot: "",
            restSeconds: 120,
            sortOrder: 0,
            template: template
        )

        let inclinePress = TemplateExercise(
            templateID: template.id,
            catalogExerciseUUID: "bench-2",
            exerciseNameSnapshot: "Incline Bench Press",
            categorySnapshot: "Chest",
            muscleSummarySnapshot: " ",
            restSeconds: 150,
            sortOrder: 1,
            template: template
        )

        template.exercises = [benchPress, inclinePress]

        let snapshot = StartWorkoutTemplatePreview(template: template)

        #expect(snapshot.focusAreaSummary == "1 focus area")
    }
}
