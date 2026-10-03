import ActivityKit
import OSLog
import Observation
import UIKit

@MainActor
protocol WorkoutLiveActivityPublishing: AnyObject {
    func synchronize(snapshot: ActiveWorkoutStoredSnapshot?, route: CardioRoute?)
}

@MainActor
protocol WorkoutLiveActivityClient {
    var isEnabled: Bool { get }
    var records: [WorkoutLiveActivityRecord] { get }
    func start(_ projection: WorkoutLiveActivityProjection) throws
    func update(id: String, state: WorkoutActivityAttributes.ContentState) async
    func end(id: String) async
}

nonisolated struct WorkoutLiveActivityRecord {
    let id: String
    let sessionID: UUID
    let state: WorkoutActivityAttributes.ContentState
    var isActive = true
}

/// A best-effort system presentation. It never saves or changes the workout.
@MainActor
@Observable
final class WorkoutLiveActivityPublisher: WorkoutLiveActivityPublishing {
    nonisolated deinit { }
    static let shared = WorkoutLiveActivityPublisher(
        defaults: AppRuntimeConfig.isRunningTests ? nil : .standard,
        initiallyEnabled: AppRuntimeConfig.isRunningTests
            ? ProcessInfo.processInfo.arguments.contains("UITEST_ENABLE_LIVE_ACTIVITIES") : nil
    )
    private(set) var isEnabled: Bool
    private let client: any WorkoutLiveActivityClient
    private let defaults: UserDefaults?
    private let canStart: () -> Bool
    @ObservationIgnored private var lastStartedSession: UUID?
    @ObservationIgnored private var desired: WorkoutLiveActivityProjection?
    @ObservationIgnored private var latestProjection: WorkoutLiveActivityProjection?
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var worker: Task<Void, Never>?
    private static let lastStartedKey = "workoutLiveActivity.lastStartedSession"
    private static let enabledKey = "workoutLiveActivity.isEnabled"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WGJ", category: "WorkoutLiveActivity")

    init(client: any WorkoutLiveActivityClient = SystemWorkoutLiveActivityClient(), defaults: UserDefaults? = .standard,
         canStart: @escaping () -> Bool = { UIApplication.shared.applicationState == .active },
         initiallyEnabled: Bool? = nil) {
        self.client = client
        self.defaults = defaults
        self.canStart = canStart
        isEnabled = initiallyEnabled ?? defaults?.bool(forKey: Self.enabledKey) ?? false
        lastStartedSession = defaults?.string(forKey: Self.lastStartedKey).flatMap(UUID.init(uuidString:))
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        defaults?.set(enabled, forKey: Self.enabledKey)
        // A deliberate preference change resets dismissal for this session.
        lastStartedSession = nil
        defaults?.removeObject(forKey: Self.lastStartedKey)
        desired = enabled ? latestProjection : nil
        enqueueUpdate()
    }

    func synchronize(snapshot: ActiveWorkoutStoredSnapshot?, route: CardioRoute?) {
        // Adding cardio to an empty workout changes its screen, not its identity.
        // Keep an existing Live Activity through that ready-to-start transition.
        latestProjection = WorkoutLiveActivityProjection.make(snapshot: snapshot, route: route,
            includesReadyCardio: snapshot?.session.id == lastStartedSession)
        desired = isEnabled ? latestProjection : nil
        enqueueUpdate()
    }

    private func enqueueUpdate() {
        revision &+= 1
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            var handled: UInt64
            repeat {
                handled = revision
                await apply(desired, revision: handled)
            } while handled != revision
            worker = nil
        }
    }

    func waitForPendingUpdates() async { await worker?.value }

    private func apply(_ projection: WorkoutLiveActivityProjection?, revision expected: UInt64) async {
        let records = client.records
        if let projection, records.contains(where: { $0.sessionID == projection.sessionID }) {
            rememberStarted(projection.sessionID)
        }
        let matching = records.first { $0.sessionID == projection?.sessionID && $0.isActive }
        // Recover system activities after launch and remove those with no active draft.
        for record in records where record.id != matching?.id {
            await client.end(id: record.id)
        }
        guard expected == revision, let projection else { return }
        if let matching {
            rememberStarted(projection.sessionID)
            if matching.state != projection.state { await client.update(id: matching.id, state: projection.state) }
        } else if client.isEnabled, canStart(), lastStartedSession != projection.sessionID {
            do {
                try client.start(projection)
                rememberStarted(projection.sessionID)
            } catch {
                Self.logger.debug("Live Activity unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }
        // A dismissed or expired activity stays dismissed for this session.
    }

    private func rememberStarted(_ sessionID: UUID) {
        guard lastStartedSession != sessionID else { return }
        lastStartedSession = sessionID
        defaults?.set(sessionID.uuidString, forKey: Self.lastStartedKey)
    }
}

@MainActor
private struct SystemWorkoutLiveActivityClient: WorkoutLiveActivityClient {
    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var records: [WorkoutLiveActivityRecord] {
        Activity<WorkoutActivityAttributes>.activities
            .map { .init(id: $0.id, sessionID: $0.attributes.sessionID, state: $0.content.state,
                isActive: $0.activityState == .active || $0.activityState == .stale) }
    }
    func start(_ projection: WorkoutLiveActivityProjection) throws {
        _ = try Activity.request(attributes: WorkoutActivityAttributes(sessionID: projection.sessionID),
            content: Self.content(projection.state), pushType: nil)
    }
    func update(id: String, state: WorkoutActivityAttributes.ContentState) async {
        await Self.updateActivity(id: id, state: state)
    }
    func end(id: String) async {
        await Self.endActivity(id: id)
    }
    @concurrent
    private static func updateActivity(id: String, state: WorkoutActivityAttributes.ContentState) async {
        let activity = Activity<WorkoutActivityAttributes>.activities.first { $0.id == id }
        await activity?.update(content(state))
    }
    @concurrent
    private static func endActivity(id: String) async {
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
    }
    nonisolated private static func content(_ state: WorkoutActivityAttributes.ContentState) -> ActivityContent<WorkoutActivityAttributes.ContentState> {
        // Timers render themselves; a distance readout needs a recent GPS update.
        let staleDate = state.restEndsAt ?? (state.isCardio && state.timerStart != nil && state.distance != nil
            ? Date.now.addingTimeInterval(60) : nil)
        return ActivityContent(state: state, staleDate: staleDate)
    }
}
