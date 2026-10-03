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
                if AppRuntimeState.shared.requiresStorageRecovery {
                    ContentUnavailableView("Restart WGJ", systemImage: "externaldrive.badge.exclamationmark",
                        description: Text("Restore could not finish. Close and reopen WGJ to recover your previous local data before continuing."))
                } else if let resolvedBootstrap = launchBootstrapState.resolvedBootstrap {
                    switch resolvedBootstrap.bootstrap.persistenceMode {
                    case .durable:
                        ContentView()
                            .environment(\.appPersistenceMode, resolvedBootstrap.bootstrap.persistenceMode)
                            .environment(\.cloudSyncEnabled, resolvedBootstrap.bootstrap.cloudSyncEnabled)
                            .environment(\.cloudSyncErrorDescription, resolvedBootstrap.bootstrap.cloudSyncErrorDescription)
                            .environment(\.userDataSyncStatus, AppRuntimeState.shared.userDataSyncStatus)
                            .environment(\.appBackgroundStore, resolvedBootstrap.backgroundStore)
                            .environment(AppNotificationRouter.shared)
                            .environment(resolvedBootstrap.activeWorkoutCoordinator)
                            .modelContainer(resolvedBootstrap.bootstrap.container)
                    case .volatileDiagnostic(let reason):
                        AppStorageDiagnosticModeView(
                            reason: reason,
                            onRetry: retryDurableStorage
                        )
                    }
                } else if let recoveryState = launchBootstrapState.recoveryState {
                    AppStorageRecoveryView(
                        state: recoveryState,
                        onRetry: retryDurableStorage,
                        onEnterDiagnosticMode: enterDiagnosticMode
                    )
                } else {
                    SplashView()
                        .task {
                            launchBootstrapState.resolveIfNeeded(
                                resolver: {
                                    try await Self.makeContainerBootstrap()
                                }
                            )
                        }
                }
            }
            .task {
                _ = await AppDataArtifactCleanupQueue.shared.retryPending()
            }
        }
    }

    nonisolated private static func makeContainerBootstrap() async throws -> ModelContainerBootstrap {
        try AppStoreLayout.clearPersistentStoreFilesForPendingReset()
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
            describeError: { error in
                describe(error)
            }
        )
    }

    nonisolated private static func makeLocalFallbackContainer() throws -> ModelContainer {
        let appSchema = AppSchema.makeFull()
        try AppStoreLayout.prepareAppGroupStoreDirectory()
        let configurations = storeConfigurations()
        try PersistentRestoreRecovery.recoverIfNeeded(configurations: configurations)
        let container = try ModelContainer(
            for: appSchema,
            migrationPlan: AppSchemaMigrationPlan.self,
            configurations: configurations
        )
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("DEV_SEED_DEMO_DATA") {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            try DemoSeedService(modelContext: context).seedDemoDataIfEmpty()
        }
#endif
        return container
    }

    nonisolated private static func makeUITestContainer() throws -> ModelContainer {
#if DEBUG
        resetActiveWorkoutSnapshotForUITestsIfRequested()
#endif
        let appSchema = AppSchema.makeFull()
        let inMemory = ModelConfiguration(
            "UITest",
            schema: appSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let container = try ModelContainer(for: appSchema, configurations: [inMemory])
        try seedUITestCatalogIfNeeded(container: container)
        try seedUITestExerciseProgressIfRequested(container: container)
        try seedUITestProfileBodyweightIfRequested(container: container)
        try seedUITestHistoryMainCardioIfRequested(container: container)
#if DEBUG
        try seedUITestCardioRouteIfRequested(container: container)
#endif
#if DEBUG
        if let value = ProcessInfo.processInfo.environment["UITEST_BIRTHDAY_PROFILE_ID"],
           let profileID = UUID(uuidString: value) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
            profile.id = profileID
            profile.displayName = "Andreas"
            profile.dateOfBirth = BirthdayCelebrationPolicy.localCalendar.date(byAdding: .year, value: -30, to: .now)
            try context.saveWithRecoveryProtection()
        }
        if ProcessInfo.processInfo.arguments.contains("UITEST_SEED_TEMPLATE_REVIEW") {
            let context = ModelContext(container)
            let template = WorkoutTemplate(
                folderID: TemplateRepository.unfiledFolderID,
                name: "Review Fixture"
            )
            let exercise = TemplateExercise(
                templateID: template.id,
                catalogExerciseUUID: "ui-test-bench",
                exerciseNameSnapshot: "Bench Press",
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Chest",
                template: template
            )
            exercise.prescribedSets = [TemplateExerciseSet(
                templateExerciseID: exercise.id,
                sortOrder: 0,
                templateExercise: exercise
            )]
            if ProcessInfo.processInfo.arguments.contains("UITEST_TEMPLATE_PREVIOUS_MULTIPLE") {
                exercise.prescribedSets = (0..<3).map { index in
                    TemplateExerciseSet(templateExerciseID: exercise.id, sortOrder: index,
                        isWarmup: index == 0, templateExercise: exercise)
                }
            }
            template.exercises = [exercise]
            context.insert(template)
            if ProcessInfo.processInfo.arguments.contains("UITEST_SEED_TEMPLATE_PREVIOUS") {
                let alternateOnly = ProcessInfo.processInfo.arguments.contains("UITEST_TEMPLATE_PREVIOUS_ALTERNATE_ONLY")
                for index in 0..<3 {
                    if index == 0 && alternateOnly { continue }
                    let startedAt = Date().addingTimeInterval(Double(index - 4) * 3600)
                    let previous = WorkoutSession(templateID: index == 1 ? UUID() : template.id,
                        name: index == 1 ? "Other Workout" : "Review Fixture", status: .completed,
                        startedAt: startedAt, endedAt: startedAt.addingTimeInterval(600))
                    let previousExercise = WorkoutSessionExercise(sessionID: previous.id,
                        templateExerciseID: index == 1 ? nil : exercise.id, catalogExerciseUUID: "ui-test-bench",
                        exerciseNameSnapshot: "Bench Press", categorySnapshot: "Strength",
                        muscleSummarySnapshot: "Chest", session: previous)
                    context.insert(previous)
                    context.insert(previousExercise)
                    if index != 2 && ProcessInfo.processInfo.arguments.contains("UITEST_TEMPLATE_PREVIOUS_MULTIPLE") {
                        context.insert(WorkoutSessionSet(sessionExerciseID: previousExercise.id,
                            sortOrder: -1, isWarmup: true, actualReps: 12, actualWeight: 13,
                            isCompleted: true, sessionExercise: previousExercise))
                        context.insert(WorkoutSessionSet(sessionExerciseID: previousExercise.id,
                            sortOrder: 1, actualReps: 12, actualWeight: 12,
                            isCompleted: true, sessionExercise: previousExercise))
                    }
                    if index != 2 && ProcessInfo.processInfo.arguments.contains("UITEST_TEMPLATE_PREVIOUS_WARMUP") {
                        context.insert(WorkoutSessionSet(sessionExerciseID: previousExercise.id,
                            sortOrder: -1, isWarmup: true, actualReps: 10, actualWeight: index == 0 ? 20 : 30,
                            isCompleted: true, sessionExercise: previousExercise))
                    }
                    context.insert(WorkoutSessionSet(sessionExerciseID: previousExercise.id,
                        actualReps: index == 2 ? nil : 8, actualWeight: index == 2 ? nil : (index == 0 ? 50 : 80),
                        isCompleted: index != 2, sessionExercise: previousExercise))
                }
            }
            try context.saveWithRecoveryProtection()
        }
        if ProcessInfo.processInfo.arguments.contains("UITEST_SEED_TEMPLATE_LIBRARY") {
            let context = ModelContext(container)
            for index in 1...16 {
                context.insert(WorkoutTemplate(
                    folderID: TemplateRepository.unfiledFolderID,
                    name: String(format: "Library Plan %02d", index),
                    sortOrder: index
                ))
            }
            try context.saveWithRecoveryProtection()
        }
#endif
        return container
    }

