import Foundation

nonisolated enum L10n {
    static var restTimerTitle: String {
        String(localized: "notification.rest.title", defaultValue: "Rest complete")
    }

    static var restTimerBody: String {
        String(localized: "notification.rest.body", defaultValue: "Time for your next set.")
    }

    static var weeklyGoalBeaten: String {
        String(localized: "widget.weekly_goal.beaten", defaultValue: "Goal beaten")
    }

    static var weeklyGoalHit: String {
        String(localized: "widget.weekly_goal.hit", defaultValue: "Goal hit")
    }

    static func weeklyGoalRemaining(_ count: Int) -> String {
        let format = String(
            localized: "widget.weekly_goal.remaining.format",
            defaultValue: "%lld to go",
            comment: "Number of workouts remaining to reach the weekly goal. The placeholder is the count."
        )
        return String.localizedStringWithFormat(format, count)
    }

    static func completedWorkoutCount(_ count: Int) -> String {
        let format = count == 1
            ? String(
                localized: "history.completed.count.singular",
                defaultValue: "%lld completed workout"
            )
            : String(
                localized: "history.completed.count.plural",
                defaultValue: "%lld completed workouts"
            )
        return String.localizedStringWithFormat(
            format,
            count
        )
    }
}
