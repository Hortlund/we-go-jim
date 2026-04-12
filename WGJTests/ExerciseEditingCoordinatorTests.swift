import Foundation
import Testing
@testable import WGJ

@MainActor
struct ExerciseEditingCoordinatorTests {
    @Test
    func workoutCoordinatorDebouncesDraftCommitsToLatestValue() async {
        let initialDraft = WorkoutSessionSetDraft(targetReps: 8, targetWeight: 100, targetLoadUnit: .kg)
        let updatedDraft = WorkoutSessionSetDraft(
            id: initialDraft.id,
            targetReps: 8,
            targetWeight: 100,
            targetLoadUnit: .kg,
            actualReps: 6,
            actualWeight: 120,
            actualLoadUnit: .kg
        )
        let latestDraft = WorkoutSessionSetDraft(
            id: initialDraft.id,
            targetReps: 8,
            targetWeight: 100,
            targetLoadUnit: .kg,
            actualReps: 5,
            actualWeight: 125,
            actualLoadUnit: .kg
        )

        var committedDrafts: [[WorkoutSessionSetDraft]] = []
        let coordinator = WorkoutExerciseEditingCoordinator(
            setDrafts: [initialDraft],
            restSeconds: 120,
            notes: "",
            commitDebounce: .milliseconds(10),
            onDraftsCommitted: { committedDrafts.append($0) },
            onRestCommitted: { _ in },
            onNotesCommitted: { _ in },
            onCompletionChanged: { _, _, _, _ in }
        )

        coordinator.scheduleDraftCommit([updatedDraft])
        coordinator.scheduleDraftCommit([latestDraft])

        for _ in 0..<20 where committedDrafts.isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
            await Task.yield()
        }

        #expect(committedDrafts.count == 1)
        #expect(committedDrafts.first == [latestDraft])
    }

    @Test
    func workoutCoordinatorFlushesPendingCommitImmediately() {
        let initialDraft = WorkoutSessionSetDraft(targetReps: 8, targetWeight: 100, targetLoadUnit: .kg)
        let updatedDraft = WorkoutSessionSetDraft(
            id: initialDraft.id,
            targetReps: 8,
            targetWeight: 100,
            targetLoadUnit: .kg,
            actualReps: 4,
            actualWeight: 110,
            actualLoadUnit: .kg
        )

        var committedDrafts: [[WorkoutSessionSetDraft]] = []
        var committedRests: [Int] = []
        let coordinator = WorkoutExerciseEditingCoordinator(
            setDrafts: [initialDraft],
            restSeconds: 120,
            notes: "",
            onDraftsCommitted: { committedDrafts.append($0) },
            onRestCommitted: { committedRests.append($0) },
            onNotesCommitted: { _ in },
            onCompletionChanged: { _, _, _, _ in }
        )

        coordinator.scheduleDraftCommit([updatedDraft])
        coordinator.scheduleRestCommit(150)
        coordinator.requestImmediateCommit(setDrafts: [updatedDraft], restSeconds: 150, notes: "")

        #expect(committedDrafts == [[updatedDraft]])
        #expect(committedRests == [150])
    }

    @Test
    func workoutCoordinatorFlushesLatestScheduledDraftsWhenImmediateCommitUsesStaleInputs() {
        let initialDraft = WorkoutSessionSetDraft(targetReps: 8, targetWeight: 100, targetLoadUnit: .kg)
        let bozarResolvedDraft = WorkoutSessionSetDraft(
            id: initialDraft.id,
            targetReps: 8,
            targetWeight: 100,
            targetLoadUnit: .kg,
            actualReps: 8,
            actualWeight: 100,
            actualLoadUnit: .kg,
            isCompleted: true
        )

        var committedDrafts: [[WorkoutSessionSetDraft]] = []
        let coordinator = WorkoutExerciseEditingCoordinator(
            setDrafts: [initialDraft],
            restSeconds: 120,
            notes: "",
            onDraftsCommitted: { committedDrafts.append($0) },
            onRestCommitted: { _ in },
            onNotesCommitted: { _ in },
            onCompletionChanged: { _, _, _, _ in }
        )

        coordinator.scheduleDraftCommit([bozarResolvedDraft])
        coordinator.requestImmediateCommit(setDrafts: [initialDraft], restSeconds: 120, notes: "")

        #expect(committedDrafts == [[bozarResolvedDraft]])
    }

    @Test
    func workoutCoordinatorRelaysCompletionImmediately() {
        let setID = UUID()
        var receivedEvent: (UUID, String?, Int, Bool)?
        let coordinator = WorkoutExerciseEditingCoordinator(
            setDrafts: [],
            restSeconds: 120,
            notes: "",
            onDraftsCommitted: { _ in },
            onRestCommitted: { _ in },
            onNotesCommitted: { _ in },
            onCompletionChanged: { setID, setLabel, restSeconds, isCompleted in
                receivedEvent = (setID, setLabel, restSeconds, isCompleted)
            }
        )

        coordinator.relayCompletionChange(
            setID: setID,
            setLabel: "Working Set 2",
            restSeconds: 90,
            isCompleted: true
        )

        #expect(receivedEvent?.0 == setID)
        #expect(receivedEvent?.1 == "Working Set 2")
        #expect(receivedEvent?.2 == 90)
        #expect(receivedEvent?.3 == true)
    }

    @Test
    func templateCoordinatorFlushesRepRangeAndDraftsImmediately() {
        let initialDraft = TemplateExerciseSetDraft(targetReps: 8, targetWeight: 100, loadUnit: .kg)
        let updatedDraft = TemplateExerciseSetDraft(
            id: initialDraft.id,
            targetReps: 10,
            targetWeight: 105,
            loadUnit: .kg
        )

        var committedRanges: [(Int?, Int?)] = []
        var committedRests: [Int] = []
        var committedNotes: [String] = []
        var committedDrafts: [[TemplateExerciseSetDraft]] = []
        let coordinator = TemplateExerciseEditingCoordinator(
            notes: "",
            targetRepMin: 6,
            targetRepMax: 8,
            restSeconds: 120,
            setDrafts: [initialDraft],
            onNotesCommitted: { committedNotes.append($0) },
            onRepRangeCommitted: { committedRanges.append(($0, $1)) },
            onRestCommitted: { committedRests.append($0) },
            onSetDraftsCommitted: { committedDrafts.append($0) }
        )

        coordinator.scheduleNotesCommit("Use a smooth tempo.")
        coordinator.scheduleRepRangeCommit(targetRepMin: 8, targetRepMax: 10)
        coordinator.scheduleSetDraftCommit([updatedDraft])
        coordinator.scheduleRestCommit(150)
        coordinator.requestImmediateCommit(
            notes: "Use a smooth tempo.",
            targetRepMin: 8,
            targetRepMax: 10,
            restSeconds: 150,
            setDrafts: [updatedDraft]
        )

        #expect(committedRanges.count == 1)
        #expect(committedRanges.first?.0 == 8)
        #expect(committedRanges.first?.1 == 10)
        #expect(committedRests == [150])
        #expect(committedNotes == ["Use a smooth tempo."])
        #expect(committedDrafts == [[updatedDraft]])
    }
}
