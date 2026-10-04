import Foundation
import Observation

@MainActor
@Observable
final class CardioRecordingController {
    let activityID: UUID
    let coordinator: ActiveWorkoutCoordinator
    let recorder: CardioRouteRecorder
    private(set) var errorMessage: String?
    private(set) var isPreparing = false
    private var completedRoute: CardioRoute?

    init(activityID: UUID, coordinator: ActiveWorkoutCoordinator, recorder: CardioRouteRecorder = .shared) {
        self.activityID = activityID
        self.coordinator = coordinator
        self.recorder = recorder
    }

    var activity: ActiveWorkoutRuntimeCardioBlock? {
        coordinator.storedSnapshot?.session.cardioBlocks.first { $0.id == activityID }
    }

    var route: CardioRoute? {
        if activity?.isCompleted == true, let completedRoute { return completedRoute }
        return recorder.route?.activityID == activityID ? recorder.route : nil
    }

    /// Saved results can contain a manual correction. Only describe the current
    /// value as GPS distance when it still matches this activity's route journal.
    var recordedDistanceForResultReview: Double? {
        guard let activity, activity.isCompleted, CardioRecordingPolicy.recordsGPS(activity),
              let route, route.sessionID == coordinator.storedSnapshot?.session.id,
              route.activityID == activityID, route.distanceMeters.isFinite, route.distanceMeters > 0,
              activity.actualDistanceMeters == route.distanceMeters else { return nil }
        return route.distanceMeters
    }

    var canSaveWorkout: Bool {
        guard let session = coordinator.storedSnapshot?.session else { return false }
        return session.exercises.isEmpty && !session.cardioBlocks.isEmpty
            && session.cardioBlocks.allSatisfy(\.isCompleted)
    }

    func prepare() async {
        guard !Task.isCancelled, let snapshot = coordinator.storedSnapshot, let activity,
              CardioRecordingPolicy.recordsGPS(activity) else { return }
        if activity.isCompleted {
            isPreparing = true
            defer { isPreparing = false }
            do {
                let saved = try await recorder.loadSavedRoute(sessionID: snapshot.session.id, activityID: activityID)
                guard !Task.isCancelled, coordinator.storedSnapshot?.session.id == snapshot.session.id,
                      self.activity?.isCompleted == true else { return }
                completedRoute = saved
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = String(localized: "Your saved route could not be opened. Please try again.")
            }
            return
        }
        completedRoute = nil
        if snapshot.session.cardioBlocks.contains(where: { $0.id != activityID && $0.timerState == .running }) {
            errorMessage = String(localized: "Pause or finish your other cardio activity first.")
            return
        }
        isPreparing = true
        defer { isPreparing = false }
        do {
            try await recorder.prepare(sessionID: snapshot.session.id, activityID: activityID)
            guard !Task.isCancelled, let current = coordinator.storedSnapshot?.session,
                  current.id == snapshot.session.id else { return }
            recorder.synchronize(with: current)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = String(localized: "Your saved route could not be opened. Please try again.")
        }
    }

    func startOrResume() async {
        guard !Task.isCancelled else { return }
        let sessionID = coordinator.storedSnapshot?.session.id
        errorMessage = nil
        await prepare()
        guard !Task.isCancelled, errorMessage == nil,
              coordinator.storedSnapshot?.session.id == sessionID else { return }
        transition { activityID, blocks, date in
            if blocks.first(where: { $0.id == activityID })?.timerState == .paused {
                try WorkoutCardioTimerCoordinator.resume(activityID: activityID, blocks: &blocks, at: date)
            } else {
                try WorkoutCardioTimerCoordinator.start(activityID: activityID, blocks: &blocks, at: date)
            }
        }
        await coordinator.flushSnapshot()
    }

    func pause() async {
        transition(WorkoutCardioTimerCoordinator.pause)
        await recorder.flush()
        await coordinator.flushSnapshot()
    }

    @discardableResult
    func finish() async -> Bool {
        transition { activityID, blocks, date in
            if let index = blocks.firstIndex(where: { $0.id == activityID }),
               let route, route.distanceMeters > 0 {
                blocks[index].actualDistanceMeters = route.distanceMeters
            }
            try WorkoutCardioTimerCoordinator.finish(activityID: activityID, blocks: &blocks, at: date)
        }
        await recorder.flush()
        await coordinator.flushSnapshot()
        return activity?.isCompleted == true
    }

    private func transition(
        _ apply: (UUID, inout [ActiveWorkoutRuntimeCardioBlock], Date) throws -> Void
    ) {
        errorMessage = nil
        guard var snapshot = coordinator.storedSnapshot else { return }
        do {
            let now = Date.now
            try apply(activityID, &snapshot.session.cardioBlocks, now)
            if let index = snapshot.session.cardioBlocks.firstIndex(where: { $0.id == activityID }) {
                snapshot.session.cardioBlocks[index].updatedAt = now
            }
            snapshot.session.touch(date: now)
            coordinator.send(.synchronize(
                session: snapshot.session, restTimer: snapshot.restTimer,
                presentationMode: snapshot.presentationMode ?? .presented, scrollTarget: snapshot.scrollTarget,
                expandedExerciseIDs: snapshot.expandedExerciseIDs
            ))
            recorder.synchronize(with: snapshot.session)
        } catch WorkoutCardioTimerError.anotherActivityRunning {
            errorMessage = String(localized: "Pause or finish your other cardio activity first.")
        } catch {
            errorMessage = String(localized: "This activity could not be updated. Please try again.")
        }
    }
}
