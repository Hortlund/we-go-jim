import Foundation
import SwiftData
import Testing
@testable import WGJ

struct WeeklyGoalWidgetTests {
    @Test
    func widgetDescriptorUsesCacheResetKind() {
        #expect(WeeklyGoalWidgetDescriptor.kind == "WGJWeeklyGoalWidgetV8")
    }

    @Test
    func widgetExtensionDebugBuildUsesSingleExecutableForWidgetKitDiscovery() throws {
        let project = try String(contentsOf: projectFileURL(), encoding: .utf8)
        let widgetDebugConfiguration = try #require(
            xcodeBuildConfiguration(
                named: "Debug",
                containing: "CODE_SIGN_ENTITLEMENTS = WGJWidgetExtension/WGJWidgetExtension.entitlements;",
                in: project
            )
        )

        #expect(widgetDebugConfiguration.contains("ENABLE_DEBUG_DYLIB = NO;"))
    }

    @Test
    func storeUsesCacheResetSnapshotKey() {
        #expect(WeeklyGoalWidgetStore.snapshotDefaultsKey == "weeklyGoalWidget.snapshot.v8")
        #expect(WeeklyGoalWidgetStore.legacySnapshotDefaultsKeys == [
            "weeklyGoalWidget.snapshot.v1",
            "weeklyGoalWidget.snapshot.v2",
            "weeklyGoalWidget.snapshot.v3",
            "weeklyGoalWidget.snapshot.v4",
            "weeklyGoalWidget.snapshot.v5",
            "weeklyGoalWidget.snapshot.v6",
            "weeklyGoalWidget.snapshot.v7",
        ])
    }

    @Test
    func contentPolicyPreviewSnapshotShowsRealWidgetContent() {
        let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = WeeklyGoalWidgetContentPolicy.preview(generatedAt: generatedAt)

        #expect(snapshot.completedWorkouts == 3)
        #expect(snapshot.weeklyGoal == 4)
        #expect(snapshot.recentWeeks.count == 6)
        #expect(snapshot.recentWeeks.last?.completedWorkouts == 3)
        #expect(snapshot.statusText == "1 to go")
    }

    @Test
    func widgetProviderPlaceholderUsesVisibleSampleSnapshot() throws {
        let source = try String(contentsOf: widgetExtensionSourceURL(), encoding: .utf8)
        let placeholder = try #require(sourceFunction(named: "placeholder", in: source))

        #expect(placeholder.contains("WeeklyGoalWidgetContentPolicy.preview()"))
        #expect(!placeholder.contains("snapshot: nil"))
    }

    @Test
    func widgetEntrySnapshotIsNonOptionalForFirstPaint() throws {
        let source = try String(contentsOf: widgetExtensionSourceURL(), encoding: .utf8)

        #expect(source.contains("let snapshot: WeeklyGoalWidgetSnapshot\n"))
        #expect(!source.contains("let snapshot: WeeklyGoalWidgetSnapshot?"))
    }

    @Test
    func widgetBrandBadgeUsesPackagedLogoAsset() throws {
        let source = try String(contentsOf: widgetExtensionSourceURL(), encoding: .utf8)

        #expect(source.contains("Image(\"WidgetLogo\")"))
    }

    @Test
    func widgetViewAdaptsToIOS26RenderingModes() throws {
        let source = try String(contentsOf: widgetExtensionSourceURL(), encoding: .utf8)

        #expect(source.contains("@Environment(\\.widgetRenderingMode)"))
        #expect(source.contains("WidgetRenderingMode"))
        #expect(source.contains("case .fullColor"))
        #expect(source.contains("case .accented"))
        #expect(source.contains("case .vibrant"))
        #expect(source.contains(".widgetAccentable()"))
        #expect(source.contains(".widgetAccentedRenderingMode("))
        #expect(source.contains("templateLogo"))
        #expect(source.contains("renderingMode == .fullColor"))
        #expect(source.contains("WGJWidgetPalette.templatePrimary"))
    }

    @Test
    func widgetLayoutUsesCompactBadgesAndFlexibleMediumText() throws {
        let source = try String(contentsOf: widgetExtensionSourceURL(), encoding: .utf8)

        #expect(source.contains("WGJWidgetBrandBadge(size: 22)"))
        #expect(source.contains("WGJWidgetBrandBadge(size: 20)"))
        #expect(source.contains("mediumInfoWidth"))
        #expect(source.contains("minimumScaleFactor(0.55)"))
        #expect(!source.contains(".frame(width: 112"))
    }

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
    func contentPolicyNormalizesRecentWeeksForWidgetChart() {
        let calendar = Calendar(identifier: .gregorian)
        let baseWeek = Date(timeIntervalSince1970: 1_800_000_000)
        let priorWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: baseWeek)!
        let snapshot = WeeklyGoalWidgetContentPolicy.snapshot(
            completedWorkouts: 3,
            weeklyGoal: 4,
            weekStart: baseWeek,
            recentWeeks: [
                WeeklyGoalWidgetWeek(weekStart: priorWeek, completedWorkouts: -4, goal: 99),
                WeeklyGoalWidgetWeek(weekStart: baseWeek, completedWorkouts: 3, goal: 4),
            ],
            calendar: calendar
        )

        #expect(snapshot.recentWeeks.count == 2)
        #expect(snapshot.recentWeeks[0].completedWorkouts == 0)
        #expect(snapshot.recentWeeks[0].goal == 14)
        #expect(snapshot.recentWeeks[1].completedWorkouts == 3)
        #expect(snapshot.recentWeeks[1].goal == 4)
        #expect(snapshot.chartMaximumWorkouts == 14)
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

    @Test
    func storeTreatsLegacySnapshotWithoutRecentWeeksAsMissing() throws {
        let suiteName = defaultsSuiteName()
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = WeeklyGoalWidgetStore(defaults: defaults)
        let payload = """
        {
          "schemaVersion": 1,
          "completedWorkouts": 2,
          "weeklyGoal": 4,
          "weekStart": "2027-01-04T00:00:00Z",
          "weekEnd": "2027-01-11T00:00:00Z",
          "generatedAt": "2027-01-05T00:00:00Z",
          "hasActiveWorkout": false
        }
        """
        defaults.set(Data(payload.utf8), forKey: WeeklyGoalWidgetStore.snapshotDefaultsKey)

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
        var reloadCount = 0
        let publisher = WeeklyGoalWidgetPublisher(store: store) {
            reloadCount += 1
        }

        try publisher.publish(modelContext: context, generatedAt: Date(timeIntervalSince1970: 1_800_010_000))

        let snapshot = try #require(try store.load())
        #expect(snapshot.completedWorkouts == 1)
        #expect(snapshot.weeklyGoal == 3)
        #expect(snapshot.hasActiveWorkout)
        #expect(reloadCount == 1)
    }

    @MainActor
    @Test
    func publisherPublishesRecentWeeklyHistoryForMediumWidget() throws {
        let context = try makeInMemoryContext()
        let profile = UserProfile(displayName: "Athlete", weeklyWorkoutGoal: 4)
        context.insert(profile)
        let calendar = Calendar.current
        let currentWeek = weekStart(for: Date(), calendar: calendar)
        let twoWeeksAgo = try #require(calendar.date(byAdding: .weekOfYear, value: -2, to: currentWeek))
        let currentWeekWorkoutDate = try #require(calendar.date(byAdding: .day, value: 1, to: currentWeek))
        let oldWorkoutDate = try #require(calendar.date(byAdding: .day, value: 2, to: twoWeeksAgo))

        try insertCompletedSession(
            name: "Two Weeks Ago",
            at: oldWorkoutDate,
            context: context
        )
        try insertCompletedSession(
            name: "Current Week",
            at: currentWeekWorkoutDate,
            context: context
        )
        _ = try WorkoutSessionRepository(modelContext: context).createEmptySession(name: "Active")

        let suiteName = defaultsSuiteName()
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = WeeklyGoalWidgetStore(defaults: defaults)
        let publisher = WeeklyGoalWidgetPublisher(store: store) {}

        try publisher.publish(modelContext: context, generatedAt: Date(timeIntervalSince1970: 1_800_010_000))

        let snapshot = try #require(try store.load())
        #expect(snapshot.completedWorkouts == 1)
        #expect(snapshot.recentWeeks.count == 6)
        #expect(snapshot.recentWeeks.map(\.goal).allSatisfy { $0 == 4 })
        #expect(snapshot.recentWeeks.suffix(3).map(\.completedWorkouts) == [1, 0, 1])
        #expect(snapshot.hasActiveWorkout)
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
        var reloadCount = 0
        let publisher = WeeklyGoalWidgetPublisher(store: store) {
            reloadCount += 1
        }

        publisher.clear()

        #expect(try store.load() == nil)
        #expect(reloadCount == 1)
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

    private func projectFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ.xcodeproj/project.pbxproj")
    }

    private func widgetExtensionSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJWidgetExtension/WeeklyGoalWidget.swift")
    }

    private func sourceFunction(named name: String, in source: String) -> String? {
        guard
            let signatureRange = source.range(of: "func \(name)"),
            let openBrace = source[signatureRange.lowerBound...].firstIndex(of: "{")
        else {
            return nil
        }

        var depth = 0
        var cursor = openBrace
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[signatureRange.lowerBound...cursor])
                }
            }
            cursor = source.index(after: cursor)
        }

        return nil
    }

    private func xcodeBuildConfiguration(named name: String, containing marker: String, in project: String) -> String? {
        var searchStart = project.startIndex
        while let nameRange = project.range(of: "/* \(name) */ = {", range: searchStart..<project.endIndex) {
            guard let blockEnd = project.range(of: "\n\t\t};", range: nameRange.lowerBound..<project.endIndex) else {
                return nil
            }

            let block = String(project[nameRange.lowerBound..<blockEnd.upperBound])
            if block.contains(marker) {
                return block
            }

            searchStart = blockEnd.upperBound
        }

        return nil
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

    @MainActor
    private func insertCompletedSession(name: String, at date: Date, context: ModelContext) throws {
        let repository = WorkoutSessionRepository(modelContext: context)
        let session = try repository.createEmptySession(name: name)
        try repository.finishSession(sessionID: session.id)
        session.startedAt = date.addingTimeInterval(-3_600)
        session.endedAt = date
        session.durationSeconds = 3_600
        session.updatedAt = date
        try context.save()
    }

    private func weekStart(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }
}
