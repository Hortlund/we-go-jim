import Foundation
import SwiftData
import SwiftUI

enum AppMainTab: Hashable {
    case profile
    case history
    case startWorkout
    case exercises
    case measure
}

@MainActor
@Observable
final class ActiveWorkoutCoordinator {
    var selectedTab: AppMainTab = .startWorkout
    var activeSessionID: UUID?
    var isActiveWorkoutPresented = false
    var isActiveWorkoutStripCollapsed = false

    func present(sessionID: UUID) {
        activeSessionID = sessionID
        isActiveWorkoutPresented = true
        isActiveWorkoutStripCollapsed = false
    }

    func collapseActiveWorkout() {
        guard activeSessionID != nil else {
            clearActiveWorkout()
            return
        }
        isActiveWorkoutPresented = false
        isActiveWorkoutStripCollapsed = true
    }

    func clearActiveWorkout() {
        activeSessionID = nil
        isActiveWorkoutPresented = false
        isActiveWorkoutStripCollapsed = false
    }

    func restoreActiveSessionIfNeeded(modelContext: ModelContext) {
        let repository = WorkoutSessionRepository(modelContext: modelContext)
        do {
            if let active = try repository.activeSession() {
                activeSessionID = active.id
                isActiveWorkoutStripCollapsed = !isActiveWorkoutPresented
            } else {
                clearActiveWorkout()
            }
        } catch {
            clearActiveWorkout()
        }
    }
}

private struct CloudSyncEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct CloudSyncErrorDescriptionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var cloudSyncEnabled: Bool {
        get { self[CloudSyncEnabledKey.self] }
        set { self[CloudSyncEnabledKey.self] = newValue }
    }

    var cloudSyncErrorDescription: String? {
        get { self[CloudSyncErrorDescriptionKey.self] }
        set { self[CloudSyncErrorDescriptionKey.self] = newValue }
    }
}
