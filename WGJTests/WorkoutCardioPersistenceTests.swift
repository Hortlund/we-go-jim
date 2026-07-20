import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class WorkoutCardioPersistenceTests: XCTestCase {
    func testTemplateCreatesTwoOrderedMainCardioActivities() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let templateRepository = TemplateRepository(modelContext: context)
        let activeRepository = ActiveWorkoutDraftRepository(modelContext: context)
        let template = try templateRepository.createTemplate(name: "Cardio Day", notes: "")
        let drafts = [
            TemplateCardioBlockDraft.fixture(
                role: .main,
                sortOrder: 0,
                name: "Treadmill Walk",
                trackingProfile: .treadmill,
                goalKind: .distance,
                targetDurationSeconds: 0,
                targetDistanceMeters: 5_000,
                preferredDistanceUnit: .kilometers
            ),
            TemplateCardioBlockDraft.fixture(
                role: .main,
                sortOrder: 1,
                name: "Bike",
                trackingProfile: .machineDistance,
                goalKind: .time,
                targetDurationSeconds: 1_200,
                targetDistanceMeters: 8_000,
                preferredDistanceUnit: .kilometers
            ),
        ]

        try templateRepository.setCardioActivities(templateID: template.id, drafts: drafts)

        let persisted = try templateRepository.cardioActivities(templateID: template.id)
        XCTAssertEqual(persisted.map(\.id), drafts.map(\.id))
        XCTAssertEqual(persisted.map(\.role), [.main, .main])
        XCTAssertEqual(persisted.map(\.sortOrder), [0, 1])

        let active = try activeRepository.createSessionFromTemplate(templateID: template.id)
        let blocks = try activeRepository.cardioActivities(sessionID: active.id)
        XCTAssertEqual(blocks.map(\.exerciseNameSnapshot), ["Treadmill Walk", "Bike"])
        XCTAssertEqual(blocks.map(\.sourceTemplateCardioID), drafts.map(\.id))
        XCTAssertEqual(blocks.map(\.sortOrder), [0, 1])
        XCTAssertEqual(Set(blocks.map(\.id)).count, 2)
        XCTAssertTrue(Set(blocks.map(\.id)).isDisjoint(with: Set(drafts.map(\.id))))
        XCTAssertEqual(blocks[0].trackingProfile, .treadmill)
        XCTAssertEqual(blocks[0].goalKind, .distance)
        XCTAssertEqual(blocks[0].targetDistanceMeters, 5_000)
        XCTAssertEqual(blocks[0].preferredDistanceUnit, .kilometers)
        XCTAssertEqual(blocks[1].trackingProfile, .machineDistance)
        XCTAssertEqual(blocks[1].goalKind, .time)
        XCTAssertEqual(blocks[1].targetDurationSeconds, 1_200)
    }

    func testTemplateAndActiveMutationsTargetActivityIDWithinRole() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let templateRepository = TemplateRepository(modelContext: context)
        let activeRepository = ActiveWorkoutDraftRepository(modelContext: context)
        let template = try templateRepository.createTemplate(name: "Intervals", notes: "")
        let walk = TemplateCardioBlockDraft.fixture(
            role: .main,
            sortOrder: 10,
            name: "Treadmill Walk"
        )
        var bike = TemplateCardioBlockDraft.fixture(
            role: .main,
            sortOrder: 2,
            name: "Bike"
        )

        try templateRepository.setCardioActivities(templateID: template.id, drafts: [walk, bike])

        var persisted = try templateRepository.cardioActivities(templateID: template.id)
        XCTAssertEqual(persisted.map(\.exerciseNameSnapshot), ["Bike", "Treadmill Walk"])
        XCTAssertEqual(persisted.map(\.sortOrder), [0, 1])

        bike.exerciseNameSnapshot = "Assault Bike"
        bike.sortOrder = 12
        try templateRepository.upsertCardioActivity(templateID: template.id, draft: bike)
        persisted = try templateRepository.cardioActivities(templateID: template.id)
        XCTAssertEqual(persisted.count, 2)
        XCTAssertEqual(persisted.first(where: { $0.id == bike.id })?.exerciseNameSnapshot, "Assault Bike")

        let active = try activeRepository.createSessionFromTemplate(templateID: template.id)
        var activeBlocks = try activeRepository.cardioActivities(sessionID: active.id)
        let walkBlock = try XCTUnwrap(activeBlocks.first(where: { $0.sourceTemplateCardioID == walk.id }))
        let bikeBlock = try XCTUnwrap(activeBlocks.first(where: { $0.sourceTemplateCardioID == bike.id }))
        var bikeDraft = WorkoutCardioBlockDraft(model: bikeBlock)
        bikeDraft.exerciseNameSnapshot = "Air Bike"

        try activeRepository.upsertCardioActivity(sessionID: active.id, draft: bikeDraft)
        try activeRepository.updateCardioResult(
            sessionID: active.id,
            activityID: bikeBlock.id,
            actualDurationSeconds: 900,
            actualDistanceMeters: 6_000,
            preferredDistanceUnit: .kilometers,
            inclinePercent: 1.5,
            resistanceLevel: 7,
            cardioNotes: "Hard finish",
            isCompleted: true
        )
        try activeRepository.removeCardioActivity(sessionID: active.id, activityID: walkBlock.id)

        activeBlocks = try activeRepository.cardioActivities(sessionID: active.id)
        XCTAssertEqual(activeBlocks.map(\.id), [bikeBlock.id])
        XCTAssertEqual(activeBlocks[0].exerciseNameSnapshot, "Air Bike")
        XCTAssertEqual(activeBlocks[0].cardioNotes, "Hard finish")
        XCTAssertEqual(activeBlocks[0].actualDurationSeconds, 900)
        XCTAssertEqual(activeBlocks[0].actualDistanceMeters, 6_000)
        XCTAssertEqual(activeBlocks[0].preferredDistanceUnit, .kilometers)
        XCTAssertEqual(activeBlocks[0].inclinePercent, 1.5)
        XCTAssertEqual(activeBlocks[0].resistanceLevel, 7)
        XCTAssertTrue(activeBlocks[0].isCompleted)

        try templateRepository.removeCardioActivity(templateID: template.id, activityID: walk.id)
        XCTAssertEqual(try templateRepository.cardioActivities(templateID: template.id).map(\.id), [bike.id])
    }

    func testHistoricalSessionCopiesTemplatePlanWithNewIDsAndSourceIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(
            modelContext: context,
            weeklyGoalWidgetPublisher: nil
        )
        let template = try templateRepository.createTemplate(name: "Mixed Cardio", notes: "")
        let drafts = [
            TemplateCardioBlockDraft.fixture(
                role: .warmUp,
                sortOrder: 4,
                name: "Row",
                trackingProfile: .rower,
                goalKind: .distance,
                targetDurationSeconds: 0,
                targetDistanceMeters: 2_000,
                preferredDistanceUnit: .meters
            ),
            TemplateCardioBlockDraft.fixture(
                role: .main,
                sortOrder: 9,
                name: "Run",
                trackingProfile: .walkRun,
                goalKind: .time,
                targetDurationSeconds: 1_800,
                preferredDistanceUnit: .miles
            ),
        ]
        try templateRepository.setCardioActivities(templateID: template.id, drafts: drafts)

        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        let activities = try sessionRepository.sessionCardioBlocks(sessionID: session.id)

        XCTAssertEqual(activities.map(\.sourceTemplateCardioID), drafts.map(\.id))
        XCTAssertTrue(Set(activities.map(\.id)).isDisjoint(with: Set(drafts.map(\.id))))
        XCTAssertEqual(activities.map(\.role), [.warmUp, .main])
        XCTAssertEqual(activities.map(\.sortOrder), [0, 0])
        XCTAssertEqual(activities.map(\.trackingProfile), [.rower, .walkRun])
        XCTAssertEqual(activities.map(\.goalKind), [.distance, .time])
        XCTAssertEqual(activities[0].targetDistanceMeters, 2_000)
        XCTAssertEqual(activities[0].preferredDistanceUnit, .meters)
        XCTAssertEqual(activities[1].targetDurationSeconds, 1_800)
        XCTAssertEqual(activities[1].preferredDistanceUnit, .miles)
    }

    func testActiveCompletionTargetsActivityIDWithinRole() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let templateRepository = TemplateRepository(modelContext: context)
        let activeRepository = ActiveWorkoutDraftRepository(modelContext: context)
        let template = try templateRepository.createTemplate(name: "Completion", notes: "")
        let drafts = [
            TemplateCardioBlockDraft.fixture(role: .main, sortOrder: 0, name: "Treadmill Walk"),
            TemplateCardioBlockDraft.fixture(role: .main, sortOrder: 1, name: "Bike"),
        ]
        try templateRepository.setCardioActivities(templateID: template.id, drafts: drafts)
        let active = try activeRepository.createSessionFromTemplate(templateID: template.id)
        let activities = try activeRepository.cardioActivities(sessionID: active.id)

        try activeRepository.setCardioCompletion(
            sessionID: active.id,
            activityID: activities[1].id,
            isCompleted: true
        )

        XCTAssertEqual(
            try activeRepository.cardioActivities(sessionID: active.id).map(\.isCompleted),
            [false, true]
        )
    }

    func testCompletionPreservesRuntimeCardioResultsAndClearsTimerState() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let templateRepository = TemplateRepository(modelContext: context)
        let activeRepository = ActiveWorkoutDraftRepository(modelContext: context)
        let template = try templateRepository.createTemplate(name: "Cardio Results", notes: "")
        let drafts = [
            TemplateCardioBlockDraft.fixture(
                role: .main,
                sortOrder: 0,
                name: "Treadmill Walk",
                trackingProfile: .treadmill,
                goalKind: .distance,
                targetDurationSeconds: 0,
                targetDistanceMeters: 5_000,
                preferredDistanceUnit: .kilometers
            ),
            TemplateCardioBlockDraft.fixture(
                role: .main,
                sortOrder: 1,
                name: "Bike",
                trackingProfile: .machineDistance,
                goalKind: .time,
                targetDurationSeconds: 1_200,
                preferredDistanceUnit: .kilometers
            ),
        ]
        try templateRepository.setCardioActivities(templateID: template.id, drafts: drafts)
        let active = try activeRepository.createSessionFromTemplate(templateID: template.id)
        let activeActivities = try activeRepository.cardioActivities(sessionID: active.id)
        var runtimeActivities = activeActivities.map(ActiveWorkoutRuntimeCardioBlock.init(model:))
        runtimeActivities[0].actualDurationSeconds = 1_500
        runtimeActivities[0].actualDistanceMeters = 5_200
        runtimeActivities[0].inclinePercent = 2.5
        runtimeActivities[0].resistanceLevel = 4
        runtimeActivities[0].cardioNotes = "Steady effort"
        runtimeActivities[0].timerState = .running
        runtimeActivities[0].timerSegmentStartedAt = .now
        runtimeActivities[0].timerAccumulatedSeconds = 1_200
        runtimeActivities[0].isCompleted = true
        runtimeActivities[1].actualDurationSeconds = 1_100
        runtimeActivities[1].cardioNotes = "Intervals"
        runtimeActivities[1].timerState = .paused
        runtimeActivities[1].timerAccumulatedSeconds = 1_100
        runtimeActivities[1].isCompleted = true
        let runtime = ActiveWorkoutRuntimeSession(
            id: active.id,
            templateID: active.templateID,
            name: active.name,
            startedAt: active.startedAt,
            notes: active.notes,
            cardioBlocks: runtimeActivities,
            createdAt: active.createdAt,
            updatedAt: .now
        )

        let result = try WorkoutCompletionRepository(modelContext: context)
            .completeWorkout(session: runtime)
        let completedSessionID = result.sessionID

        let completed = try context.fetch(
            FetchDescriptor<WorkoutSessionCardioBlock>(
                predicate: #Predicate { $0.sessionID == completedSessionID }
            )
        ).sorted(by: completedCardioOrder)
        XCTAssertEqual(completed.map(\.id), runtimeActivities.map(\.id))
        XCTAssertEqual(completed.map(\.sourceTemplateCardioID), drafts.map(\.id))
        XCTAssertEqual(completed.map(\.sortOrder), [0, 1])
        XCTAssertEqual(completed.map(\.actualDurationSeconds), [1_500, 1_100])
        XCTAssertEqual(completed[0].actualDistanceMeters, 5_200)
        XCTAssertEqual(completed[0].preferredDistanceUnit, .kilometers)
        XCTAssertEqual(completed[0].inclinePercent, 2.5)
        XCTAssertEqual(completed[0].resistanceLevel, 4)
        XCTAssertEqual(completed.map(\.cardioNotes), ["Steady effort", "Intervals"])
        XCTAssertEqual(completed.map(\.isCompleted), [true, true])

        let completedDrafts = completed.map(WorkoutCardioBlockDraft.init(model:))
        XCTAssertEqual(completedDrafts.map(\.timerState), [.idle, .idle])
        XCTAssertEqual(completedDrafts.map(\.timerSegmentStartedAt), [nil, nil])
        XCTAssertEqual(completedDrafts.map(\.timerAccumulatedSeconds), [0, 0])
    }

    func testWorkoutTemplateSyncPreservesSameRoleActivityIdentityAndPlanFields() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(
            modelContext: context,
            weeklyGoalWidgetPublisher: nil
        )
        let template = try templateRepository.createTemplate(name: "Cardio Sync", notes: "Original")
        let treadmill = TemplateCardioBlockDraft.fixture(
            role: .main,
            sortOrder: 0,
            name: "Treadmill Walk",
            trackingProfile: .treadmill,
            goalKind: .distance,
            targetDurationSeconds: 0,
            targetDistanceMeters: 5_000,
            preferredDistanceUnit: .kilometers
        )
        try templateRepository.setCardioActivities(templateID: template.id, drafts: [treadmill])
        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        let persistedTreadmill = try XCTUnwrap(
            try sessionRepository.sessionCardioBlocks(sessionID: session.id).first
        )
        persistedTreadmill.actualDurationSeconds = 1_800
        persistedTreadmill.actualDistanceMeters = 6_200

        let sessionAddedID = UUID()
        let bike = WorkoutSessionCardioBlock(
            id: sessionAddedID,
            sessionID: session.id,
            phase: .preWorkout,
            role: .main,
            sortOrder: 1,
            catalogExerciseUUID: "seed-bike",
            exerciseNameSnapshot: "Bike",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            trackingProfile: .machineDistance,
            goalKind: .time,
            targetDurationSeconds: 1_200,
            targetDistanceMeters: 8_000,
            actualDurationSeconds: 1_100,
            actualDistanceMeters: 9_000,
            preferredDistanceUnit: .miles,
            inclinePercent: 2,
            resistanceLevel: 7,
            cardioNotes: "Session-only result",
            isCompleted: true,
            session: session
        )
        context.insert(bike)
        session.cardioBlocks = [persistedTreadmill, bike]
        session.notes = "Updated"
        try context.save()

        let syncService = WorkoutTemplateSyncService(modelContext: context)
        let preview = try XCTUnwrap(syncService.previewTemplateUpdate(forSessionID: session.id))
        try syncService.applyTemplateUpdate(preview)

        let synced = try templateRepository.cardioActivities(templateID: template.id)
        XCTAssertEqual(synced.map(\.exerciseNameSnapshot), ["Treadmill Walk", "Bike"])
        guard synced.count == 2 else {
            return
        }
        XCTAssertEqual(synced.map(\.role), [.main, .main])
        XCTAssertEqual(synced.map(\.sortOrder), [0, 1])
        XCTAssertEqual(synced[0].id, treadmill.id)
        XCTAssertNotEqual(synced[1].id, sessionAddedID)
        XCTAssertEqual(synced.map(\.trackingProfile), [.treadmill, .machineDistance])
        XCTAssertEqual(synced.map(\.goalKind), [.distance, .time])
        XCTAssertEqual(synced.map(\.targetDurationSeconds), [0, 1_200])
        XCTAssertEqual(synced.map(\.targetDistanceMeters), [5_000, 8_000])
        XCTAssertEqual(synced.map(\.preferredDistanceUnit), [.kilometers, .miles])
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try AppSchema.makeInMemoryContainer(name: "WorkoutCardioPersistenceTests")
    }

    private func completedCardioOrder(
        _ lhs: WorkoutSessionCardioBlock,
        _ rhs: WorkoutSessionCardioBlock
    ) -> Bool {
        if lhs.role.sortOrder != rhs.role.sortOrder {
            return lhs.role.sortOrder < rhs.role.sortOrder
        }
        return lhs.sortOrder < rhs.sortOrder
    }
}

private extension TemplateCardioBlockDraft {
    static func fixture(
        role: WorkoutCardioRole,
        sortOrder: Int,
        name: String,
        trackingProfile: WorkoutCardioTrackingProfile = .timeOnly,
        goalKind: WorkoutCardioGoalKind = .time,
        targetDurationSeconds: Int = 600,
        targetDistanceMeters: Double? = nil,
        preferredDistanceUnit: WorkoutDistanceUnit? = nil
    ) -> TemplateCardioBlockDraft {
        TemplateCardioBlockDraft(
            phase: role == .finisher ? .postWorkout : .preWorkout,
            role: role,
            sortOrder: sortOrder,
            catalogExerciseUUID: "seed-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
            exerciseNameSnapshot: name,
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Full Body",
            trackingProfile: trackingProfile,
            goalKind: goalKind,
            targetDurationSeconds: targetDurationSeconds,
            targetDistanceMeters: targetDistanceMeters,
            preferredDistanceUnit: preferredDistanceUnit
        )
    }
}
