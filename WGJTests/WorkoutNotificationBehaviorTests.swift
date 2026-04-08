import Testing
import UserNotifications
@testable import WGJ

@MainActor
struct WorkoutNotificationBehaviorTests {
    @Test
    func restTimerNotificationsUseDefaultSystemSound() {
        let descriptor = RestTimerNotificationManager.notificationDescriptor(
            style: .standard
        )

        #expect(descriptor.title == "Rest complete")
        #expect(descriptor.subtitle.isEmpty)
        #expect(descriptor.body == "Time for your next set.")
        #expect(descriptor.usesDefaultSound)
        #expect(descriptor.interruptionLevel == .active)
    }

    @Test
    func timeSensitiveRestTimerNotificationsKeepTimeSensitiveInterruptionLevel() {
        let descriptor = RestTimerNotificationManager.notificationDescriptor(
            style: .timeSensitive
        )

        #expect(descriptor.usesDefaultSound)
        #expect(descriptor.interruptionLevel == .timeSensitive)
    }

    @Test
    func nextRestTimerContextUsesUpcomingWorkingSetLabel() {
        var drafts = [
            WorkoutSessionSetDraft(isWarmup: false),
            WorkoutSessionSetDraft(isWarmup: false),
            WorkoutSessionSetDraft(isWarmup: false)
        ]
        drafts[1].isCompleted = true

        #expect(
            WorkoutRestTimerContextBuilder.nextSetLabel(
                afterCompletingSetAt: 1,
                in: drafts
            ) == "Working Set 3"
        )
    }

    @Test
    func nextRestTimerContextFallsBackWhenNoUpcomingSetExists() {
        var drafts = [
            WorkoutSessionSetDraft(isWarmup: true),
            WorkoutSessionSetDraft(isWarmup: false)
        ]
        drafts[1].isCompleted = true

        #expect(
            WorkoutRestTimerContextBuilder.nextSetLabel(
                afterCompletingSetAt: 1,
                in: drafts
            ) == nil
        )
    }

    @Test
    func foregroundRestTimerFeedbackNeverPlaysSound() {
        #expect(!WorkoutNotificationStyle.standard.foregroundRestTimerAlertPolicy.playsSound)
        #expect(!WorkoutNotificationStyle.timeSensitive.foregroundRestTimerAlertPolicy.playsSound)
        #expect(!WorkoutNotificationStyle.standard.foregroundRestTimerAlertPolicy.usesEnhancedHaptics)
        #expect(WorkoutNotificationStyle.timeSensitive.foregroundRestTimerAlertPolicy.usesEnhancedHaptics)
    }

    @Test
    func restTimerNotificationsStaySilentWhileForegrounded() {
        #expect(
            WGJNotificationCenterDelegate.presentationOptions(
                isRestTimerNotification: true,
                isBrosReactionNotification: false
            ).isEmpty
        )
        #expect(
            WGJNotificationCenterDelegate.presentationOptions(
                isRestTimerNotification: false,
                isBrosReactionNotification: true
            ).contains(.sound)
        )
    }

    @Test
    func workoutNotificationStylesKeepExpectedInterruptionLevels() {
        #expect(WorkoutNotificationStyle.standard.notificationInterruptionLevel == .active)
        #expect(WorkoutNotificationStyle.timeSensitive.notificationInterruptionLevel == .timeSensitive)
    }
}
