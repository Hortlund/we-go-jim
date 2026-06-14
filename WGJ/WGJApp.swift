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
        AppLifecycleDiagnostics.shared.start()
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
                            launchBootstrapState.resolveIfNeeded(
                                resolver: {
                                    try await Self.makeContainerBootstrap()
                                },
                                failureFallback: { error in
                                    try Self.makeEmergencyBootstrap(after: error)
                                }
                            )
                        }
                }
            }
        }
    }

    private static func makeContainerBootstrap() async throws -> ModelContainerBootstrap {
        AppStoreLayout.clearPersistentStoreFilesForPendingReset()
        AppStoreLayout.clearObsoleteAppGroupStoreFiles()
#if DEBUG
        try AppStoreLayout.clearPersistentStoreFilesForUITestsIfRequested()
        resetActiveWorkoutSnapshotForUITestsIfRequested()
#endif
        return try await AppLaunchBootstrapResolver.resolve(
            makeUITestContainer: {
                try makeUITestContainer()
            },
            makeLocalFallbackContainer: {
                try makeLocalFallbackContainer()
            },
            makeEmergencyInMemoryContainer: {
                try makeEmergencyInMemoryContainer()
            },
            describeError: { error in
                describe(error)
            }
        )
    }

    private static func makeLocalFallbackContainer() throws -> ModelContainer {
        let appSchema = fullAppSchema()
        try AppStoreLayout.prepareAppGroupStoreDirectory()
        return try ModelContainer(
            for: appSchema,
            configurations: storeConfigurations()
        )
    }

    private static func makeUITestContainer() throws -> ModelContainer {
#if DEBUG
        resetActiveWorkoutSnapshotForUITestsIfRequested()
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

#if DEBUG
    private static func resetActiveWorkoutSnapshotForUITestsIfRequested() {
        if ProcessInfo.processInfo.arguments.contains("UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT") {
            ActiveWorkoutSnapshotStore.deleteDefaultSnapshotFileForUITests()
        }
    }
#endif

    nonisolated private static func makeEmergencyInMemoryContainer() throws -> ModelContainer {
        let appSchema = fullAppSchema()
        return try ModelContainer(
            for: appSchema,
            configurations: [
                ModelConfiguration(
                    "EmergencyLocalOnly",
                    schema: appSchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            ]
        )
    }

    nonisolated private static func makeEmergencyBootstrap(after error: Error) throws -> ModelContainerBootstrap {
        let description = "App storage could not be opened. Keeping WGJ running in temporary local-only mode. \(describe(error))"
        return ModelContainerBootstrap(
            container: try makeEmergencyInMemoryContainer(),
            cloudRuntimeMode: .unavailable(description),
            cloudFeaturesEnabled: false,
            userDataSyncEnabled: false,
            cloudSyncEnabled: false,
            cloudSyncErrorDescription: description
        )
    }

    nonisolated private static func fullAppSchema() -> Schema {
        Schema([
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
        ])
    }

    private static func storeConfigurations() -> [ModelConfiguration] {
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
            UserDataDeletionTombstone.self,
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
                cloudKitDatabase: .none
            ),
            ModelConfiguration(
                AppStoreLayout.activeWorkoutDraftConfigurationName,
                schema: activeWorkoutDraftSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            ),
            ModelConfiguration(
                AppStoreLayout.historyProjectionConfigurationName,
                schema: historyProjectionSchema,
                isStoredInMemoryOnly: false,
                groupContainer: AppStoreLayout.historyProjectionGroupContainer,
                cloudKitDatabase: .none
            ),
        ]
    }

    nonisolated private static func describe(_ error: Error) -> String {
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

nonisolated enum AppStoreLayout {
    static let appGroupIdentifier = WeeklyGoalWidgetStore.appGroupIdentifier
    static let localCatalogConfigurationName = "LocalCatalog"
    static let userDataConfigurationName = "UserData"
    static let activeWorkoutDraftConfigurationName = "ActiveWorkoutDraft"
    static let historyProjectionConfigurationName = "HistoryProjection"
    static let configurationNames = [
        localCatalogConfigurationName,
        userDataConfigurationName,
        activeWorkoutDraftConfigurationName,
        historyProjectionConfigurationName,
    ]
    static let storeFilePrefixes = configurationNames.map { "\($0).store" }
    static let obsoleteAppGroupStoreFilePrefixes = [
        "LocalCatalog.store",
        "UserData.store",
        "ActiveWorkoutDraft.store",
        "UserDataCloudMirror.store",
        "SocialOutbox.store",
    ]
    static let historyProjectionGroupContainer = ModelConfiguration.GroupContainer.identifier(appGroupIdentifier)
    private static let resetPersistentStoresKey = "appStorage.resetPersistentStoresOnNextLaunch"

    static func prepareAppGroupStoreDirectory(fileManager: FileManager = .default) throws {
        guard let supportDirectory = appGroupApplicationSupportDirectory(fileManager: fileManager) else { return }
        try fileManager.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
    }

#if DEBUG
    static func clearPersistentStoreFilesForUITestsIfRequested(
        processInfo: ProcessInfo = .processInfo,
        fileManager: FileManager = .default
    ) throws {
        guard processInfo.arguments.contains("UITEST_CLOUD_RESTORE_WIPE_STORES") else {
            return
        }

        try clearPersistentStoreFiles(fileManager: fileManager)
    }
#endif

    static func requestPersistentStoreResetOnNextLaunch(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: resetPersistentStoresKey)
    }

    static func clearPersistentStoreFilesForPendingReset(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        guard defaults.bool(forKey: resetPersistentStoresKey) else { return }
        try? clearPersistentStoreFiles(fileManager: fileManager)
        clearObsoleteAppGroupStoreFiles(fileManager: fileManager)
        defaults.removeObject(forKey: resetPersistentStoresKey)
    }

    static func persistentStoreDirectories(fileManager: FileManager = .default) -> [URL] {
        var directories = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        if let groupContainerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            directories.append(
                groupContainerURL
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)
            )
        }
        return directories
    }

    static func appGroupApplicationSupportDirectory(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    static func isPersistentStoreFile(_ fileURL: URL) -> Bool {
        storeFilePrefixes.contains { prefix in
            fileURL.lastPathComponent.hasPrefix(prefix)
        }
    }

    static func clearObsoleteAppGroupStoreFiles(fileManager: FileManager = .default) {
        guard let directory = appGroupApplicationSupportDirectory(fileManager: fileManager),
              fileManager.fileExists(atPath: directory.path),
              let fileURLs = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              )
        else { return }

        for fileURL in fileURLs where obsoleteAppGroupStoreFilePrefixes.contains(where: { prefix in
            fileURL.lastPathComponent.hasPrefix(prefix)
        }) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private static func clearPersistentStoreFiles(fileManager: FileManager) throws {
        for directory in persistentStoreDirectories(fileManager: fileManager) {
            guard fileManager.fileExists(atPath: directory.path) else { continue }
            let fileURLs = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            for fileURL in fileURLs where isPersistentStoreFile(fileURL) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}
