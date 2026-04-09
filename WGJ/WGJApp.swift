import Foundation
import SwiftData
import SwiftUI
import UIKit

@main
struct WGJApp: App {
    private let bootstrap = WGJApp.makeContainerBootstrap()

    init() {
        Self.configureNavigationTitleAppearance()
        RestTimerNotificationManager.shared.configureNotifications()
        CloudSyncEventMonitor.shared.start()
        AppRuntimeState.shared.updateCloudState(
            isEnabled: bootstrap.cloudSyncEnabled,
            errorDescription: bootstrap.cloudSyncErrorDescription
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.cloudSyncEnabled, bootstrap.cloudSyncEnabled)
                .environment(\.cloudSyncErrorDescription, bootstrap.cloudSyncErrorDescription)
                .environment(AppNotificationRouter.shared)
        }
        .modelContainer(bootstrap.container)
    }

    private static func makeContainerBootstrap() -> ModelContainerBootstrap {
        if ProcessInfo.processInfo.arguments.contains("UITEST_IN_MEMORY_STORE") {
            do {
                return ModelContainerBootstrap(
                    container: try makeUITestContainer(),
                    cloudSyncEnabled: false,
                    cloudSyncErrorDescription: "UI test run using an in-memory local container."
                )
            } catch {
                fatalError("Could not create UI test ModelContainer: \(describe(error))")
            }
        }

        let startupDecision = CloudStartupPreflight.makeDecision()
        switch startupDecision.storeMode {
        case .localFallback:
            do {
                return ModelContainerBootstrap(
                    container: try makeLocalFallbackContainer(),
                    cloudSyncEnabled: startupDecision.cloudSyncEnabled,
                    cloudSyncErrorDescription: startupDecision.cloudSyncErrorDescription
                )
            } catch {
                fatalError("Could not create fallback ModelContainer without CloudKit sync: \(describe(error))")
            }
        case .cloudBacked:
            do {
                let container = try makeCloudBackedContainer()
                return ModelContainerBootstrap(
                    container: container,
                    cloudSyncEnabled: startupDecision.cloudSyncEnabled,
                    cloudSyncErrorDescription: startupDecision.cloudSyncErrorDescription
                )
            } catch {
                let cloudError = describe(error)
                let fallbackContainer: ModelContainer

                do {
                    fallbackContainer = try makeLocalFallbackContainer()
                } catch {
                    fatalError("Could not create fallback ModelContainer without CloudKit sync: \(describe(error))")
                }

                #if DEBUG
                print("Cloud-backed ModelContainer unavailable. Falling back to local-only mode. Error: \(cloudError)")
                #endif

                return ModelContainerBootstrap(
                    container: fallbackContainer,
                    cloudSyncEnabled: false,
                    cloudSyncErrorDescription: cloudError
                )
            }
        }
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
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
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
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
        ])

        let activeWorkoutDraftSchema = Schema([
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
        ])

        let socialOutboxSchema = Schema([
            SocialOutboxItem.self,
            BlockedBro.self,
        ])

        let historyProjectionSchema = Schema([
            CompletedSetFact.self,
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

private struct ModelContainerBootstrap {
    let container: ModelContainer
    let cloudSyncEnabled: Bool
    let cloudSyncErrorDescription: String?
}
