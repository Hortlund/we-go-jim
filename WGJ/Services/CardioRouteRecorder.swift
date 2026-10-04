import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class CardioRouteRecorder: NSObject, CLLocationManagerDelegate {
    static let shared = CardioRouteRecorder()

    enum GPSState: Equatable {
        case inactive, locating, recording, paused, denied, approximate, unavailable

        var message: String {
            switch self {
            case .inactive: String(localized: "GPS records your distance and route.")
            case .locating: String(localized: "Finding GPS…")
            case .recording: String(localized: "GPS recording · Works with your screen locked")
            case .paused: String(localized: "GPS paused")
            case .denied: String(localized: "Location is off. Add distance when you finish.")
            case .approximate: String(localized: "Precise Location is needed to record your route.")
            case .unavailable: String(localized: "GPS signal unavailable. Recording will resume when it returns.")
            }
        }
    }

    private(set) var route: CardioRoute?
    private(set) var gpsState = GPSState.inactive
    private(set) var persistenceError: String?
    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private let store: CardioRouteStore
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var recordingStartedAt = Date.distantFuture
    @ObservationIgnored private var wantsUpdates = false
    @ObservationIgnored private var maximumSpeedMetersPerSecond: Double = 12
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var lastSavedAt = Date.distantPast
    @ObservationIgnored private var preparationToken = UUID()
    @ObservationIgnored var onProgress: (() -> Void)?

    init(store: CardioRouteStore = .shared, manager: CLLocationManager = CLLocationManager()) {
        self.store = store
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func prepare(sessionID: UUID, activityID: UUID) async throws {
        try Task.checkCancellation()
        if route?.activityID == activityID && route?.sessionID == sessionID { return }
        let token = UUID()
        preparationToken = token
        stopUpdates()
        await flush()
        try Task.checkCancellation()
        guard preparationToken == token else { return }
        let prepared = try await store.prepareRecording(activityID: activityID)
        try Task.checkCancellation()
        let loaded = prepared.route
        let writeGeneration = prepared.generation
        guard preparationToken == token else { return }
        guard loaded == nil || loaded?.sessionID == sessionID else {
            throw CocoaError(.fileReadCorruptFile)
        }
        route = loaded ?? CardioRoute(sessionID: sessionID, activityID: activityID)
        generation = writeGeneration
        gpsState = .inactive
        persistenceError = nil
    }

    /// Reading a completed activity must not take over another activity's GPS.
    func loadSavedRoute(sessionID: UUID, activityID: UUID) async throws -> CardioRoute? {
        if let route, route.activityID == activityID, route.sessionID == sessionID { return route }
        let saved = try await store.load(activityID: activityID)
        guard saved == nil || saved?.sessionID == sessionID else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return saved
    }

    /// Called only at timer/persistence boundaries, never by the display timer.
    func synchronize(with session: ActiveWorkoutRuntimeSession, requestPermission: Bool = true) {
        guard let route else { return }
        guard route.sessionID == session.id else {
            preparationToken = UUID()
            stop()
            return
        }
        guard
              let activity = session.cardioBlocks.first(where: { $0.id == route.activityID }),
              !activity.isCompleted,
              CardioRecordingPolicy.recordsGPS(activity) else {
            stop()
            return
        }
        maximumSpeedMetersPerSecond = CardioRecordingPolicy.maximumSpeedMetersPerSecond(for: activity)
        if activity.timerState == .running {
            if wantsUpdates {
                // Restore waits for existing authorization without prompting.
                // Opening the recorder may now request an expired Allow Once
                // grant without restarting the route or its current segment.
                if requestPermission, manager.authorizationStatus == .notDetermined {
                    startAuthorizedUpdates(requestPermission: true)
                }
                return
            }
            self.route?.beginSegment()
            recordingStartedAt = max(.now, activity.timerSegmentStartedAt ?? .now)
            wantsUpdates = true
            startAuthorizedUpdates(requestPermission: requestPermission)
            save(force: true)
        } else {
            stop()
            if activity.timerState == .paused { gpsState = .paused }
        }
    }

    /// Reload an existing journal independently of location permission. The
    /// caller synchronizes the timer afterward; this read never starts GPS.
    func restoreRoute(sessionID: UUID, activityID: UUID, isCurrent: () -> Bool) async throws {
        guard let saved = try await store.load(activityID: activityID), saved.sessionID == sessionID else { return }
        guard isCurrent() else { return }
        try await prepare(sessionID: sessionID, activityID: activityID)
    }

    func stop(sessionID: UUID) {
        guard route?.sessionID == sessionID else { return }
        stop()
    }

    func includingRecordedDistance(
        in session: ActiveWorkoutRuntimeSession,
        includeCompletedActivities: Bool = false
    ) -> ActiveWorkoutRuntimeSession {
        guard let route, route.sessionID == session.id, route.distanceMeters > 0,
              let index = session.cardioBlocks.firstIndex(where: { $0.id == route.activityID }),
              !session.cardioBlocks[index].isCompleted
                || (includeCompletedActivities && session.cardioBlocks[index].actualDistanceMeters == nil) else { return session }
        var updated = session
        updated.cardioBlocks[index].actualDistanceMeters = route.distanceMeters
        return updated
    }

    func stop() {
        stopUpdates()
        if route?.isRecording == true {
            route?.stop()
            save(force: true)
        }
        if gpsState == .recording || gpsState == .locating { gpsState = .inactive }
    }

    func flush() async {
        save(force: true)
        await pendingSave?.value
    }

    func reset() async throws {
        preparationToken = UUID()
        stop()
        await pendingSave?.value
        route = nil
        generation = nil
        gpsState = .inactive
        persistenceError = nil
        try await store.deleteAll()
    }

    /// The restore changed the file generation already. Dropping this cached
    /// route must not delete the restored files or enqueue a fresh-generation write.
    func invalidateAfterRestore() {
        preparationToken = UUID()
        stopUpdates()
        route = nil
        generation = nil
        gpsState = .inactive
        persistenceError = nil
    }

    func remove(activityID: UUID) async throws {
        if route?.activityID == activityID {
            preparationToken = UUID()
            stop()
            await pendingSave?.value
            route = nil
            generation = nil
        }
        try await store.delete(activityID: activityID)
    }

    func requestPreciseLocation() {
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "OutdoorWorkout") { [weak self] _ in
            Task { @MainActor in self?.startAuthorizedUpdates(requestPermission: false) }
        }
    }

    private func stopUpdates() {
        wantsUpdates = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    private func startAuthorizedUpdates(requestPermission: Bool) {
        guard wantsUpdates else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            gpsState = .locating
            if requestPermission { manager.requestWhenInUseAuthorization() }
        case .denied, .restricted:
            gpsState = .denied
            manager.stopUpdatingLocation()
        case .authorizedAlways, .authorizedWhenInUse:
            guard manager.accuracyAuthorization == .fullAccuracy else {
                gpsState = .approximate
                manager.stopUpdatingLocation()
                return
            }
            gpsState = .locating
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
        @unknown default:
            gpsState = .unavailable
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startAuthorizedUpdates(requestPermission: false)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wantsUpdates, manager.accuracyAuthorization == .fullAccuracy else { return }
        var changed = false
        for location in locations {
            if route?.append(
                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                timestamp: location.timestamp, accuracy: location.horizontalAccuracy,
                now: .now, recordingStartedAt: recordingStartedAt,
                maximumSpeedMetersPerSecond: maximumSpeedMetersPerSecond
            ) == true { changed = true }
        }
        if changed {
            gpsState = .recording
            save(force: false)
        } else if let last = locations.last, last.horizontalAccuracy > 35 || last.horizontalAccuracy < 0 {
            gpsState = .unavailable
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard wantsUpdates else { return }
        gpsState = (error as? CLError)?.code == .denied ? .denied : .unavailable
    }

    private func save(force: Bool) {
        guard let route, let generation,
              force || Date.now.timeIntervalSince(lastSavedAt) >= 5 else { return }
        lastSavedAt = .now
        onProgress?()
        let priorSave = pendingSave
        pendingSave = Task { [weak self, store] in
            await priorSave?.value
            do {
                try await store.save(route, generation: generation)
                self?.persistenceError = nil
            } catch {
                self?.persistenceError = String(localized: "Your route could not be saved. Try again before closing WGJ.")
            }
        }
    }
}
