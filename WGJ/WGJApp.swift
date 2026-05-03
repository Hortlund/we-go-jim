import Foundation
import SwiftData
import SwiftUI
import UIKit

@main
struct WGJApp: App {
    @State private var launchBootstrapState = AppLaunchBootstrapState()

    init() {
        Self.configureNavigationTitleAppearance()
        RestTimerNotificationManager.shared.configureNotifications()
        CloudSyncEventMonitor.shared.start()
        SubscriptionState.shared.configureIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let resolvedBootstrap = launchBootstrapState.resolvedBootstrap {
                    ContentView()
                        .environment(\.cloudSyncEnabled, resolvedBootstrap.bootstrap.cloudSyncEnabled)
                        .environment(\.cloudSyncErrorDescription, resolvedBootstrap.bootstrap.cloudSyncErrorDescription)
                        .environment(\.userDataSyncStatus, AppRuntimeState.shared.userDataSyncStatus)
                        .environment(\.appBackgroundStore, resolvedBootstrap.backgroundStore)
                        .environment(AppNotificationRouter.shared)
                        .modelContainer(resolvedBootstrap.bootstrap.container)
                } else {
                    SplashView()
                        .task {
                            launchBootstrapState.resolveIfNeeded {
                                try await Self.makeContainerBootstrap()
                            }
                        }
                }
            }
        }
    }

    private static func makeContainerBootstrap() async throws -> ModelContainerBootstrap {
        try await AppLaunchBootstrapResolver.resolve(
            makeUITestContainer: {
                try makeUITestContainer()
            },
            makeCloudBackedContainer: {
                try makeCloudBackedContainer()
            },
            makeLocalFallbackContainer: {
                try makeLocalFallbackContainer()
            },
            describeError: { error in
                describe(error)
            }
        )
    }

    private static func makeCloudBackedContainer() throws -> ModelContainer {
        let appSchema = fullAppSchema()
        return try ModelContainer(
            for: appSchema,
            configurations: storeConfigurations(userDataCloudKitDatabase: .automatic)
        )
    }

    private static func makeLocalFallbackContainer() throws -> ModelContainer {
        let appSchema = fullAppSchema()
        return try ModelContainer(
            for: appSchema,
            configurations: storeConfigurations(userDataCloudKitDatabase: .none)
        )
    }

    private static func makeUITestContainer() throws -> ModelContainer {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT") {
            ActiveWorkoutSnapshotStore.deleteDefaultSnapshotFileForUITests()
        }
#endif
        let appSchema = fullAppSchema()
        let inMemory = ModelConfiguration(
            "UITest",
            schema: appSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let container = try ModelContainer(for: appSchema, configurations: [inMemory])
        try seedUITestCatalogIfNeeded(container: container)
        return container
    }

    private static func fullAppSchema() -> Schema {
        Schema([
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
            UserProfile.self,
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
            SocialOutboxItem.self,
            BlockedBro.self,
        ])
    }

    private static func storeConfigurations(
        userDataCloudKitDatabase: ModelConfiguration.CloudKitDatabase
    ) -> [ModelConfiguration] {
        let localCatalogSchema = Schema([
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
        ])

        let userDataSchema = Schema([
            UserProfile.self,
            ProfileWidgetConfig.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            TemplateSupersetGroup.self,
            TemplateExerciseDropStage.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            WorkoutSessionSupersetGroup.self,
            WorkoutSessionDropStage.self,
        ])

        let activeWorkoutDraftSchema = Schema([
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            ActiveWorkoutDraftSupersetGroup.self,
            ActiveWorkoutDraftDropStage.self,
        ])

        let socialOutboxSchema = Schema([
            SocialOutboxItem.self,
            BlockedBro.self,
        ])

        let historyProjectionSchema = Schema([
            CompletedSetFact.self,
            CachedCoachNarrative.self,
            CachedCoachFollowUpNarrative.self,
        ])

        return [
            ModelConfiguration(
                AppStoreLayout.localCatalogConfigurationName,
                schema: localCatalogSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            ),
            ModelConfiguration(
                AppStoreLayout.userDataConfigurationName,
                schema: userDataSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: userDataCloudKitDatabase
            ),
            ModelConfiguration(
                AppStoreLayout.activeWorkoutDraftConfigurationName,
                schema: activeWorkoutDraftSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            ),
            ModelConfiguration(
                AppStoreLayout.socialOutboxConfigurationName,
                schema: socialOutboxSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            ),
            ModelConfiguration(
                AppStoreLayout.historyProjectionConfigurationName,
                schema: historyProjectionSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            ),
        ]
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        let userInfo = nsError.userInfo.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        if userInfo.isEmpty {
            return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
        }
        return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription) [\(userInfo)]"
    }

    private static func seedUITestCatalogIfNeeded(container: ModelContainer) throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ExerciseCatalogItem>()
        descriptor.fetchLimit = 1

        if try context.fetch(descriptor).isEmpty == false {
            return
        }

        let bench = ExerciseCatalogItem(
            remoteUUID: "ui-test-bench",
            displayName: "Bench Press",
            categoryName: "Strength",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "ui-test"
        )
        context.insert(bench)
        try context.save()
        ExerciseSearchService.invalidateCatalogIndex(for: context)
    }

    private static func configureNavigationTitleAppearance() {
        let titleColor = UIColor(red: 243.0 / 255.0, green: 246.0 / 255.0, blue: 255.0 / 255.0, alpha: 1.0)
        let accentColor = UIColor(red: 75.0 / 255.0, green: 172.0 / 255.0, blue: 255.0 / 255.0, alpha: 1.0)

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.titleTextAttributes = [.foregroundColor: titleColor]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: titleColor]

        let barAppearance = UINavigationBar.appearance()
        barAppearance.standardAppearance = navAppearance
        barAppearance.scrollEdgeAppearance = navAppearance
        barAppearance.compactAppearance = navAppearance
        barAppearance.tintColor = accentColor
    }
}

enum AppStoreLayout {
    static let localCatalogConfigurationName = "LocalCatalog"
    static let userDataConfigurationName = "UserData"
    static let activeWorkoutDraftConfigurationName = "ActiveWorkoutDraft"
    static let socialOutboxConfigurationName = "SocialOutbox"
    static let historyProjectionConfigurationName = "HistoryProjection"
    static let configurationNames = [
        localCatalogConfigurationName,
        userDataConfigurationName,
        activeWorkoutDraftConfigurationName,
        socialOutboxConfigurationName,
        historyProjectionConfigurationName,
    ]
    static let storeFilePrefixes = configurationNames.map { "\($0).store" }
}

enum AppBootstrapRecoveryPolicy {
    static let preservesExistingStoresOnCloudFailure = true
}
