import Foundation
import Testing
@testable import WGJ

struct WorkoutSetCompletionControlPresentationTests {
    @Test
    func incompleteManualSetUsesInlineCheckButtonWithoutSupplementalRow() {
        let draft = WorkoutSessionSetDraft(isCompleted: false)

        let presentation = WorkoutSetCompletionControlPresentation.make(
            draft: draft,
            manualCompletionMode: true,
            isSetCompletionEnabled: true,
            gatePresentation: nil,
            isGateRevealed: false,
            isPendingBozarCompletion: false
        )

        #expect(presentation?.inlineButton == WorkoutSetCompletionControlPresentation.InlineButton(
            label: "Complete set",
            systemImage: "checkmark.circle",
            tone: .ready,
            targetIsCompleted: true
        ))
        #expect(presentation?.supplementalRow == nil)
    }

    @Test
    func completedManualSetUsesInlineUndoCheckButtonWithoutSupplementalRow() {
        let draft = WorkoutSessionSetDraft(isCompleted: true)

        let presentation = WorkoutSetCompletionControlPresentation.make(
            draft: draft,
            manualCompletionMode: true,
            isSetCompletionEnabled: true,
            gatePresentation: nil,
            isGateRevealed: false,
            isPendingBozarCompletion: false
        )

        #expect(presentation?.inlineButton == WorkoutSetCompletionControlPresentation.InlineButton(
            label: "Mark set incomplete",
            systemImage: "checkmark.circle.fill",
            tone: .completed,
            targetIsCompleted: false
        ))
        #expect(presentation?.supplementalRow == nil)
    }

    @Test
    func gatedManualSetKeepsInlineActionAndOnlyShowsNoticeAfterTap() {
        let draft = WorkoutSessionSetDraft(isCompleted: false)
        let gate = WorkoutSetCompletionGatePresentation(
            title: "Missing values",
            detail: "Add reps or weight first.",
            iconSystemName: "lock.fill"
        )

        let hidden = WorkoutSetCompletionControlPresentation.make(
            draft: draft,
            manualCompletionMode: true,
            isSetCompletionEnabled: false,
            gatePresentation: gate,
            isGateRevealed: false,
            isPendingBozarCompletion: false
        )
        let revealed = WorkoutSetCompletionControlPresentation.make(
            draft: draft,
            manualCompletionMode: true,
            isSetCompletionEnabled: false,
            gatePresentation: gate,
            isGateRevealed: true,
            isPendingBozarCompletion: false
        )

        #expect(hidden?.inlineButton == WorkoutSetCompletionControlPresentation.InlineButton(
            label: "Complete set",
            systemImage: "checkmark.circle",
            tone: .gated,
            targetIsCompleted: true
        ))
        #expect(hidden?.supplementalRow == nil)
        #expect(revealed?.supplementalRow == .gateNotice(gate))
    }

    @Test
    func pendingBozarCompletionShowsLoadingSupplementalRow() {
        let draft = WorkoutSessionSetDraft(isCompleted: false)

        let presentation = WorkoutSetCompletionControlPresentation.make(
            draft: draft,
            manualCompletionMode: true,
            isSetCompletionEnabled: true,
            gatePresentation: nil,
            isGateRevealed: false,
            isPendingBozarCompletion: true
        )

        #expect(presentation?.inlineButton == WorkoutSetCompletionControlPresentation.InlineButton(
            label: "Complete set",
            systemImage: "checkmark.circle",
            tone: .ready,
            targetIsCompleted: true
        ))
        #expect(presentation?.supplementalRow == .pendingBozarCompletion)
    }

    @Test
    func automaticCompletionModeHasNoManualControl() {
        let draft = WorkoutSessionSetDraft(isCompleted: false)

        let presentation = WorkoutSetCompletionControlPresentation.make(
            draft: draft,
            manualCompletionMode: false,
            isSetCompletionEnabled: true,
            gatePresentation: nil,
            isGateRevealed: false,
            isPendingBozarCompletion: false
        )

        #expect(presentation == nil)
    }

    @Test
    func inlineButtonFactorySupportsDropStageCompletionToggle() {
        let incomplete = WorkoutSetCompletionControlPresentation.InlineButton.make(
            isCompleted: false,
            completedLabel: "Undo drop 1",
            incompleteLabel: "Complete drop 1",
            isSetCompletionEnabled: true
        )
        let completed = WorkoutSetCompletionControlPresentation.InlineButton.make(
            isCompleted: true,
            completedLabel: "Undo drop 1",
            incompleteLabel: "Complete drop 1",
            isSetCompletionEnabled: true
        )
        let gated = WorkoutSetCompletionControlPresentation.InlineButton.make(
            isCompleted: false,
            completedLabel: "Undo drop 1",
            incompleteLabel: "Complete drop 1",
            isSetCompletionEnabled: false
        )

        #expect(incomplete == WorkoutSetCompletionControlPresentation.InlineButton(
            label: "Complete drop 1",
            systemImage: "checkmark.circle",
            tone: .ready,
            targetIsCompleted: true
        ))
        #expect(completed == WorkoutSetCompletionControlPresentation.InlineButton(
            label: "Undo drop 1",
            systemImage: "checkmark.circle.fill",
            tone: .completed,
            targetIsCompleted: false
        ))
        #expect(gated == WorkoutSetCompletionControlPresentation.InlineButton(
            label: "Complete drop 1",
            systemImage: "checkmark.circle",
            tone: .gated,
            targetIsCompleted: true
        ))
    }

    @Test
    func completedExerciseEmphasisDoesNotInsertLayoutBadgeOrAnimatedBackground() throws {
        let source = try String(contentsOf: workoutGridEditorSourceURL(), encoding: .utf8)

        #expect(!source.contains("completedExerciseBadge"))
        #expect(!source.contains("""
                if shouldEmphasizeCompletedExercise {
                    completedExerciseBadge
                }
"""))
        #expect(source.contains("private var completedExerciseBackgroundStyle: AnyShapeStyle"))
        #expect(source.contains("transaction.animation = nil"))
    }
}

private func workoutGridEditorSourceURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("WGJ")
        .appendingPathComponent("Views")
        .appendingPathComponent("Workout")
        .appendingPathComponent("WorkoutSessionExerciseGridEditor.swift")
}
