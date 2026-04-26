import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct ScreenSnapshotTests {
    @Test
    func exercisesCatalogSnapshotBuildsFilteredSections() {
        let chest = MuscleGroup(remoteID: 1, name: "Chest", nameEn: "Chest")
        let legs = MuscleGroup(remoteID: 2, name: "Legs", nameEn: "Legs")

        let bench = ExerciseCatalogItem(
            remoteUUID: "bench",
            displayName: "Bench Press",
            categoryName: "Strength",
            equipmentSummary: "Barbell",
            isCurated: true
        )
        bench.primaryMuscles = [chest]
        bench.aliases = [ExerciseAlias(value: "Barbell Bench", exercise: bench)]

        let squat = ExerciseCatalogItem(
            remoteUUID: "squat",
            displayName: "Back Squat",
            categoryName: "Strength",
            equipmentSummary: "Barbell",
            isCurated: true
        )
        squat.primaryMuscles = [legs]

        let hidden = ExerciseCatalogItem(
            remoteUUID: "hidden",
            displayName: "Hidden Curl",
            categoryName: "Accessories",
            equipmentSummary: "Cable",
            isHidden: true
        )
        hidden.primaryMuscles = [chest]

        var snapshot = ExercisesCatalogSnapshot.empty
        snapshot.rebuild(from: [bench, squat, hidden], muscleGroups: [chest, legs])

        #expect(snapshot.availableCategories == ["Strength"])
        #expect(snapshot.availableMuscles.map(\.name) == ["Chest", "Legs"])
        #expect(snapshot.exerciseByUUID["bench"]?.displayName == "Bench Press")

        snapshot.applyFilters(
            query: "bench",
            selectedPrimaryMuscleID: chest.remoteID,
            selectedCategory: "Strength",
            sortDescending: false
        )

        #expect(snapshot.sections.count == 1)
        #expect(snapshot.sections.first?.title == "B")
        #expect(snapshot.sections.first?.rows.map(\.displayName) == ["Bench Press"])
    }

    @Test
    func exercisesCatalogSnapshotToleratesDuplicateExerciseUUIDs() {
        let first = ExerciseCatalogItem(
            remoteUUID: "duplicate-catalog-uuid",
            displayName: "First Bench",
            categoryName: "Strength",
            equipmentSummary: "Barbell",
            isCurated: true
        )
        let duplicate = ExerciseCatalogItem(
            remoteUUID: "duplicate-catalog-uuid",
            displayName: "Duplicate Bench",
            categoryName: "Strength",
            equipmentSummary: "Barbell",
            isCurated: true
        )

        var snapshot = ExercisesCatalogSnapshot.empty
        snapshot.rebuild(from: [first, duplicate], muscleGroups: [])

        #expect(snapshot.exerciseByUUID["duplicate-catalog-uuid"]?.displayName == "First Bench")
        #expect(snapshot.sections.first?.rows.map(\.displayName) == ["First Bench"])
    }

    @Test
    func exercisesCatalogSearchStateClearsCommittedQueryAndFilters() {
        var state = ExercisesCatalogSearchState()
        let initialResetToken = state.resetToken

        state.updateDebouncedQuery("bench")
        state.selectedPrimaryMuscleID = 1
        state.selectedCategory = "Strength"
        state.sortDescending = true

        #expect(state.hasActiveFilters)

        state.clearSearchAndFilters()

        #expect(state.debouncedQuery == "")
        #expect(state.selectedPrimaryMuscleID == nil)
        #expect(state.selectedCategory == nil)
        #expect(state.sortDescending == false)
        #expect(state.hasActiveFilters == false)
        #expect(state.resetToken == initialResetToken + 1)
    }

    @Test
    func exercisesCatalogSnapshotLoaderBuildsControllerSnapshotFromContext() throws {
        let context = try makeSnapshotLoaderContext()
        let chest = MuscleGroup(remoteID: 1, name: "Chest", nameEn: "Chest")
        let bench = ExerciseCatalogItem(
            remoteUUID: "bench",
            displayName: "Bench Press",
            categoryName: "Strength",
            equipmentSummary: "Barbell",
            isCurated: true
        )
        bench.primaryMuscles = [chest]
        context.insert(chest)
        context.insert(bench)
        try context.save()

        let snapshot = try ExercisesCatalogSnapshotLoader.load(modelContext: context)

        #expect(snapshot.availableCategories == ["Strength"])
        #expect(snapshot.sections.first?.rows.map(\.displayName) == ["Bench Press"])
    }

    @Test
    func startWorkoutSnapshotLoaderBuildsGroupedSnapshotFromContext() throws {
        let context = try makeSnapshotLoaderContext()
        let folder = TemplateFolder(name: "Push", sortOrder: 0)
        let template = WorkoutTemplate(folderID: folder.id, name: "Push Template")
        let session = WorkoutSession(
            templateID: template.id,
            name: "Push Day",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_736_035_200),
            endedAt: Date(timeIntervalSince1970: 1_736_038_800),
            durationSeconds: 3600,
            totalVolume: 1200,
            prHitsCount: 1
        )
        context.insert(folder)
        context.insert(template)
        context.insert(session)
        try context.save()

        let snapshot = try StartWorkoutHomeSnapshotLoader.load(modelContext: context)

        #expect(snapshot.sections.map(\.title) == ["Push"])
        #expect(snapshot.sections.first?.templates.map(\.name) == ["Push Template"])
        #expect(snapshot.lastCompletedByTemplateID[template.id] == session.endedAt)
    }

    @Test
    func historyOverviewSnapshotLoaderBuildsFilteredSnapshotFromContext() throws {
        let context = try makeSnapshotLoaderContext()
        let session = WorkoutSession(
            name: "Push Day",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_736_035_200),
            endedAt: Date(timeIntervalSince1970: 1_736_038_800),
            durationSeconds: 3600,
            totalVolume: 1200,
            prHitsCount: 1
        )
        context.insert(session)
        try context.save()

        let loaded = try HistoryOverviewSnapshotLoader.load(
            modelContext: context,
            selectedDayFilter: session.endedAt
        )

        #expect(loaded.completedSessions.map(\.id) == [session.id])
        #expect(loaded.snapshot.sections.first?.cards.map(\.name) == ["Push Day"])
    }

    @Test
    func startWorkoutHomeSnapshotBuildsGroupedSectionsAndLastCompletedLookup() {
        let folder = TemplateFolder(name: "Push", sortOrder: 0)
        let unfiledTemplate = WorkoutTemplate(
            folderID: TemplateRepository.unfiledFolderID,
            name: "Unfiled Template"
        )
        let filedTemplate = WorkoutTemplate(
            folderID: folder.id,
            name: "Filed Template"
        )
        filedTemplate.sortOrder = 1
        unfiledTemplate.sortOrder = 0

        let completedSession = WorkoutSession(
            templateID: filedTemplate.id,
            name: "Push Day",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_736_035_200),
            endedAt: Date(timeIntervalSince1970: 1_736_038_800),
            durationSeconds: 3600,
            totalVolume: 1200,
            prHitsCount: 1
        )
        let olderSession = WorkoutSession(
            templateID: filedTemplate.id,
            name: "Push Day",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_736_000_000),
            endedAt: Date(timeIntervalSince1970: 1_736_001_000),
            durationSeconds: 1200,
            totalVolume: 500,
            prHitsCount: 0
        )

        let snapshot = StartWorkoutHomeSnapshotBuilder.build(
            folders: [folder],
            templates: [filedTemplate, unfiledTemplate],
            completedSessions: [olderSession, completedSession]
        )

        #expect(snapshot.sections.count == 2)
        #expect(snapshot.sections.first?.title == "Unfiled")
        #expect(snapshot.sections.last?.title == "Push")
        #expect(snapshot.sections.first?.templates.map { $0.name } == ["Unfiled Template"])
        #expect(snapshot.sections.last?.templates.map { $0.name } == ["Filed Template"])
        #expect(snapshot.lastCompletedByTemplateID[filedTemplate.id] == completedSession.endedAt)
    }

    @Test
    func historyOverviewSnapshotBuilderGroupsSessionsAndCountsDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let januarySession = WorkoutSession(
            name: "Push Day",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_736_035_200),
            endedAt: Date(timeIntervalSince1970: 1_736_038_800),
            durationSeconds: 3600,
            totalVolume: 1200,
            prHitsCount: 1
        )
        let januaryExercise = WorkoutSessionExercise(
            sessionID: januarySession.id,
            catalogExerciseUUID: "bench",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            sortOrder: 0,
            session: januarySession
        )
        let januarySet = WorkoutSessionSet(
            sessionExerciseID: januaryExercise.id,
            sortOrder: 0,
            targetReps: 8,
            targetWeight: 100,
            actualReps: 8,
            actualWeight: 100,
            isCompleted: true,
            sessionExercise: januaryExercise
        )
        januaryExercise.sets = [januarySet]
        januarySession.exercises = [januaryExercise]

        let februarySession = WorkoutSession(
            name: "Leg Day",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_738_886_400),
            endedAt: Date(timeIntervalSince1970: 1_738_890_000),
            durationSeconds: 3600,
            totalVolume: 1800,
            prHitsCount: 0
        )

        let snapshot = HistoryOverviewSnapshotBuilder.build(
            sessions: [januarySession, februarySession],
            selectedDayFilter: nil,
            calendar: calendar
        )

        #expect(snapshot.sections.count == 2)
        #expect(snapshot.sections.first?.cards.first?.name == "Leg Day")
        #expect(
            snapshot.workoutCountsByDay[calendar.startOfDay(for: januarySession.endedAt ?? januarySession.startedAt)] == 1
        )
        #expect(snapshot.sections.first?.cards.first?.summaryRows.isEmpty == true)
        #expect(snapshot.sections.last?.cards.first?.summaryRows == [
            HistorySessionSummaryRow(
                id: 0,
                exercise: "1 x Bench Press",
                bestSet: "100 kg x 8"
            ),
        ])

        let filtered = HistoryOverviewSnapshotBuilder.build(
            sessions: [januarySession, februarySession],
            selectedDayFilter: januarySession.endedAt,
            calendar: calendar
        )

        #expect(filtered.sections.count == 1)
        #expect(filtered.sections.first?.cards.map(\.name) == ["Push Day"])
    }

    @Test
    func profileDashboardContentBuildsStableSnapshot() {
        let widgetConfigs: [ProfileWidgetConfigSnapshot] = [
            ProfileWidgetConfigSnapshot(config: ProfileWidgetConfig(kind: .prs, sortOrder: 0)),
            ProfileWidgetConfigSnapshot(config: ProfileWidgetConfig(kind: .weeklyGoals, sortOrder: 1)),
            ProfileWidgetConfigSnapshot(config: ProfileWidgetConfig(kind: .coachBrief, sortOrder: 2)),
        ]
        let dashboard = ProfileDashboardSnapshot(
            personalRecords: [
                WorkoutPRRecord(
                    id: "bench",
                    catalogExerciseUUID: "bench",
                    exerciseName: "Bench Press",
                    estimatedOneRepMax: 110,
                    weight: 100,
                    reps: 3,
                    loadUnit: .kg,
                    achievedAt: .now
                ),
            ],
            weeklyProgress: [
                WeeklyWorkoutProgressPoint(
                    id: "week-1",
                    weekStart: Date(timeIntervalSince1970: 1_736_035_200),
                    completedWorkouts: 3,
                    goal: 0
                ),
            ],
            weeklyGoal: 0,
            overviewStats: ProfileOverviewStats(
                totalWorkouts: 6,
                totalPRHits: 4,
                totalDurationSeconds: 7_200,
                currentStreakDays: 2,
                longestStreakDays: 4,
                activeDaysThisMonth: 3,
                firstWorkoutDate: Date(timeIntervalSince1970: 1_735_430_400)
            ),
            topExercises: [
                ProfileTopExerciseStat(
                    catalogExerciseUUID: "bench",
                    exerciseName: "Bench Press",
                    sessionCount: 4,
                    lastPerformedAt: Date(timeIntervalSince1970: 1_736_035_200)
                ),
            ],
            activityDays: [
                ProfileActivityDay(
                    date: Date(timeIntervalSince1970: 1_736_035_200),
                    workoutCount: 1
                ),
            ]
        )
        let coachSnapshot = WeeklyCoachInsightSnapshot(
            weekStart: Date(timeIntervalSince1970: 1_736_035_200),
            revisionKey: "coach-week-1",
            baselineWeekCount: 6,
            completedWorkoutCount: 3,
            totalVolumeDelta: 14.2,
            consistencyDelta: 1,
            topRisingSignals: [
                WeeklyCoachSignal(
                    id: "bench",
                    catalogExerciseUUID: "bench",
                    exerciseName: "Bench Press",
                    deltaPercentage: 12.4,
                    summary: "Bench Press is up 12.4% vs the six-week baseline."
                ),
            ],
            topWatchSignals: [
                WeeklyCoachSignal(
                    id: "squat",
                    catalogExerciseUUID: "squat",
                    exerciseName: "Back Squat",
                    deltaPercentage: -5.8,
                    summary: "Back Squat is down 5.8% vs the six-week baseline."
                ),
            ],
            fallbackSummary: "",
            followUpKinds: [.whatImproved, .whatChanged, .whyFlat]
        )
        let coachBrief = ProfileCoachPresentation(
            snapshot: coachSnapshot,
            recap: CoachNarrativeSummary(
                headline: "Bench Press Led The Week",
                body: "You logged 3 workouts this week. Bench Press is up 12.4% vs the six-week baseline.",
                availabilityMode: .fallback
            )
        )

        let trendSeries: [ProfileWidgetKind: ExerciseMetricSeries] = [
            ProfileWidgetKind.exerciseOneRMTrend: ExerciseMetricSeries(
                catalogExerciseUUID: "bench",
                exerciseName: "Bench Press",
                loadUnit: .kg,
                points: [
                    ExerciseMetricPoint(
                        id: "point-1",
                        completedAt: Date(timeIntervalSince1970: 1_736_035_200),
                        value: 105
                    ),
                ]
            ),
        ]

        let content = ProfileDashboardContent.make(
            enabledWidgets: widgetConfigs,
            dashboard: dashboard,
            trendSeriesByKind: trendSeries,
            coachBrief: coachBrief
        )

        #expect(content.enabledWidgets.count == 3)
        #expect(content.personalRecords.map(\.exerciseName) == ["Bench Press"])
        #expect(content.weeklyProgress.first?.completedWorkouts == 3)
        #expect(content.weeklyGoal == 1)
        #expect(content.overviewStats.totalWorkouts == 6)
        #expect(content.topExercises.first?.sessionCount == 4)
        #expect(content.activityDays.first?.workoutCount == 1)
        #expect(content.trendSeriesByKind[.exerciseOneRMTrend]?.points.first?.value == 105)
        #expect(content.coachBrief?.recap.headline == "Bench Press Led The Week")
        #expect(content.coachBrief?.snapshot.topRisingSignals.map(\.exerciseName) == ["Bench Press"])
        #expect(content.coachBrief?.snapshot.followUpKinds == [.whatImproved, .whatChanged, .whyFlat])
    }

    private func makeSnapshotLoaderContext() throws -> ModelContext {
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
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            WorkoutSessionSupersetGroup.self,
            WorkoutSessionDropStage.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            ActiveWorkoutDraftSupersetGroup.self,
            ActiveWorkoutDraftDropStage.self,
            CompletedSetFact.self,
            CachedCoachNarrative.self,
            CachedCoachFollowUpNarrative.self,
            SocialOutboxItem.self,
            BlockedBro.self,
        ])
        let configuration = ModelConfiguration(
            "SnapshotLoaderTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
