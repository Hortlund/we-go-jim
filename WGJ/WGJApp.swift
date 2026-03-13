import Foundation
import SwiftData
import SwiftUI
import UIKit

@main
struct WGJApp: App {
    private static let preReleaseStoreResetVersion = 1
    private static let preReleaseStoreResetKey = "wgj.preReleaseStoreResetVersion"

    private let bootstrap = WGJApp.makeContainerBootstrap()

    init() {
        Self.configureNavigationTitleAppearance()
        RestTimerNotificationManager.shared.configureNotifications()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.cloudSyncEnabled, bootstrap.cloudSyncEnabled)
                .environment(\.cloudSyncErrorDescription, bootstrap.cloudSyncErrorDescription)
        }
        .modelContainer(bootstrap.container)
    }

    private static func makeContainerBootstrap() -> ModelContainerBootstrap {
        performPreReleaseStoreResetIfNeeded()

        do {
            let container = try makeCloudBackedContainer()
            return ModelContainerBootstrap(
                container: container,
                cloudSyncEnabled: true,
                cloudSyncErrorDescription: nil
            )
        } catch {
            let cloudError = describe(error)
            let fallbackContainer: ModelContainer

            do {
                fallbackContainer = try makeLocalFallbackContainer()
            } catch {
                do {
                    try resetLocalStores()

                    if let recoveredCloudContainer = try? makeCloudBackedContainer() {
                        return ModelContainerBootstrap(
                            container: recoveredCloudContainer,
                            cloudSyncEnabled: true,
                            cloudSyncErrorDescription: nil
                        )
                    }

                    fallbackContainer = try makeLocalFallbackContainer()
                } catch {
                    fatalError("Could not create fallback ModelContainer after resetting local stores: \(describe(error))")
                }
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

    private static func performPreReleaseStoreResetIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: preReleaseStoreResetKey) < preReleaseStoreResetVersion else {
            return
        }

        try? resetLocalStores()
        defaults.set(preReleaseStoreResetVersion, forKey: preReleaseStoreResetKey)
    }

    private static func makeCloudBackedContainer() throws -> ModelContainer {
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
            TemplateExercise.self,
            TemplateExerciseSet.self,
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
        ])

        let socialOutboxSchema = Schema([
            SocialOutboxItem.self,
        ])

        let appSchema = fullAppSchema()

        let localCatalogConfiguration = ModelConfiguration(
            "LocalCatalog",
            schema: localCatalogSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        let userCloudConfiguration = ModelConfiguration(
            "UserData",
            schema: userDataSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        let socialOutboxConfiguration = ModelConfiguration(
            "SocialOutbox",
            schema: socialOutboxSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: appSchema,
            configurations: [localCatalogConfiguration, userCloudConfiguration, socialOutboxConfiguration]
        )
    }

    private static func makeLocalFallbackContainer() throws -> ModelContainer {
        let appSchema = fullAppSchema()
        let localOnly = ModelConfiguration(
            schema: appSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        return try ModelContainer(for: appSchema, configurations: [localOnly])
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
            TemplateExercise.self,
            TemplateExerciseSet.self,
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            SocialOutboxItem.self,
        ])
    }

    private static func resetLocalStores() throws {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let knownStorePrefixes = [
            "default.store",
            "LocalCatalog.store",
            "UserData.store",
            "SocialOutbox.store",
        ]

        let existingItems = try? fileManager.contentsOfDirectory(
            at: appSupportURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for itemURL in existingItems ?? [] {
            let fileName = itemURL.lastPathComponent
            guard knownStorePrefixes.contains(where: { fileName == $0 || fileName.hasPrefix("\($0)-") }) else {
                continue
            }
            try? fileManager.removeItem(at: itemURL)
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        let userInfo = nsError.userInfo.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        if userInfo.isEmpty {
            return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
        }
        return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription) [\(userInfo)]"
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

private struct ModelContainerBootstrap {
    let container: ModelContainer
    let cloudSyncEnabled: Bool
    let cloudSyncErrorDescription: String?
}
