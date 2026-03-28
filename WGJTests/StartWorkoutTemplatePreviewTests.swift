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

        inclinePress.prescribedSets = [
            TemplateExerciseSet(templateExerciseID: inclinePress.id, sortOrder: 0, templateExercise: inclinePress),
            TemplateExerciseSet(templateExerciseID: inclinePress.id, sortOrder: 1, templateExercise: inclinePress),
        ]
        template.exercises = [inclinePress, shoulderPress]

        let snapshot = StartWorkoutTemplatePreview(template: template)

        #expect(snapshot.templateID == template.id)
        #expect(snapshot.folderID == TemplateRepository.unfiledFolderID)
        #expect(snapshot.name == "Push Day")
        #expect(snapshot.notes == "Heavy compounds first")
        #expect(snapshot.exercises.map(\.exerciseName) == ["Shoulder Press", "Incline Press"])
        #expect(snapshot.exercises.map(\.plannedSetCount) == [3, 2])
        #expect(snapshot.exercises.map(\.descriptor) == ["Shoulders", "Upper chest"])
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
    }
}
