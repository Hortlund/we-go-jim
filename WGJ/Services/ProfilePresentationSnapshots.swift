import Foundation
import SwiftData

struct ProfileIdentitySnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let athleteType: ProfileAthleteType?
    let avatarImageData: Data?
    let weeklyWorkoutGoal: Int
    let isTrainingGuidanceEnabled: Bool
    let keepsScreenAwake: Bool
    let isBozarModeEnabled: Bool
    let preferredWeightUnit: PreferredWeightUnit
    let workoutNotificationStyle: WorkoutNotificationStyle
    let updatedAt: Date

    nonisolated init(profile: UserProfile) {
        id = profile.id
        displayName = profile.displayName
        athleteType = profile.athleteType
        avatarImageData = profile.avatarImageData
        weeklyWorkoutGoal = profile.weeklyWorkoutGoal
        isTrainingGuidanceEnabled = profile.isTrainingGuidanceEnabled
        keepsScreenAwake = profile.keepsScreenAwake
        isBozarModeEnabled = profile.isBozarModeEnabled
        preferredWeightUnit = profile.preferredWeightUnit
        workoutNotificationStyle = profile.workoutNotificationStyle
        updatedAt = profile.updatedAt
    }
}

struct ProfileWidgetConfigSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: ProfileWidgetKind
    let isEnabled: Bool
    let sortOrder: Int
    let selectedCatalogExerciseUUID: String?
    let selectedExerciseNameSnapshot: String?
    let updatedAt: Date

    nonisolated init(config: ProfileWidgetConfig) {
        id = config.id
        kind = config.kind
        isEnabled = config.isEnabled
        sortOrder = config.sortOrder
        selectedCatalogExerciseUUID = config.selectedCatalogExerciseUUID
        selectedExerciseNameSnapshot = config.selectedExerciseNameSnapshot
        updatedAt = config.updatedAt
    }
}
