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
    let exerciseTrendMetric: ProfileExerciseTrendMetric
    let updatedAt: Date

    nonisolated init(config: ProfileWidgetConfig) {
        id = config.id
        kind = config.kind
        isEnabled = config.isEnabled
        sortOrder = config.sortOrder
        selectedCatalogExerciseUUID = config.selectedCatalogExerciseUUID
        selectedExerciseNameSnapshot = config.selectedExerciseNameSnapshot
        exerciseTrendMetric = config.exerciseTrendMetric
        updatedAt = config.updatedAt
    }

    nonisolated init(
        id: UUID,
        kind: ProfileWidgetKind,
        isEnabled: Bool,
        sortOrder: Int,
        selectedCatalogExerciseUUID: String?,
        selectedExerciseNameSnapshot: String?,
        exerciseTrendMetric: ProfileExerciseTrendMetric,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.selectedCatalogExerciseUUID = selectedCatalogExerciseUUID
        self.selectedExerciseNameSnapshot = selectedExerciseNameSnapshot
        self.exerciseTrendMetric = exerciseTrendMetric
        self.updatedAt = updatedAt
    }

    nonisolated func updating(
        kind: ProfileWidgetKind? = nil,
        isEnabled: Bool? = nil,
        sortOrder: Int? = nil,
        selectedCatalogExerciseUUID: String? = nil,
        selectedExerciseNameSnapshot: String? = nil,
        exerciseTrendMetric: ProfileExerciseTrendMetric? = nil,
        updatedAt: Date = .now
    ) -> ProfileWidgetConfigSnapshot {
        ProfileWidgetConfigSnapshot(
            id: id,
            kind: kind ?? self.kind,
            isEnabled: isEnabled ?? self.isEnabled,
            sortOrder: sortOrder ?? self.sortOrder,
            selectedCatalogExerciseUUID: selectedCatalogExerciseUUID ?? self.selectedCatalogExerciseUUID,
            selectedExerciseNameSnapshot: selectedExerciseNameSnapshot ?? self.selectedExerciseNameSnapshot,
            exerciseTrendMetric: exerciseTrendMetric ?? self.exerciseTrendMetric,
            updatedAt: updatedAt
        )
    }
}
