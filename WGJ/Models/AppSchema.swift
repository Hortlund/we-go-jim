import SwiftData

nonisolated enum AppSchema {
    static func makeFull() -> Schema { Schema(versionedSchema: AppSchemaV2.self) }

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
            ExerciseSessionSummary.self,
            CompletedCardioFact.self,
            HistoryProjectionCheckpoint.self,
        ]
    }

    static func makeInMemoryContainer(name: String = "WGJInMemory") throws -> ModelContainer {
        let schema = makeFull()
        let configuration = ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: AppSchemaMigrationPlan.self, configurations: [configuration])
    }
}

nonisolated enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
    static var models: [any PersistentModel.Type] { AppSchema.models }
}

nonisolated enum AppSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self, AppSchemaV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self)] }
}