#if DEBUG
    nonisolated private static func resetActiveWorkoutSnapshotForUITestsIfRequested() {
        if ProcessInfo.processInfo.arguments.contains("UITEST_RESET_GYM_EASTER_EGGS") {
            UserDefaults.standard.removeObject(forKey: GymEasterEggPolicy.unlockedKey)
            UserDefaults.standard.removeObject(forKey: GymEasterEggPolicy.enabledKey)
        }
        if ProcessInfo.processInfo.arguments.contains("UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT") {
            ActiveWorkoutSnapshotStore.deleteDefaultSnapshotFileForUITests()
        }
    }
#endif

    nonisolated private static func makeEmergencyInMemoryContainer() throws -> ModelContainer {
        let appSchema = AppSchema.makeFull()
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

    nonisolated private static func makeEmergencyBootstrap(reason: String) throws -> ModelContainerBootstrap {
        let description = "Temporary diagnostics — changes cannot be saved. \(reason)"
        return ModelContainerBootstrap(
            container: try makeEmergencyInMemoryContainer(),
            cloudRuntimeMode: .unavailable(description),
            cloudFeaturesEnabled: false,
            userDataSyncEnabled: false,
            cloudSyncEnabled: false,
            cloudSyncErrorDescription: description,
            persistenceMode: .volatileDiagnostic(reason: description)
        )
    }

    private func retryDurableStorage() {
        launchBootstrapState.retry {
            try await Self.makeContainerBootstrap()
        }
    }

    private func enterDiagnosticMode() {
        launchBootstrapState.enterDiagnosticMode { reason in
            try Self.makeEmergencyBootstrap(reason: reason)
        }
    }

    nonisolated private static func storeConfigurations() -> [ModelConfiguration] {
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
            ExerciseSessionSummary.self,
            CompletedCardioFact.self,
            HistoryProjectionCheckpoint.self,
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

    nonisolated private static func seedUITestCatalogIfNeeded(container: ModelContainer) throws {
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
            // Keep the fixture when the bundled catalog replaces seed exercises.
            sourceName: "custom"
        )
        context.insert(bench)
        try context.saveWithRecoveryProtection()
    }

    nonisolated private static func seedUITestProfileBodyweightIfRequested(container: ModelContainer) throws {
        guard ProcessInfo.processInfo.arguments.contains("UITEST_SEED_PROFILE_BODYWEIGHT") else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(ExerciseCatalogItem(remoteUUID: "fixture-pull-up", displayName: "Pull-Up", equipmentSummary: "Pull-up bar", sourceName: "custom"))
        for index in 0..<2 {
            let date = Date().addingTimeInterval(Double(index - 2) * 86_400)
            let session = WorkoutSession(name: "Pull-Up Fixture", status: .completed, endedAt: date)
            let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: "fixture-pull-up",
                exerciseNameSnapshot: "Pull-Up", categorySnapshot: "Back", muscleSummarySnapshot: "Back", session: session)
            let set = WorkoutSessionSet(sessionExerciseID: exercise.id, actualReps: 8 + index * 2,
                actualWeight: index == 0 ? nil : 0, actualLoadUnit: .kg, isCompleted: true, sessionExercise: exercise)
            context.insert(session)
            context.insert(exercise)
            context.insert(set)
        }
        try context.saveWithRecoveryProtection()
        HistoryAnalyticsCache.shared.invalidate(container: container)
    }

    nonisolated private static func seedUITestExerciseProgressIfRequested(container: ModelContainer) throws {
        guard ProcessInfo.processInfo.arguments.contains("UITEST_SEED_EXERCISE_PROGRESS") else { return }

        let mixedLoad = ProcessInfo.processInfo.arguments.contains("UITEST_MIXED_LOAD_PROGRESS")
        let assisted = ProcessInfo.processInfo.arguments.contains("UITEST_ASSISTED_PROGRESS")
        let exerciseUUID = assisted ? "seed-assisted-pull-up" : mixedLoad ? "seed-pull-up" : "seed-bench-press"
        let exerciseName = assisted ? "Assisted Pull Up" : mixedLoad ? "Pull-Up" : "Barbell Bench Press"
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let completedDates = [
            calendar.date(byAdding: .month, value: -8, to: now)!,
            calendar.date(byAdding: .month, value: -4, to: now)!,
            calendar.date(byAdding: .day, value: -7, to: now)!,
        ]
        let sessionIDs = [
            UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
        ]

        for index in completedDates.indices {
            let completedAt = completedDates[index]
            let sessionID = sessionIDs[index]
            let session = WorkoutSession(
                id: sessionID,
                name: "Progress Fixture \(index + 1)",
                status: .completed,
                startedAt: completedAt.addingTimeInterval(-3_600),
                endedAt: completedAt,
                durationSeconds: 3_600,
                totalVolume: Double(1_000 + index * 250),
                summaryMetricsVersion: WorkoutMetricsService.currentSummaryMetricsVersion,
                createdAt: completedAt,
                updatedAt: completedAt
            )
            let exerciseID = UUID()
            let exercise = WorkoutSessionExercise(
                id: exerciseID,
                sessionID: sessionID,
                catalogExerciseUUID: exerciseUUID,
                exerciseNameSnapshot: exerciseName,
                categorySnapshot: "Chest",
                muscleSummarySnapshot: "Chest",
                totalSetCount: 2,
                completedSetCount: 2,
                createdAt: completedAt,
                updatedAt: completedAt,
                session: session
            )
            var sets: [WorkoutSessionSet] = []

            for setIndex in 0..<2 {
                let weight = assisted ? Double(40 - index * 10) : mixedLoad ? Double(index * 5) : Double(70 + index * 10 + setIndex * 5)
                let reps = assisted ? 10 - index * 2 - setIndex : mixedLoad ? 10 - index * 2 - setIndex : 8 + index + setIndex
                let setID = UUID()
                let set = WorkoutSessionSet(
                    id: setID,
                    sessionExerciseID: exerciseID,
                    sortOrder: setIndex,
                    actualReps: reps,
                    actualWeight: weight,
                    actualLoadUnit: .kg,
                    isCompleted: true,
                    createdAt: completedAt,
                    updatedAt: completedAt,
                    sessionExercise: exercise
                )
                sets.append(set)
                context.insert(CompletedSetFact(
                    sessionSetID: setID,
                    sessionID: sessionID,
                    sessionExerciseID: exerciseID,
                    catalogExerciseUUID: exerciseUUID,
                    exerciseNameSnapshot: exerciseName,
                    completedAt: completedAt,
                    setIndex: setIndex,
                    isWarmup: false,
                    reps: reps,
                    weight: weight,
                    loadUnit: .kg,
                    normalizedWeightKg: weight,
                    estimatedOneRepMaxKg: WorkoutPerformanceMath.estimatedOneRepMax(weight: weight, reps: reps),
                    volumeKg: weight * Double(reps),
                    sourceSessionUpdatedAt: completedAt
                ))
            }
            context.insert(session)
            context.insert(exercise)
            sets.forEach(context.insert)
            session.exercises = [exercise]
            exercise.sets = sets
        }

        try context.saveWithRecoveryProtection()
        HistoryAnalyticsCache.shared.invalidate(container: container)
    }

    nonisolated private static func seedUITestHistoryMainCardioIfRequested(container: ModelContainer) throws {
        guard ProcessInfo.processInfo.arguments.contains("UITEST_SEED_HISTORY_MAIN_CARDIO") else { return }

        let context = ModelContext(container)
        context.autosaveEnabled = false
        let completedAt = Date()
        let sessionID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let session = WorkoutSession(
            id: sessionID,
            name: "Mixed Cardio Fixture",
            status: .completed,
            startedAt: completedAt.addingTimeInterval(-1_800),
            endedAt: completedAt,
            durationSeconds: 1_800,
            totalVolume: 800,
            summaryMetricsVersion: WorkoutMetricsService.currentSummaryMetricsVersion,
            createdAt: completedAt,
            updatedAt: completedAt
        )
        let exerciseID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let exercise = WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "seed-bench-press",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            totalSetCount: 1,
            completedSetCount: 1,
            session: session
        )
        let set = WorkoutSessionSet(
            sessionExerciseID: exerciseID,
            actualReps: 8,
            actualWeight: 100,
            actualLoadUnit: .kg,
            isCompleted: true,
            sessionExercise: exercise
        )
        let cardioBlocks = [
            WorkoutSessionCardioBlock(
                sessionID: sessionID,
                phase: .preWorkout,
                role: .warmUp,
                catalogExerciseUUID: "seed-walk",
                exerciseNameSnapshot: "Warm-up Walk",
                categorySnapshot: "Cardio",
                muscleSummarySnapshot: "Legs",
                trackingProfile: .timeOnly,
                goalKind: .time,
                targetDurationSeconds: 300,
                actualDurationSeconds: 300,
                isCompleted: true,
                session: session
            ),
            WorkoutSessionCardioBlock(
                sessionID: sessionID,
                phase: .preWorkout,
                role: .main,
                catalogExerciseUUID: "seed-bike",
                exerciseNameSnapshot: "Bike",
                categorySnapshot: "Cardio",
                muscleSummarySnapshot: "Legs",
                trackingProfile: .timeOnly,
                goalKind: .time,
                targetDurationSeconds: 600,
                actualDurationSeconds: 600,
                isCompleted: true,
                session: session
            ),
            WorkoutSessionCardioBlock(
                sessionID: sessionID,
                phase: .postWorkout,
                role: .finisher,
                catalogExerciseUUID: "seed-stairs",
                exerciseNameSnapshot: "Finisher Stairs",
                categorySnapshot: "Cardio",
                muscleSummarySnapshot: "Legs",
                trackingProfile: .timeOnly,
                goalKind: .time,
                targetDurationSeconds: 300,
                actualDurationSeconds: 300,
                isCompleted: true,
                session: session
            ),
        ]

        context.insert(session)
        context.insert(exercise)
        context.insert(set)
        cardioBlocks.forEach(context.insert)
        session.exercises = [exercise]
        session.cardioBlocks = cardioBlocks
        exercise.sets = [set]
        try context.saveWithRecoveryProtection()
        HistoryAnalyticsCache.shared.invalidate(container: container)
    }

