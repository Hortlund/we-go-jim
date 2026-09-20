import Foundation
import SwiftData

// Frozen persistence shape shipped at 1360a36. Never edit; add a new schema version.
nonisolated enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
            UserProfile.self,
            UserDataDeletionTombstone.self,
            ProfileWidgetConfig.self,
            CachedCoachNarrative.self,
            CachedCoachFollowUpNarrative.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            TemplateSupersetGroup.self,
            TemplateExerciseDropStage.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            ActiveWorkoutDraftSupersetGroup.self,
            ActiveWorkoutDraftDropStage.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            WorkoutSessionSupersetGroup.self,
            WorkoutSessionDropStage.self,
            CompletedSetFact.self,
        ]
    }

    @Model
    final class ExerciseCatalogItem {
        @Attribute(.unique) var remoteUUID: String
        var remoteID: Int?
        var displayName: String
        var categoryName: String
        var equipmentSummary: String
        var instructionText: String?
        var cardioTrackingProfileRaw: String?
        var isCurated: Bool
        var isHidden: Bool
        var sourceName: String
        var lastUpdateGlobal: Date?
        var updatedAt: Date
        @Relationship(inverse: \MuscleGroup.primaryExercises) var primaryMuscles: [MuscleGroup]
        @Relationship(inverse: \MuscleGroup.secondaryExercises) var secondaryMuscles: [MuscleGroup]
        @Relationship(deleteRule: .cascade, inverse: \ExerciseAlias.exercise) var aliases: [ExerciseAlias]
        @Relationship(deleteRule: .cascade, inverse: \ExerciseImageAsset.exercise) var images: [ExerciseImageAsset]
        @Relationship(deleteRule: .cascade, inverse: \ExerciseAttribution.exercise) var attributions: [ExerciseAttribution]

        init() {
            self.remoteUUID = ""
            self.displayName = ""
            self.categoryName = ""
            self.equipmentSummary = ""
            self.isCurated = false
            self.isHidden = false
            self.sourceName = ""
            self.updatedAt = Date()
            self.primaryMuscles = []
            self.secondaryMuscles = []
            self.aliases = []
            self.images = []
            self.attributions = []
        }
    }

    @Model
    final class MuscleGroup {
        @Attribute(.unique) var remoteID: Int
        var name: String
        var nameEn: String
        @Relationship var primaryExercises: [ExerciseCatalogItem]
        @Relationship var secondaryExercises: [ExerciseCatalogItem]

        init() {
            self.remoteID = 0
            self.name = ""
            self.nameEn = ""
            self.primaryExercises = []
            self.secondaryExercises = []
        }
    }

    @Model
    final class ExerciseImageAsset {
        var remoteImageID: Int?
        var remoteURL: String
        var localPath: String?
        var licenseName: String
        var licenseAuthor: String
        var sourceName: String
        var lastAccessedAt: Date
        var fileSizeBytes: Int
        @Relationship var exercise: ExerciseCatalogItem?

        init() {
            self.remoteURL = ""
            self.licenseName = ""
            self.licenseAuthor = ""
            self.sourceName = ""
            self.lastAccessedAt = Date()
            self.fileSizeBytes = 0
        }
    }

    @Model
    final class ExerciseAlias {
        var value: String
        @Relationship var exercise: ExerciseCatalogItem?

        init() {
            self.value = ""
        }
    }

    @Model
    final class ExerciseAttribution {
        var sourceName: String
        var sourceURL: String
        var licenseName: String
        var licenseURL: String
        var authorName: String
        @Relationship var exercise: ExerciseCatalogItem?

        init() {
            self.sourceName = ""
            self.sourceURL = ""
            self.licenseName = ""
            self.licenseURL = ""
            self.authorName = ""
        }
    }

    @Model
    final class ExerciseCatalogSyncState {
        @Attribute(.unique) var key: String
        var seedVersion: Int
        var seedImportedAt: Date?
        var lastSuccessfulSyncAt: Date?
        var lastUpdateCursor: Date?
        var lastRefreshAttemptAt: Date?
        var lastErrorMessage: String?

        init() {
            self.key = ""
            self.seedVersion = 0
        }
    }

    @Model
    final class UserProfile {
        var id: UUID = UUID()
        var displayName: String = ""
        var athleteTypeRaw: String?
        var avatarImageData: Data?
        var calorieEstimateSexRaw: String?
        var dateOfBirth: Date?
        var heightCentimeters: Double?
        var bodyWeightKilograms: Double?
        var showsCalorieEstimates: Bool = true
        var preferredWeightUnitRaw: String = PreferredWeightUnit.kg.rawValue
        var preferredDistanceUnitRaw: String?
        var workoutNotificationStyleRaw: String = WorkoutNotificationStyle.timeSensitive.rawValue
        var weeklyWorkoutGoal: Int = 4
        var isTrainingGuidanceEnabled: Bool = true
        var keepsScreenAwake: Bool = false
        var automaticallyClosesCompletedExercises: Bool = true
        var isBozarModeEnabled: Bool = false
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init() {

        }
    }

    @Model
    final class UserDataDeletionTombstone {
        var id: UUID = UUID()
        var entityName: String = ""
        var entityID: UUID = UUID()
        var entityKey: String?
        var deletedAt: Date = Date()

        init() {

        }
    }

    @Model
    final class ProfileWidgetConfig {
        var id: UUID = UUID()
        var kindRaw: String = ProfileWidgetKind.prs.rawValue
        var isEnabled: Bool = true
        var selectedCatalogExerciseUUID: String?
        var selectedExerciseNameSnapshot: String?
        var exerciseTrendMetricRaw: String?
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init() {

        }
    }

    @Model
    final class CachedCoachNarrative {
        var id: UUID = UUID()
        @Attribute(.unique) var cacheKey: String = ""
        var sessionID: UUID = UUID()
        var weekStart: Date = Date()
        var revisionKey: String = ""
        var headline: String = ""
        var availabilityModeRaw: String = CoachNarrativeAvailabilityMode.fallback.rawValue
        var body: String = ""
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init() {

        }
    }

    @Model
    final class CachedCoachFollowUpNarrative {
        var id: UUID = UUID()
        @Attribute(.unique) var cacheKey: String = ""
        var sessionID: UUID = UUID()
        var weekStart: Date = Date()
        var revisionKey: String = ""
        var headline: String = ""
        var followUpKindRaw: String = CoachFollowUpKind.whatImproved.rawValue
        var availabilityModeRaw: String = CoachNarrativeAvailabilityMode.fallback.rawValue
        var body: String = ""
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init() {

        }
    }

    @Model
    final class TemplateFolder {
        var id: UUID = UUID()
        var name: String = ""
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship(inverse: \WorkoutTemplate.folder) var templates: [WorkoutTemplate]?

        init() {

        }
    }

    @Model
    final class WorkoutTemplate {
        var id: UUID = UUID()
        var folderID: UUID = UUID()
        var name: String = ""
        var notes: String = ""
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var folder: TemplateFolder?
        @Relationship(inverse: \TemplateExercise.template) var exercises: [TemplateExercise]?
        @Relationship(inverse: \TemplateCardioBlock.template) var cardioBlocks: [TemplateCardioBlock]?
        @Relationship(deleteRule: .cascade, inverse: \TemplateSupersetGroup.template) var supersetGroups: [TemplateSupersetGroup]?

        init() {

        }
    }

    @Model
    final class TemplateCardioBlock {
        var id: UUID = UUID()
        var templateID: UUID = UUID()
        var phaseRaw: String = WorkoutCardioPhase.preWorkout.rawValue
        var roleRaw: String?
        var sortOrder: Int = 0
        var catalogExerciseUUID: String = ""
        var exerciseNameSnapshot: String = ""
        var categorySnapshot: String = ""
        var muscleSummarySnapshot: String = ""
        var trackingProfileRaw: String?
        var goalKindRaw: String?
        var targetDurationSeconds: Int = WorkoutCardioPhase.preWorkout.defaultDurationSeconds
        var targetDistanceMeters: Double?
        var preferredDistanceUnitRaw: String?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var template: WorkoutTemplate?

        init() {

        }
    }

    @Model
    final class TemplateExercise {
        var id: UUID = UUID()
        var templateID: UUID = UUID()
        var catalogExerciseUUID: String = ""
        var exerciseNameSnapshot: String = ""
        var categorySnapshot: String = ""
        var muscleSummarySnapshot: String = ""
        var notes: String = ""
        var targetRepMin: Int?
        var targetRepMax: Int?
        var restSeconds: Int = 120
        var supersetGroupID: UUID?
        var supersetPositionRaw: String?
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var template: WorkoutTemplate?
        @Relationship(deleteRule: .cascade, inverse: \TemplateExerciseSet.templateExercise) var prescribedSets: [TemplateExerciseSet]?
        @Relationship(deleteRule: .cascade, inverse: \TemplateExerciseComponent.templateExercise) var components: [TemplateExerciseComponent]?
        @Relationship var supersetGroup: TemplateSupersetGroup?

        init() {

        }
    }

    @Model
    final class TemplateExerciseComponent {
        var id: UUID = UUID()
        var templateExerciseID: UUID = UUID()
        var catalogExerciseUUID: String = ""
        var exerciseNameSnapshot: String = ""
        var categorySnapshot: String = ""
        var muscleSummarySnapshot: String = ""
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var templateExercise: TemplateExercise?

        init() {

        }
    }

    @Model
    final class TemplateExerciseSet {
        var id: UUID = UUID()
        var templateExerciseID: UUID = UUID()
        var sortOrder: Int = 0
        var targetReps: Int?
        var targetWeight: Double?
        var loadUnitRaw: String = TemplateLoadUnit.kg.rawValue
        var restSeconds: Int = 120
        var isWarmup: Bool = false
        var isLocked: Bool = false
        var previousTargetReps: Int?
        var previousTargetWeight: Double?
        var previousLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var templateExercise: TemplateExercise?
        @Relationship(deleteRule: .cascade, inverse: \TemplateExerciseDropStage.templateExerciseSet) var dropStages: [TemplateExerciseDropStage]?

        init() {

        }
    }

    @Model
    final class TemplateSupersetGroup {
        var id: UUID = UUID()
        var templateID: UUID = UUID()
        var roundRestSeconds: Int = 120
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var template: WorkoutTemplate?
        @Relationship(inverse: \TemplateExercise.supersetGroup) var exercises: [TemplateExercise]?

        init() {

        }
    }

    @Model
    final class TemplateExerciseDropStage {
        var id: UUID = UUID()
        var templateExerciseSetID: UUID = UUID()
        var sortOrder: Int = 0
        var targetReps: Int?
        var targetWeight: Double?
        var loadUnitRaw: String = TemplateLoadUnit.kg.rawValue
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var templateExerciseSet: TemplateExerciseSet?

        init() {

        }
    }

    @Model
    final class ActiveWorkoutDraftSession {
        var id: UUID = UUID()
        var templateID: UUID?
        var name: String = ""
        var startedAt: Date = Date()
        var notes: String = ""
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship(deleteRule: .cascade, inverse: \ActiveWorkoutDraftExercise.session) var exercises: [ActiveWorkoutDraftExercise]?
        @Relationship(deleteRule: .cascade, inverse: \ActiveWorkoutDraftCardioBlock.session) var cardioBlocks: [ActiveWorkoutDraftCardioBlock]?
        @Relationship(deleteRule: .cascade, inverse: \ActiveWorkoutDraftSupersetGroup.session) var supersetGroups: [ActiveWorkoutDraftSupersetGroup]?

        init() {

        }
    }

    @Model
    final class ActiveWorkoutDraftCardioBlock {
        var id: UUID = UUID()
        var sessionID: UUID = UUID()
        var sourceTemplateCardioID: UUID?
        var phaseRaw: String = WorkoutCardioPhase.preWorkout.rawValue
        var roleRaw: String?
        var sortOrder: Int = 0
        var catalogExerciseUUID: String = ""
        var exerciseNameSnapshot: String = ""
        var categorySnapshot: String = ""
        var muscleSummarySnapshot: String = ""
        var trackingProfileRaw: String?
        var goalKindRaw: String?
        var targetDurationSeconds: Int = WorkoutCardioPhase.preWorkout.defaultDurationSeconds
        var targetDistanceMeters: Double?
        var actualDurationSeconds: Int?
        var actualDistanceMeters: Double?
        var preferredDistanceUnitRaw: String?
        var inclinePercent: Double?
        var resistanceLevel: Double?
        var cardioNotes: String = ""
        var timerStateRaw: String?
        var timerSegmentStartedAt: Date?
        var timerAccumulatedSeconds: Int = 0
        var isCompleted: Bool = false
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var session: ActiveWorkoutDraftSession?

        init() {

        }
    }

    @Model
    final class ActiveWorkoutDraftExercise {
        var id: UUID = UUID()
        var sessionID: UUID = UUID()
        var templateExerciseID: UUID?
        var catalogExerciseUUID: String = ""
        var exerciseNameSnapshot: String = ""
        var categorySnapshot: String = ""
        var muscleSummarySnapshot: String = ""
        var notes: String = ""
        var targetRepMin: Int?
        var targetRepMax: Int?
        var restSeconds: Int = 120
        var supersetGroupID: UUID?
        var supersetPositionRaw: String?
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var session: ActiveWorkoutDraftSession?
        @Relationship(deleteRule: .cascade, inverse: \ActiveWorkoutDraftSet.sessionExercise) var sets: [ActiveWorkoutDraftSet]?
        @Relationship(deleteRule: .cascade, inverse: \ActiveWorkoutDraftExerciseComponent.sessionExercise) var components: [ActiveWorkoutDraftExerciseComponent]?
        @Relationship var supersetGroup: ActiveWorkoutDraftSupersetGroup?

        init() {

        }
    }

    @Model
    final class ActiveWorkoutDraftExerciseComponent {
        var id: UUID = UUID()
        var sessionExerciseID: UUID = UUID()
        var catalogExerciseUUID: String = ""
        var exerciseNameSnapshot: String = ""
        var categorySnapshot: String = ""
        var muscleSummarySnapshot: String = ""
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var sessionExercise: ActiveWorkoutDraftExercise?

        init() {

        }
    }

    @Model
    final class ActiveWorkoutDraftSet {
        var id: UUID = UUID()
        var sessionExerciseID: UUID = UUID()
        var sortOrder: Int = 0
        var isWarmup: Bool = false
        var restSeconds: Int = 120
        var targetReps: Int?
        var targetWeight: Double?
        var targetLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
        var actualReps: Int?
        var actualWeight: Double?
        var actualLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
        var isCompleted: Bool = false
        var isLocked: Bool = false
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var sessionExercise: ActiveWorkoutDraftExercise?
        @Relationship(deleteRule: .cascade, inverse: \ActiveWorkoutDraftDropStage.sessionSet) var dropStages: [ActiveWorkoutDraftDropStage]?

        init() {

        }
    }

    @Model
    final class ActiveWorkoutDraftSupersetGroup {
        var id: UUID = UUID()
        var sessionID: UUID = UUID()
        var roundRestSeconds: Int = 120
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var session: ActiveWorkoutDraftSession?
        @Relationship(inverse: \ActiveWorkoutDraftExercise.supersetGroup) var exercises: [ActiveWorkoutDraftExercise]?

        init() {

        }
    }

    @Model
    final class ActiveWorkoutDraftDropStage {
        var id: UUID = UUID()
        var sessionSetID: UUID = UUID()
        var sortOrder: Int = 0
        var targetReps: Int?
        var targetWeight: Double?
        var targetLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
        var actualReps: Int?
        var actualWeight: Double?
        var actualLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
        var isCompleted: Bool = false
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var sessionSet: ActiveWorkoutDraftSet?

        init() {

        }
    }

    @Model
    final class WorkoutSession {
        var id: UUID = UUID()
        var templateID: UUID?
        var name: String = ""
        var statusRaw: String = WorkoutSessionStatus.active.rawValue
        var startedAt: Date = Date()
        var endedAt: Date?
        var durationSeconds: Int = 0
        var totalVolume: Double = 0
        var prHitsCount: Int = 0
        var summaryMetricsVersion: Int = 0
        var estimatedActiveCalories: Int?
        var calorieEstimateVersion: Int?
        var notes: String = ""
        var archivedAt: Date?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionExercise.session) var exercises: [WorkoutSessionExercise]?
        @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionCardioBlock.session) var cardioBlocks: [WorkoutSessionCardioBlock]?
        @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionSupersetGroup.session) var supersetGroups: [WorkoutSessionSupersetGroup]?

        init() {

        }
    }

    @Model
    final class WorkoutSessionCardioBlock {
        var id: UUID = UUID()
        var sessionID: UUID = UUID()
        var sourceTemplateCardioID: UUID?
        var phaseRaw: String = WorkoutCardioPhase.preWorkout.rawValue
        var roleRaw: String?
        var sortOrder: Int = 0
        var catalogExerciseUUID: String = ""
        var exerciseNameSnapshot: String = ""
        var categorySnapshot: String = ""
        var muscleSummarySnapshot: String = ""
        var trackingProfileRaw: String?
        var goalKindRaw: String?
        var targetDurationSeconds: Int = WorkoutCardioPhase.preWorkout.defaultDurationSeconds
        var targetDistanceMeters: Double?
        var actualDurationSeconds: Int?
        var actualDistanceMeters: Double?
        var preferredDistanceUnitRaw: String?
        var inclinePercent: Double?
        var resistanceLevel: Double?
        var cardioNotes: String = ""
        var isCompleted: Bool = false
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var session: WorkoutSession?

        init() {

        }
    }

    @Model
    final class WorkoutSessionExercise {
        var id: UUID = UUID()
        var sessionID: UUID = UUID()
        var templateExerciseID: UUID?
        var catalogExerciseUUID: String = ""
        var exerciseNameSnapshot: String = ""
        var categorySnapshot: String = ""
        var muscleSummarySnapshot: String = ""
        var notes: String = ""
        var targetRepMin: Int?
        var targetRepMax: Int?
        var restSeconds: Int = 120
        var totalSetCount: Int = 0
        var completedSetCount: Int = 0
        var hasDropsets: Bool = false
        var supersetGroupID: UUID?
        var supersetPositionRaw: String?
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var session: WorkoutSession?
        @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionSet.sessionExercise) var sets: [WorkoutSessionSet]?
        @Relationship var supersetGroup: WorkoutSessionSupersetGroup?

        init() {

        }
    }

    @Model
    final class WorkoutSessionSet {
        var id: UUID = UUID()
        var sessionExerciseID: UUID = UUID()
        var sortOrder: Int = 0
        var isWarmup: Bool = false
        var restSeconds: Int = 120
        var targetReps: Int?
        var targetWeight: Double?
        var targetLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
        var actualReps: Int?
        var actualWeight: Double?
        var actualLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
        var isCompleted: Bool = false
        var isLocked: Bool = false
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var sessionExercise: WorkoutSessionExercise?
        @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionDropStage.sessionSet) var dropStages: [WorkoutSessionDropStage]?

        init() {

        }
    }

    @Model
    final class WorkoutSessionSupersetGroup {
        var id: UUID = UUID()
        var sessionID: UUID = UUID()
        var roundRestSeconds: Int = 120
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var session: WorkoutSession?
        @Relationship(inverse: \WorkoutSessionExercise.supersetGroup) var exercises: [WorkoutSessionExercise]?

        init() {

        }
    }

    @Model
    final class WorkoutSessionDropStage {
        var id: UUID = UUID()
        var sessionSetID: UUID = UUID()
        var sortOrder: Int = 0
        var targetReps: Int?
        var targetWeight: Double?
        var targetLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
        var actualReps: Int?
        var actualWeight: Double?
        var actualLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
        var isCompleted: Bool = false
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship var sessionSet: WorkoutSessionSet?

        init() {

        }
    }

    @Model
    final class CompletedSetFact {
        @Attribute(.unique) var sessionSetID: UUID = UUID()
        var sessionID: UUID = UUID()
        var sessionExerciseID: UUID = UUID()
        var templateID: UUID?
        var catalogExerciseUUID: String = ""
        var exerciseNameSnapshot: String = ""
        var completedAt: Date = Date()
        var setIndex: Int = 0
        var isWarmup: Bool = false
        var reps: Int = 0
        var weight: Double?
        var loadUnitRaw: String = TemplateLoadUnit.kg.rawValue
        var normalizedWeightKg: Double?
        var estimatedOneRepMaxKg: Double?
        var volumeKg: Double?
        var sourceSessionUpdatedAt: Date = Date()

        init() {

        }
    }
}
