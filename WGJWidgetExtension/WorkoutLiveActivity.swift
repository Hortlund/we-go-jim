import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color(red: 0.06, green: 0.10, blue: 0.14))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.workoutURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        WGJWidgetBrandBadge(size: 24)
                        Text("WGJ")
                    }
                        .font(.headline).foregroundStyle(.cyan)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutActivityTimer(state: context.state)
                        .font(.title3.bold()).foregroundStyle(.cyan).frame(maxWidth: 100)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.title).font(.headline).lineLimit(1).privacySensitive()
                        WorkoutActivityDetails(state: context.state, isStale: context.isStale)
                        if context.isStale && context.state.isCardio {
                            Text("Open WGJ for the latest distance").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                WGJWidgetBrandBadge(size: 22)
            } compactTrailing: {
                WorkoutActivityTimer(state: context.state)
                    .font(.caption.monospacedDigit()).frame(width: 58).foregroundStyle(.cyan)
            } minimal: {
                WGJWidgetBrandBadge(size: 22)
            }
            .widgetURL(context.attributes.workoutURL)
            .keylineTint(.cyan)
        }
    }
}

private struct WorkoutLockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                WGJWidgetBrandBadge(size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title).font(.headline).lineLimit(1).privacySensitive()
                    Text(isStale && state.isCardio ? "Open WGJ for the latest distance" : state.status)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                WorkoutActivityTimer(state: state)
                    .font(.title2.bold()).foregroundStyle(.cyan).frame(width: 105, alignment: .trailing)
            }
            WorkoutActivityDetails(state: state, isStale: isStale)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private struct WorkoutActivityTimer: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Group {
            if let start = state.timerStart {
                Text(timerInterval: start...start.addingTimeInterval(24 * 3600), countsDown: false)
            } else {
                Text(durationText(state.elapsedSeconds))
            }
        }
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
    }

    private func durationText(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct WorkoutActivityDetails: View {
    let state: WorkoutActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 20) {
            if state.isCardio {
                metric("Distance", value: state.distance ?? "—")
                metric("Avg. pace", value: state.pace ?? "—")
            } else {
                if let progress = state.progress {
                    Label(progress, systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.medium)).privacySensitive()
                }
                Spacer(minLength: 0)
            }
            if let endsAt = state.restEndsAt {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Next set").font(.caption).foregroundStyle(.secondary)
                    Group {
                        if isStale || endsAt <= Date.now {
                            Text("now")
                        } else {
                            Text(timerInterval: endsAt.addingTimeInterval(-3600)...endsAt,
                                countsDown: true, showsHours: false)
                        }
                    }
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: 170, alignment: .trailing)
                .privacySensitive()
            }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).privacySensitive()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Outdoor walk", as: .content, using: WorkoutActivityAttributes(sessionID: UUID())) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState(title: "Outdoor Walk", symbol: "figure.walk", isCardio: true,
        status: "In progress", timerStart: .now.addingTimeInterval(-1234), elapsedSeconds: 1234,
        distance: "2.34 km", pace: "8:47 /km", progress: nil, restEndsAt: nil)
}

#Preview("Strength workout", as: .content, using: WorkoutActivityAttributes(sessionID: UUID())) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState(title: "Push Day", symbol: "dumbbell.fill", isCardio: false,
        status: "Workout in progress", timerStart: .now.addingTimeInterval(-2200), elapsedSeconds: 0,
        distance: nil, pace: nil, progress: "6/12 sets", restEndsAt: .now.addingTimeInterval(90))
}
