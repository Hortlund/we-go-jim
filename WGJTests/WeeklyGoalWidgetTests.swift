import Foundation
import SwiftData
import Testing
@testable import WGJ

struct WeeklyGoalWidgetTests {
    @Test
    func contentPolicyClampsGoalAndFinishedCount() {
        let snapshot = WeeklyGoalWidgetContentPolicy.snapshot(
            completedWorkouts: -2,
            weeklyGoal: 99,
            weekStart: Date(timeIntervalSince1970: 1_800_000_000),
            generatedAt: Date(timeIntervalSince1970: 1_800_010_000)
        )

        #expect(snapshot.completedWorkouts == 0)
        #expect(snapshot.weeklyGoal == 14)
        #expect(snapshot.remainingWorkouts == 14)
        #expect(snapshot.progressFraction == 0)
    }

    @Test
    func contentPolicyDoesNotCountActiveWorkoutSnapshot() {
        let snapshot = WeeklyGoalWidgetContentPolicy.snapshot(
            completedWorkouts: 2,
            weeklyGoal: 4,
            weekStart: Date(timeIntervalSince1970: 1_800_000_000),
            hasActiveWorkout: true,
            generatedAt: Date(timeIntervalSince1970: 1_800_010_000)
        )

        #expect(snapshot.completedWorkouts == 2)
        #expect(snapshot.remainingWorkouts == 2)
        #expect(snapshot.statusText == "2 to go")
    }

    @Test
    func contentPolicyStatusCopyCoversProgressStates() {
        let weekStart = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(
            WeeklyGoalWidgetContentPolicy.snapshot(
                completedWorkouts: 0,
                weeklyGoal: 4,
                weekStart: weekStart
            ).statusText == "4 to go"
        )
        #expect(
            WeeklyGoalWidgetContentPolicy.snapshot(
                completedWorkouts: 2,
                weeklyGoal: 4,
                weekStart: weekStart
            ).statusText == "2 to go"
        )
        #expect(
            WeeklyGoalWidgetContentPolicy.snapshot(
                completedWorkouts: 4,
                weeklyGoal: 4,
                weekStart: weekStart
            ).statusText == "Goal hit"
        )
        #expect(
            WeeklyGoalWidgetContentPolicy.snapshot(
                completedWorkouts: 5,
                weeklyGoal: 4,
                weekStart: weekStart
            ).statusText == "Goal beaten"
        )
    }

    @Test
    func storeRoundTripsAndClearsSnapshot() throws {
        let suiteName = defaultsSuiteName()
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = WeeklyGoalWidgetStore(defaults: defaults)
        let snapshot = WeeklyGoalWidgetContentPolicy.snapshot(
            completedWorkouts: 3,
            weeklyGoal: 4,
            weekStart: Date(timeIntervalSince1970: 1_800_000_000),
            generatedAt: Date(timeIntervalSince1970: 1_800_010_000)
        )

        try store.save(snapshot)

        #expect(try store.load() == snapshot)

        store.clear()
        #expect(try store.load() == nil)
    }

    @Test
    func storeTreatsCorruptDataAsMissing() throws {
        let suiteName = defaultsSuiteName()
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = WeeklyGoalWidgetStore(defaults: defaults)
        defaults.set(Data("not-json".utf8), forKey: WeeklyGoalWidgetStore.snapshotDefaultsKey)

        #expect(try store.load() == nil)
    }

    @MainActor
    @Test
    func publisherPublishesCurrentWeekFinishedWorkoutProgressOnly() throws {
        let context = try makeInMemoryContext()
        let profile = UserProfile(displayName: "Athlete", weeklyWorkoutGoal: 3)
        context.insert(profile)

        let repository = WorkoutSessionRepository(modelContext: context)
        let active = try repository.createEmptySession(name: "Active")
        #expect(active.status == .active)

        let completed = try repository.createEmptySession(name: "Completed")
        try repository.finishSession(sessionID: completed.id)

        let suiteName = defaultsSuiteName()
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = WeeklyGoalWidgetStore(defaults: defaults)
        var reloads: [String] = []
        let publisher = WeeklyGoalWidgetPublisher(store: store) { kind in
            reloads.append(kind)
        }

        try publisher.publish(modelContext: context, generatedAt: Date(timeIntervalSince1970: 1_800_010_000))

        let snapshot = try #require(try store.load())
        #expect(snapshot.completedWorkouts == 1)
        #expect(snapshot.weeklyGoal == 3)
        #expect(snapshot.hasActiveWorkout)
        #expect(reloads == [WeeklyGoalWidgetPublisher.widgetKind])
    }

    @Test
    func publisherClearsSnapshotAndReloadsTimeline() throws {
        let suiteName = defaultsSuiteName()
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = WeeklyGoalWidgetStore(defaults: defaults)
        try store.save(
            WeeklyGoalWidgetContentPolicy.snapshot(
                completedWorkouts: 1,
                weeklyGoal: 4,
                weekStart: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        var reloads: [String] = []
        let publisher = WeeklyGoalWidgetPublisher(store: store) { kind in
            reloads.append(kind)
        }

        publisher.clear()

        #expect(try store.load() == nil)
        #expect(reloads == [WeeklyGoalWidgetPublisher.widgetKind])
    }

    @MainActor
    @Test
    func widgetDeepLinkRoutesToProfileTab() throws {
        let tabState = AppTabState()
        tabState.selectedTab = .startWorkout

        let didRoute = AppDeepLinkRouter.route(
            url: try #require(URL(string: "wgj://profile/weekly-goal")),
            appPhase: .main,
            tabState: tabState
        )

        #expect(didRoute)
        #expect(tabState.selectedTab == .profile)
    }

    @MainActor
    @Test
    func widgetDeepLinkWaitsUntilMainPhase() throws {
        let tabState = AppTabState()
        tabState.selectedTab = .startWorkout

        let didRoute = AppDeepLinkRouter.route(
            url: try #require(URL(string: "wgj://profile/weekly-goal")),
            appPhase: .splash,
            tabState: tabState
        )

        #expect(didRoute == false)
        #expect(tabState.selectedTab == .startWorkout)
    }

    private func defaultsSuiteName() -> String {
        "WeeklyGoalWidgetTests.\(UUID().uuidString)"
    }

    private func temporaryDefaults(suiteName: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
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
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
