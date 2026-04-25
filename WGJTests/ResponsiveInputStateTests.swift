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
}