#if DEBUG
    nonisolated private static func seedUITestCardioRouteIfRequested(container: ModelContainer) throws {
        guard ProcessInfo.processInfo.arguments.contains("UITEST_SEED_HISTORY_CARDIO_ROUTE") else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let now = Date()
        let session = WorkoutSession(name: "Evening Walk", status: .completed,
            startedAt: now.addingTimeInterval(-1_800), endedAt: now, durationSeconds: 1_800,
            totalVolume: 0, summaryMetricsVersion: WorkoutMetricsService.currentSummaryMetricsVersion,
            createdAt: now, updatedAt: now)
        let activity = WorkoutSessionCardioBlock(sessionID: session.id, phase: .preWorkout, role: .main,
            catalogExerciseUUID: "seed-outdoor-walk", exerciseNameSnapshot: "Outdoor Walk",
            categorySnapshot: "Cardio", muscleSummarySnapshot: "Legs", trackingProfile: .walkRun,
            goalKind: .open, targetDurationSeconds: 0, actualDurationSeconds: 1_800,
            actualDistanceMeters: 2_500, preferredDistanceUnit: .kilometers, isCompleted: true, session: session)
        context.insert(session)
        context.insert(activity)
        session.cardioBlocks = [activity]
        try context.saveWithRecoveryProtection()
        var route = CardioRoute(sessionID: session.id, activityID: activity.id)
        route.points = [(59.3293, 18.0686), (59.331, 18.073), (59.334, 18.071), (59.337, 18.08), (59.333, 18.084)]
            .enumerated().map { index, coordinate in
                .init(latitude: coordinate.0, longitude: coordinate.1,
                      timestamp: now.addingTimeInterval(Double(index) - 1_800), horizontalAccuracy: 5, segment: 0)
            }
        route.distanceMeters = 2_500
        try CardioRouteFiles().write(route)
        HistoryAnalyticsCache.shared.invalidate(container: container)
    }
#endif

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
    ) throws {
        try performPendingPersistentStoreReset(defaults: defaults) {
            try clearPersistentStoreFiles(fileManager: fileManager)
        }
    }

    static func performPendingPersistentStoreReset(
        defaults: UserDefaults,
        reset: () throws -> Void
    ) throws {
        guard defaults.bool(forKey: resetPersistentStoresKey) else { return }
        try reset()
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

    private static func clearPersistentStoreFiles(fileManager: FileManager) throws {
        try clearPersistentStoreFiles(in: persistentStoreDirectories(fileManager: fileManager), fileManager: fileManager)
    }

    static func clearPersistentStoreFiles(in directories: [URL], fileManager: FileManager = .default) throws {
        for directory in directories {
            guard fileManager.fileExists(atPath: directory.path) else { continue }
            let fileURLs = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            // A reset starts a new local lineage. Old rollback copies must never
            // repopulate the removed stores on this same launch.
            for fileURL in fileURLs where fileURL.lastPathComponent == "BackupJournal"
                || fileURL.lastPathComponent.hasPrefix("RestoreRecovery-") {
                try fileManager.removeItem(at: fileURL)
            }
            for fileURL in fileURLs where isPersistentStoreFile(fileURL) {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }
}
