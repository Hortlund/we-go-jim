import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct WorkoutSessionRepositoryTests {
    @Test
    func sessionLifecycleStartLogAndFinish() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "bench-1",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession(name: "Push Day")
        try repository.addExercise(sessionID: session.id, catalogItem: item)

        guard let exercise = try repository.sessionExercises(sessionID: session.id).first else {
            Issue.record("Expected session exercise")
            return
        }

        var drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        #expect(drafts.count == 3)
        drafts[1].actualWeight = 100
        drafts[1].actualReps = 5
        drafts[1].actualLoadUnit = .kg
        drafts[1].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)

        try repository.finishSession(sessionID: session.id, notes: "Solid day")

        let refreshed = try repository.session(id: session.id)
        #expect(refreshed?.status == .completed)
        #expect(refreshed?.notes == "Solid day")
        #expect((refreshed?.totalVolume ?? 0) > 0)
    }

    @Test
    func finishSessionPublishesWeeklyGoalWidgetProgress() throws {
        let context = try makeInMemoryContext()
        context.insert(UserProfile(displayName: "Athlete", weeklyWorkoutGoal: 3))

        let suiteName = "WorkoutSessionRepositoryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = WeeklyGoalWidgetStore(defaults: defaults)
        var reloadedKinds: [String] = []
        let publisher = WeeklyGoalWidgetPublisher(store: store) { kind in
            reloadedKinds.append(kind)
        }
        let repository = WorkoutSessionRepository(
            modelContext: context,
            weeklyGoalWidgetPublisher: publisher
        )

        let session = try repository.createEmptySession(name: "Widget Update")
        try repository.finishSession(sessionID: session.id)

        let snapshot = try #require(try store.load())
        #expect(snapshot.completedWorkouts == 1)
        #expect(snapshot.weeklyGoal == 3)
        #expect(snapshot.statusText == "2 to go")
        #expect(reloadedKinds == [WeeklyGoalWidgetPublisher.widgetKind])
    }

    @Test
    func addExerciseUsesPreferredWeightUnitForDefaultSets() throws {
        let context = try makeInMemoryContext()
        let profileRepository = ProfileRepository(modelContext: context)
        try profileRepository.updatePreferredWeightUnit(.lb)

        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "bench-lb-1",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession(name: "Push Day")
        try repository.addExercise(sessionID: session.id, catalogItem: item)

        guard let exercise = try repository.sessionExercises(sessionID: session.id).first else {
            Issue.record("Expected session exercise")
            return
        }

        let drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        #expect(drafts.count == 3)
        #expect(drafts.allSatisfy { $0.targetLoadUnit == .lb })
        #expect(drafts.allSatisfy { $0.actualLoadUnit == .lb })
    }

    @Test
    func createSessionFromTemplateCopiesCardioBlocks() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let repository = WorkoutSessionRepository(modelContext: context)

        let template = try templateRepository.createTemplate(name: "Hybrid", notes: "")
        try templateRepository.setCardioBlocks(
            templateID: template.id,
            drafts: [
                TemplateCardioBlockDraft(
                    phase: .preWorkout,
                    catalogExerciseUUID: "bike-1",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
                TemplateCardioBlockDraft(
                    phase: .postWorkout,
                    catalogExerciseUUID: "treadmill-1",
                    exerciseNameSnapshot: "Incline Treadmill Walk",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Cooldown",
                    targetDurationSeconds: 1200
                ),
            ]
        )

        let session = try repository.createSessionFromTemplate(templateID: template.id)

        #expect(try repository.sessionCardioBlocks(sessionID: session.id).map(\.phase) == [.preWorkout, .postWorkout])
        #expect(try repository.sessionCardioBlocks(sessionID: session.id).map(\.targetDurationSeconds) == [300, 1200])
    }

    @Test
    func createSessionFromTemplateCopiesExerciseNotes() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "template-notes-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let template = try templateRepository.createTemplate(name: "Push", notes: "")
        try templateRepository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: item.remoteUUID,
                    exerciseNameSnapshot: item.displayName,
                    categorySnapshot: item.categoryName,
                    muscleSummarySnapshot: item.primaryMuscleNames,
                    notes: "Elbows tucked and pause the first rep.",
                    targetRepMin: 6,
                    targetRepMax: 8,
                    restSeconds: 120,
                    setDrafts: [
                        TemplateExerciseSetDraft(targetReps: 6, targetWeight: 100, loadUnit: .kg, restSeconds: 120),
                    ]
                ),
            ]
        )

        let session = try repository.createSessionFromTemplate(templateID: template.id)
        let exercise = try #require(try repository.sessionExercises(sessionID: session.id).first)

        #expect(exercise.notes == "Elbows tucked and pause the first rep.")
    }

    @Test
    func createSessionFromTemplateCopiesWorkoutNotes() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let repository = WorkoutSessionRepository(modelContext: context)

        let template = try templateRepository.createTemplate(
            name: "Push",
            notes: "Keep the workout moving and log every top set."
        )

        let session = try repository.createSessionFromTemplate(templateID: template.id)

        #expect(session.notes == "Keep the workout moving and log every top set.")
    }

    @Test
    func createSessionFromTemplateRotatesMultiComponentExerciseAcrossCompletedSessions() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let repository = WorkoutSessionRepository(modelContext: context)

        let reverseCurl = ExerciseCatalogItem(
            remoteUUID: "session-rotation-reverse-curl",
            displayName: "Reverse Curl",
            categoryName: "Arms",
            equipmentSummary: "EZ bar",
            isCurated: true,
            sourceName: "seed"
        )
        let wristCurl = ExerciseCatalogItem(
            remoteUUID: "session-rotation-wrist-curl",
            displayName: "Wrist Curl",
            categoryName: "Arms",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(reverseCurl)
        context.insert(wristCurl)

        let template = try templateRepository.createTemplate(name: "Forearms", notes: "")
        try templateRepository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: reverseCurl.remoteUUID,
                    exerciseNameSnapshot: reverseCurl.displayName,
                    categorySnapshot: reverseCurl.categoryName,
                    muscleSummarySnapshot: reverseCurl.primaryMuscleNames,
                    targetRepMin: 10,
                    targetRepMax: 12,
                    restSeconds: 60,
                    setDrafts: [
                        TemplateExerciseSetDraft(targetReps: 12, targetWeight: 20, loadUnit: .kg, restSeconds: 60),
                    ],
                    components: [
                        TemplateExerciseComponentDraft(catalogItem: reverseCurl),
                        TemplateExerciseComponentDraft(catalogItem: wristCurl),
                    ]
                ),
            ]
        )

        let firstSession = try repository.createSessionFromTemplate(templateID: template.id)
        firstSession.startedAt = Date(timeIntervalSince1970: 1_000)
        try context.save()
        let firstExercise = try #require(try repository.sessionExercises(sessionID: firstSession.id).first)
        #expect(firstExercise.catalogExerciseUUID == reverseCurl.remoteUUID)
        #expect(firstExercise.templateExerciseID != nil)
        var firstDrafts = try repository.setDrafts(sessionExerciseID: firstExercise.id)
        firstDrafts[0].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: firstExercise.id, drafts: firstDrafts)
        try repository.finishSession(sessionID: firstSession.id)

        let secondSession = try repository.createSessionFromTemplate(templateID: template.id)
        secondSession.startedAt = Date(timeIntervalSince1970: 2_000)
        try context.save()
        let secondExercise = try #require(try repository.sessionExercises(sessionID: secondSession.id).first)
        #expect(secondExercise.catalogExerciseUUID == wristCurl.remoteUUID)
        #expect(secondExercise.templateExerciseID == firstExercise.templateExerciseID)
        var secondDrafts = try repository.setDrafts(sessionExerciseID: secondExercise.id)
        secondDrafts[0].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: secondExercise.id, drafts: secondDrafts)
        try repository.finishSession(sessionID: secondSession.id)

        let thirdSession = try repository.createSessionFromTemplate(templateID: template.id)
        let thirdExercise = try #require(try repository.sessionExercises(sessionID: thirdSession.id).first)
        #expect(thirdExercise.catalogExerciseUUID == reverseCurl.remoteUUID)
        #expect(thirdExercise.templateExerciseID == firstExercise.templateExerciseID)
    }

    @Test
    func createSessionFromTemplateDoesNotAdvanceRotationWhenNoSetsWereCompleted() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let repository = WorkoutSessionRepository(modelContext: context)

        let seatedCalfRaise = ExerciseCatalogItem(
            remoteUUID: "session-rotation-seated-calf-raise",
            displayName: "Seated Calf Raise",
            categoryName: "Legs",
            equipmentSummary: "Machine",
            isCurated: true,
            sourceName: "seed"
        )
        let standingCalfRaise = ExerciseCatalogItem(
            remoteUUID: "session-rotation-standing-calf-raise",
            displayName: "Standing Calf Raise",
            categoryName: "Legs",
            equipmentSummary: "Machine",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(seatedCalfRaise)
        context.insert(standingCalfRaise)

        let template = try templateRepository.createTemplate(name: "Calves", notes: "")
        try templateRepository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: seatedCalfRaise.remoteUUID,
                    exerciseNameSnapshot: seatedCalfRaise.displayName,
                    categorySnapshot: seatedCalfRaise.categoryName,
                    muscleSummarySnapshot: seatedCalfRaise.primaryMuscleNames,
                    targetRepMin: 12,
                    targetRepMax: 15,
                    restSeconds: 60,
                    setDrafts: [
                        TemplateExerciseSetDraft(targetReps: 15, targetWeight: 40, loadUnit: .kg, restSeconds: 60),
                    ],
                    components: [
                        TemplateExerciseComponentDraft(catalogItem: seatedCalfRaise),
                        TemplateExerciseComponentDraft(catalogItem: standingCalfRaise),
                    ]
                ),
            ]
        )

        let firstSession = try repository.createSessionFromTemplate(templateID: template.id)
        firstSession.startedAt = Date(timeIntervalSince1970: 1_000)
        try context.save()
        let firstExercise = try #require(try repository.sessionExercises(sessionID: firstSession.id).first)
        #expect(firstExercise.catalogExerciseUUID == seatedCalfRaise.remoteUUID)
        try repository.finishSession(sessionID: firstSession.id)

        let secondSession = try repository.createSessionFromTemplate(templateID: template.id)
        let secondExercise = try #require(try repository.sessionExercises(sessionID: secondSession.id).first)
        #expect(secondExercise.catalogExerciseUUID == seatedCalfRaise.remoteUUID)
        #expect(secondExercise.templateExerciseID == firstExercise.templateExerciseID)
    }

    @Test
    func previousSetLookupMatchesExerciseAndSetIndex() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "squat-1",
            displayName: "Back Squat",
            categoryName: "Legs",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let first = try repository.createEmptySession(name: "Legs 1")
        try repository.addExercise(sessionID: first.id, catalogItem: item)
        let firstExercise = try repository.sessionExercises(sessionID: first.id).first!
        var firstDrafts = try repository.setDrafts(sessionExerciseID: firstExercise.id)
        firstDrafts[0].actualWeight = 140
        firstDrafts[0].actualReps = 4
        firstDrafts[0].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: firstExercise.id, drafts: firstDrafts)
        try repository.finishSession(sessionID: first.id)

        let second = try repository.createEmptySession(name: "Legs 2")
        let previous = try repository.previousSet(
            for: item.remoteUUID,
            setIndex: 0,
            before: second.startedAt,
            excludingSessionID: second.id
        )

        #expect(previous?.actualWeight == 140)
        #expect(previous?.actualReps == 4)
    }

    @Test
    func previousSetMapProvidesFallbackForMissingIndexes() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "row-previous-map",
            displayName: "Barbell Row",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let first = try repository.createEmptySession(name: "Back 1")
        try repository.addExercise(sessionID: first.id, catalogItem: item)
        let firstExercise = try repository.sessionExercises(sessionID: first.id).first!
        var firstDrafts = try repository.setDrafts(sessionExerciseID: firstExercise.id)
        firstDrafts[0].actualWeight = 80
        firstDrafts[0].actualReps = 8
        firstDrafts[0].isCompleted = true
        firstDrafts[1].actualWeight = 90
        firstDrafts[1].actualReps = 6
        firstDrafts[1].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: firstExercise.id, drafts: firstDrafts)
        try repository.finishSession(sessionID: first.id)

        let second = try repository.createEmptySession(name: "Back 2")
        let map = try repository.previousSetMap(
            for: item.remoteUUID,
            before: second.startedAt,
            excludingSessionID: second.id,
            maxSetCount: 4
        )

        #expect(map.count == 4)
        #expect(map[0]?.weight == 80)
        #expect(map[0]?.reps == 8)
        #expect(map[1]?.weight == 90)
        #expect(map[1]?.reps == 6)
        #expect(map[2]?.weight == nil)
        #expect(map[2]?.reps == nil)
        #expect(map[3]?.weight == nil)
        #expect(map[3]?.reps == nil)
    }

    @Test
    func createTemplateFromCompletedSessionUsesLoggedValues() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let templateRepository = TemplateRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "deadlift-1",
            displayName: "Deadlift",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try sessionRepository.createEmptySession(name: "Back Day")
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: item)
        let exercise = try sessionRepository.sessionExercises(sessionID: session.id).first!
        try sessionRepository.updateExerciseNotes(
            sessionExerciseID: exercise.id,
            notes: "Brace hard before every pull."
        )
        var drafts = try sessionRepository.setDrafts(sessionExerciseID: exercise.id)
        drafts[0].actualWeight = 180
        drafts[0].actualReps = 3
        drafts[0].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        let template = try templateRepository.createTemplate(fromSessionID: session.id, name: "Deadlift Template")
        let templateExercise = try templateRepository.exercises(in: template.id).first
        let setDrafts = try templateExercise.map { try templateRepository.setDrafts(for: $0.id) } ?? []
        let components = try templateExercise.map { try templateRepository.components(for: $0.id) } ?? []

        #expect(templateExercise?.exerciseNameSnapshot == "Deadlift")
        #expect(templateExercise?.notes == "Brace hard before every pull.")
        #expect(setDrafts.first?.targetWeight == 180)
        #expect(setDrafts.first?.targetReps == 3)
        #expect(components.count == 1)
        #expect(components.first?.catalogExerciseUUID == item.remoteUUID)
    }

    @Test
    func backfillCompletedSessionSummariesUpdatesStaleMetricVersions() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "backfill-bench-1",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession(name: "Push Day")
        try repository.addExercise(sessionID: session.id, catalogItem: item)
        let exercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        var drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        drafts[0].actualWeight = 200
        drafts[0].actualReps = 1
        drafts[0].actualLoadUnit = .lb
        drafts[0].isCompleted = true
        drafts[1].actualWeight = 100
        drafts[1].actualReps = 5
        drafts[1].actualLoadUnit = .kg
        drafts[1].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try repository.finishSession(sessionID: session.id)

        let stored = try #require(try repository.session(id: session.id))
        stored.totalVolume = 999
        stored.prHitsCount = 99
        stored.summaryMetricsVersion = 0
        try context.save()

        let updatedCount = try repository.backfillCompletedSessionSummariesIfNeeded()
        let refreshed = try #require(try repository.session(id: session.id))

        #expect(updatedCount == 1)
        #expect(abs(refreshed.totalVolume - 500) < 0.01)
        #expect(refreshed.prHitsCount == 1)
        #expect(refreshed.summaryMetricsVersion == WorkoutMetricsService.currentSummaryMetricsVersion)
    }

    @Test
    func previousSetMapKeepsCompletedBodyweightLogsSeparateFromWeightedTargets() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let pullUp = ExerciseCatalogItem(
            remoteUUID: "previous-bodyweight-pullup",
            displayName: "Pull Up",
            categoryName: "Back",
            equipmentSummary: "Bodyweight",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(pullUp)

        let baseline = try repository.createEmptySession(name: "Baseline")
        try repository.addExercise(sessionID: baseline.id, catalogItem: pullUp)
        let baselineExercise = try #require(try repository.sessionExercises(sessionID: baseline.id).first)
        var baselineDrafts = try repository.setDrafts(sessionExerciseID: baselineExercise.id)
        baselineDrafts[1].targetWeight = 15
        baselineDrafts[1].targetLoadUnit = .kg
        baselineDrafts[1].actualWeight = nil
        baselineDrafts[1].actualReps = 12
        baselineDrafts[1].actualLoadUnit = .bodyweight
        baselineDrafts[1].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: baselineExercise.id, drafts: baselineDrafts)
        try repository.finishSession(sessionID: baseline.id)

        let current = try repository.createEmptySession(name: "Current")
        try repository.addExercise(sessionID: current.id, catalogItem: pullUp)

        let previousSetMap = try repository.previousSetMap(
            for: pullUp.remoteUUID,
            before: current.startedAt,
            excludingSessionID: current.id,
            maxSetCount: 3
        )
        let previousSet = try #require(previousSetMap[1])

        #expect(previousSet.reps == 12)
        #expect(previousSet.weight == nil)
        #expect(previousSet.unit == .bodyweight)
    }

    @Test
    func updateExerciseRestPersists() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "row-1",
            displayName: "Row",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession()
        try repository.addExercise(sessionID: session.id, catalogItem: item)
        let exercise = try repository.sessionExercises(sessionID: session.id).first!

        try repository.updateExerciseRest(sessionExerciseID: exercise.id, restSeconds: 165)
        let refreshed = try repository.sessionExercises(sessionID: session.id).first
        #expect(refreshed?.restSeconds == 165)
    }

    @Test
    func updateExerciseRestPreservesCustomSetOverrides() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "rest-override-1",
            displayName: "Incline Press",
            categoryName: "Chest",
            equipmentSummary: "Dumbbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession()
        try repository.addExercise(sessionID: session.id, catalogItem: item)
        let exercise = try repository.sessionExercises(sessionID: session.id).first!
        var drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        drafts[1].restSeconds = 180
        try repository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)

        try repository.updateExerciseRest(sessionExerciseID: exercise.id, restSeconds: 150)

        let updatedDrafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        #expect(updatedDrafts[0].restSeconds == 150)
        #expect(updatedDrafts[1].restSeconds == 180)
        #expect(updatedDrafts[2].restSeconds == 150)
    }

    @Test
    func updateExerciseRepRangePersists() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "rep-range-1",
            displayName: "Lat Pulldown",
            categoryName: "Back",
            equipmentSummary: "Cable",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession()
        try repository.addExercise(sessionID: session.id, catalogItem: item)
        let exercise = try repository.sessionExercises(sessionID: session.id).first!

        try repository.updateExerciseRepRange(sessionExerciseID: exercise.id, minReps: 8, maxReps: 12)

        let refreshed = try repository.sessionExercises(sessionID: session.id).first
        #expect(refreshed?.targetRepMin == 8)
        #expect(refreshed?.targetRepMax == 12)
    }

    @Test
    func updateExerciseNotesPersists() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "exercise-notes-1",
            displayName: "Lat Pulldown",
            categoryName: "Back",
            equipmentSummary: "Cable",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession()
        try repository.addExercise(sessionID: session.id, catalogItem: item)
        let exercise = try #require(try repository.sessionExercises(sessionID: session.id).first)

        try repository.updateExerciseNotes(
            sessionExerciseID: exercise.id,
            notes: "Keep chest tall and drive elbows down."
        )

        let refreshed = try repository.sessionExercises(sessionID: session.id).first
        #expect(refreshed?.notes == "Keep chest tall and drive elbows down.")
    }

    @Test
    func saveSetDraftsOnlyTouchesChangedSetAndPreservesParentStamps() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "draft-delta-1",
            displayName: "Leg Press",
            categoryName: "Legs",
            equipmentSummary: "Machine",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession(name: "Lower")
        try repository.addExercise(sessionID: session.id, catalogItem: item)

        let initialSession = try #require(try repository.session(id: session.id))
        let initialExercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        let initialSets = (initialExercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        #expect(initialSets.count == 3)

        let baselineSessionUpdatedAt = Date(timeIntervalSince1970: 1_000)
        let baselineExerciseUpdatedAt = Date(timeIntervalSince1970: 2_000)
        initialSession.updatedAt = baselineSessionUpdatedAt
        initialExercise.updatedAt = baselineExerciseUpdatedAt

        var baselineSetUpdatedAtByID: [UUID: Date] = [:]
        for (index, set) in initialSets.enumerated() {
            let updatedAt = Date(timeIntervalSince1970: 3_000 + Double(index))
            set.updatedAt = updatedAt
            baselineSetUpdatedAtByID[set.id] = updatedAt
        }
        try context.save()

        var drafts = try repository.setDrafts(sessionExerciseID: initialExercise.id)
        drafts[1].actualWeight = 180
        drafts[1].actualReps = 10
        drafts[1].actualLoadUnit = .lb
        drafts[1].isCompleted = true

        try repository.saveSetDrafts(sessionExerciseID: initialExercise.id, drafts: drafts)

        let refreshedSession = try #require(try repository.session(id: session.id))
        let refreshedExercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        let refreshedSets = (refreshedExercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }

        #expect(refreshedSession.updatedAt == baselineSessionUpdatedAt)
        #expect(refreshedExercise.updatedAt == baselineExerciseUpdatedAt)
        #expect(refreshedSets[0].updatedAt == baselineSetUpdatedAtByID[refreshedSets[0].id])
        #expect(refreshedSets[2].updatedAt == baselineSetUpdatedAtByID[refreshedSets[2].id])
        #expect((refreshedSets[1].updatedAt) > (baselineSetUpdatedAtByID[refreshedSets[1].id] ?? .distantFuture))
    }

    @Test
    func saveSetDraftsNoOpPreservesExistingTimestamps() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "draft-noop-1",
            displayName: "Chest Press",
            categoryName: "Chest",
            equipmentSummary: "Machine",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession(name: "Push")
        try repository.addExercise(sessionID: session.id, catalogItem: item)

        let initialSession = try #require(try repository.session(id: session.id))
        let initialExercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        let initialSets = (initialExercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let baselineSessionUpdatedAt = Date(timeIntervalSince1970: 4_000)
        let baselineExerciseUpdatedAt = Date(timeIntervalSince1970: 5_000)

        initialSession.updatedAt = baselineSessionUpdatedAt
        initialExercise.updatedAt = baselineExerciseUpdatedAt

        var baselineSetUpdatedAtByID: [UUID: Date] = [:]
        for (index, set) in initialSets.enumerated() {
            let updatedAt = Date(timeIntervalSince1970: 6_000 + Double(index))
            set.updatedAt = updatedAt
            baselineSetUpdatedAtByID[set.id] = updatedAt
        }
        try context.save()

        let drafts = try repository.setDrafts(sessionExerciseID: initialExercise.id)
        try repository.saveSetDrafts(sessionExerciseID: initialExercise.id, drafts: drafts)

        let refreshedSession = try #require(try repository.session(id: session.id))
        let refreshedExercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        let refreshedSets = (refreshedExercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }

        #expect(refreshedSession.updatedAt == baselineSessionUpdatedAt)
        #expect(refreshedExercise.updatedAt == baselineExerciseUpdatedAt)
        for set in refreshedSets {
            #expect(set.updatedAt == baselineSetUpdatedAtByID[set.id])
        }
    }

    @Test
    func deleteSessionRemovesFromHistory() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)
        let session = try repository.createEmptySession(name: "Delete Me")
        try repository.deleteSession(id: session.id)
        #expect(try repository.session(id: session.id) == nil)
    }

    @Test
    func deleteSessionRecordsCloudMirrorTombstone() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)
        let session = try repository.createEmptySession(name: "Delete Cloud Mirror")

        try repository.deleteSession(id: session.id)

        #expect(try tombstone(entityName: "WorkoutSession", entityID: session.id, in: context) != nil)
    }

    @Test
    func archiveAndRestoreCompletedSessionKeepsCanonicalHistory() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "archive-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession(name: "Archive Me")
        try repository.addExercise(sessionID: session.id, catalogItem: item)
        let exercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        var drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        drafts[1].actualWeight = 100
        drafts[1].actualReps = 5
        drafts[1].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try repository.finishSession(sessionID: session.id)

        try repository.archiveSession(id: session.id)

        let archivedSession = try #require(try repository.session(id: session.id))
        #expect(archivedSession.archivedAt != nil)
        #expect(try repository.completedSessions().isEmpty)
        #expect(try repository.completedSessions(includeArchived: true).count == 1)
        #expect(try repository.archivedSessions().map(\.id) == [session.id])

        try repository.restoreArchivedSession(id: session.id)

        let restoredSession = try #require(try repository.session(id: session.id))
        #expect(restoredSession.archivedAt == nil)
        #expect(try repository.completedSessions().map(\.id) == [session.id])
        #expect(try repository.archivedSessions().isEmpty)
    }

    @Test
    func cancelSessionDiscardsActiveWorkout() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let session = try repository.createEmptySession(name: "Cancel Me")
        #expect(try repository.activeSession()?.id == session.id)

        try repository.cancelSession(sessionID: session.id)

        #expect(try repository.session(id: session.id) == nil)
        #expect(try repository.activeSession() == nil)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
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

    private func tombstone(
        entityName: String,
        entityID: UUID,
        in context: ModelContext
    ) throws -> UserDataDeletionTombstone? {
        var descriptor = FetchDescriptor<UserDataDeletionTombstone>(
            predicate: #Predicate { tombstone in
                tombstone.entityName == entityName && tombstone.entityID == entityID
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
