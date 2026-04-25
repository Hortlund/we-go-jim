import Foundation
import Testing
@testable import WGJ

@MainActor
struct ResponsiveInputStateTests {
    @Test
    func liveTypingDoesNotChangeCommittedTextUntilCommit() {
        var draft = WGJResponsiveTextDraft(committedText: "Leg Day")

        draft.stageLiveText("Leg Day Heavy")

        #expect(draft.liveText == "Leg Day Heavy")
        #expect(draft.committedText == "Leg Day")
        #expect(draft.hasUncommittedChanges)

        let committed = draft.commitLiveText()

        #expect(committed == "Leg Day Heavy")
        #expect(draft.committedText == "Leg Day Heavy")
        #expect(draft.hasUncommittedChanges == false)
    }

    @Test
    func externalCommittedTextSyncDoesNotClobberDirtyLiveText() {
        var draft = WGJResponsiveTextDraft(committedText: "Push")

        draft.stageLiveText("Push Hypertrophy")
        draft.syncCommittedText("Push Day")

        #expect(draft.liveText == "Push Hypertrophy")
        #expect(draft.committedText == "Push Day")
        #expect(draft.hasUncommittedChanges)
    }

    @Test
    func workoutMetricTypingStaysBufferedUntilCommit() {
        let setID = UUID()
        let originalDraft = WorkoutSessionSetDraft(id: setID, targetLoadUnit: .kg)
        var drafts = [originalDraft]
        var buffer = WorkoutMetricInputDraftBuffer()

        buffer.stage("12", for: setID, metric: .reps)
        buffer.stage("95.5", for: setID, metric: .weight)

        #expect(drafts == [originalDraft])
        #expect(buffer.text(for: setID, metric: .reps) == "12")
        #expect(buffer.text(for: setID, metric: .weight) == "95.5")

        let changed = buffer.commit(
            setID: setID,
            metric: .weight,
            drafts: &drafts,
            preferredLoadUnit: .kg,
            manualCompletionMode: true
        )

        #expect(changed)
        #expect(drafts[0].actualWeight == 95.5)
        #expect(drafts[0].actualReps == nil)
        #expect(buffer.text(for: setID, metric: .weight) == nil)
        #expect(buffer.text(for: setID, metric: .reps) == "12")
    }

    @Test
    func workoutMetricBufferedCommitCanFlushAllFocusedInput() {
        let setID = UUID()
        var drafts = [WorkoutSessionSetDraft(id: setID, targetLoadUnit: .bodyweight, actualLoadUnit: .bodyweight)]
        var buffer = WorkoutMetricInputDraftBuffer()

        buffer.stage("100", for: setID, metric: .weight)
        buffer.stage("8", for: setID, metric: .reps)

        let changed = buffer.commitAll(
            drafts: &drafts,
            preferredLoadUnit: .lb,
            manualCompletionMode: false
        )

        #expect(changed)
        #expect(drafts[0].actualWeight == 100)
        #expect(drafts[0].actualLoadUnit == .lb)
        #expect(drafts[0].actualReps == 8)
        #expect(drafts[0].isCompleted)
        #expect(buffer.text(for: setID, metric: .weight) == nil)
        #expect(buffer.text(for: setID, metric: .reps) == nil)
    }
}
