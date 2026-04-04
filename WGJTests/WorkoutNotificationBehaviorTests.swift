import Testing
import UserNotifications
@testable import WGJ

@MainActor
struct WorkoutNotificationBehaviorTests {
    @Test
    func restTimerNotificationsUseDefaultSystemSound() {
        let descriptor = RestTimerNotificationManager.notificationDescriptor(
            exerciseName: "Bench Press",
            setLabel: "Set 3",
            style: .standard
        )

        #expect(descriptor.title == "Rest complete")
        #expect(descriptor.subtitle == "Bench Press")
        #expect(descriptor.body == "Back for Set 3")
        #expect(descriptor.usesDefaultSound)
        #expect(descriptor.interruptionLevel == .active)
    }

    @Test
    func timeSensitiveRestTimerNotificationsKeepTimeSensitiveInterruptionLevel() {
        let descriptor = RestTimerNotificationManager.notificationDescriptor(
            exerciseName: "Incline Press",
            setLabel: "Set 4",
            style: .timeSensitive
        )

        #expect(descriptor.usesDefaultSound)
        #expect(descriptor.interruptionLevel == .timeSensitive)
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
