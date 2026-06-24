import SwiftData
import SwiftUI

nonisolated enum AppMaintenanceTrigger: Equatable, Sendable {
    case enteredMain
    case sceneActivated
    case activeWorkoutEnded
}

nonisolated struct AppDeferredMaintenanceWork: Equatable, Sendable {
    let shouldPrimeCatalog: Bool
    let shouldBackfillHistoryProjection: Bool
    let shouldBackfillSessionSummaries: Bool

    var hasWork: Bool {
        shouldPrimeCatalog
            || shouldBackfillHistoryProjection
            || shouldBackfillSessionSummaries
    }
}

nonisolated enum AppDeferredMaintenancePlanner {
    nonisolated static func plan(
        hasPrimedCatalog: Bool,
        needsHistoryProjectionBackfill: Bool,
        needsSessionSummaryBackfill: Bool
    ) -> AppDeferredMaintenanceWork {
        AppDeferredMaintenanceWork(
            shouldPrimeCatalog: hasPrimedCatalog == false,
            shouldBackfillHistoryProjection: needsHistoryProjectionBackfill,
            shouldBackfillSessionSummaries: needsSessionSummaryBackfill
        )
    }
}

@MainActor
@Observable
final class AppDeferredMaintenanceState {
    private(set) var isPending = true

    func requestRun() {
        isPending = true
    }

    func markCompleted() {
        isPending = false
    }

    func reset() {
        isPending = true
    }
}

nonisolated enum AppMaintenancePolicy {
    static let enteredMainDeferredDelay: Duration = .milliseconds(2_500)

    static func shouldRunResumeCritical(
        appPhase: AppPhase,
        scenePhase: ScenePhase,
        activeSessionID: UUID? = nil
    ) -> Bool {
        appPhase == .main && scenePhase == .active && activeSessionID == nil
    }

    static func shouldScheduleDeferred(
        appPhase: AppPhase,
        scenePhase: ScenePhase,
        activeSessionID: UUID?,
        hasPendingDeferredMaintenance: Bool
    ) -> Bool {
        shouldRunResumeCritical(appPhase: appPhase, scenePhase: scenePhase)
            && activeSessionID == nil
            && hasPendingDeferredMaintenance
    }
}

nonisolated struct ResumeCriticalMaintenanceTracker: Equatable, Sendable {
    private(set) var hasRunThisForegroundCycle = false
    private(set) var isRunning = false
    private var generation = 0
    private(set) var currentRunID: Int?

    mutating func beginRunIfNeeded() -> Int? {
        guard !hasRunThisForegroundCycle, !isRunning else { return nil }

        generation += 1
        hasRunThisForegroundCycle = true
        isRunning = true
        currentRunID = generation
        return currentRunID
    }

    mutating func finishRun(_ runID: Int) {
        guard currentRunID == runID else { return }
        isRunning = false
    }

    mutating func resetForegroundCycle() {
        invalidateInFlightRun()
        hasRunThisForegroundCycle = false
    }

    func isCurrent(_ runID: Int) -> Bool {
        currentRunID == runID
    }

    private mutating func invalidateInFlightRun() {
        generation += 1
        isRunning = false
        currentRunID = nil
    }
}

nonisolated struct AsyncLoadGenerationTracker: Equatable, Sendable {
    private var generation = 0

    mutating func next() -> Int {
        generation += 1
        return generation
    }

    mutating func invalidate() {
        generation += 1
    }

    func isCurrent(_ candidate: Int) -> Bool {
        generation == candidate
    }
}
