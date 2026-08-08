import os
import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class TemplateEditorPersistenceTests: XCTestCase {
    func testTemplateEditorSaveCommitsCreatedTemplate() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let request = TemplateEditorSaveRequest(
            folderID: nil,
            templateID: nil,
            name: "Upper",
            notes: "",
            exerciseDrafts: [],
            cardioDrafts: []
        )

        _ = try TemplateEditorPersistence.save(request, modelContext: context)

        let verificationContext = ModelContext(container)
        XCTAssertEqual(
            try verificationContext.fetch(FetchDescriptor<WorkoutTemplate>()).map(\.name),
            ["Upper"]
        )
    }

    func testTemplateEditorSavePublishesBoundaryEffectsExactlyOnce() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let recorder = OSAllocatedUnfairLock(
            initialState: (libraryChanges: 0, backupReasons: [BoundaryCloudBackupReason]())
        )
        let effects = TemplateSaveBoundaryEffects(
            postLibraryChange: {
                recorder.withLock { state in
                    state.libraryChanges += 1
                }
            },
            scheduleBackup: { _, reason in
                recorder.withLock { state in
                    state.backupReasons.append(reason)
                }
            }
        )

        _ = try TemplateEditorPersistence.save(
            makeRequest(name: "Upper"),
            modelContext: context,
            boundaryEffects: effects
        )

        let recorded = recorder.withLock { $0 }
        XCTAssertEqual(recorded.libraryChanges, 1)
        XCTAssertEqual(recorded.backupReasons, [.templateSaved])
    }

    func testTemplateEditorSavePersistsMultipleActivitiesInOneRole() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let request = TemplateEditorSaveRequest(
            folderID: nil,
            templateID: nil,
            name: "Cardio",
            notes: "",
            exerciseDrafts: [],
            cardioDrafts: [
                TemplateCardioBlockDraft(
                    phase: .preWorkout,
                    role: .main,
                    sortOrder: 0,
                    catalogExerciseUUID: "seed-treadmill-walk",
                    exerciseNameSnapshot: "Treadmill Walk",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Legs",
                    trackingProfile: .treadmill,
                    goalKind: .distance,
                    targetDurationSeconds: 0,
                    targetDistanceMeters: 5_000,
                    preferredDistanceUnit: .kilometers
                ),
                TemplateCardioBlockDraft(
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
                    preferredDistanceUnit: .kilometers
                ),
            ]
        )

        _ = try TemplateEditorPersistence.save(request, modelContext: context)

        let verificationContext = ModelContext(container)
        let activities = try verificationContext.fetch(FetchDescriptor<TemplateCardioBlock>())
            .sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(activities.map(\.id), request.cardioDrafts.map(\.id))
        XCTAssertEqual(activities.map(\.exerciseNameSnapshot), ["Treadmill Walk", "Bike"])
        XCTAssertEqual(activities.map(\.role), [.main, .main])
        XCTAssertEqual(activities.map(\.sortOrder), [0, 1])
    }

    func testTemplateEditorUpdatePersistsWholeOrderedActivityCollection() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let initialMainID = UUID()
        let removedWarmUpID = UUID()
        let created = try XCTUnwrap(savedTemplate(from: try TemplateEditorPersistence.save(
            TemplateEditorSaveRequest(
                folderID: nil,
                templateID: nil,
                name: "Cardio",
                notes: "",
                exerciseDrafts: [],
                cardioDrafts: [
                    cardioDraft(id: removedWarmUpID, role: .warmUp, sortOrder: 0, name: "Walk"),
                    cardioDraft(id: initialMainID, role: .main, sortOrder: 0, name: "Run"),
                ]
            ),
            modelContext: context
        )))
        let addedMainID = UUID()

        _ = try TemplateEditorPersistence.save(
            TemplateEditorSaveRequest(
                folderID: nil,
                templateID: created.templateID,
                name: "Cardio",
                notes: "",
                exerciseDrafts: [],
                cardioDrafts: [
                    cardioDraft(id: addedMainID, role: .main, sortOrder: 0, name: "Bike"),
                    cardioDraft(id: initialMainID, role: .main, sortOrder: 1, name: "Run"),
                ]
            ),
            modelContext: context
        )

        let activities = try TemplateRepository(modelContext: context)
            .cardioActivities(templateID: created.templateID)
        XCTAssertEqual(activities.map(\.id), [addedMainID, initialMainID])
        XCTAssertEqual(activities.map(\.sortOrder), [0, 1])
        XCTAssertFalse(activities.contains(where: { $0.id == removedWarmUpID }))
    }

    func testCardioDraftReducerAppendsAtEndOfRoleAndNormalizesEveryRole() {
        let warmUp = cardioDraft(id: UUID(), role: .warmUp, sortOrder: 8, name: "Walk")
        let firstMain = cardioDraft(id: UUID(), role: .main, sortOrder: 4, name: "Run")
        let appendedMain = cardioDraft(id: UUID(), role: .main, sortOrder: 0, name: "Bike")

        let result = TemplateCardioDraftReducer.appending(
            appendedMain,
            to: [firstMain, warmUp]
        )

        XCTAssertEqual(result.map(\.id), [warmUp.id, firstMain.id, appendedMain.id])
        XCTAssertEqual(result.map(\.sortOrder), [0, 0, 1])
    }

    func testCardioDraftReducerRoleChangeAppendsWithStableID() {
        var moved = cardioDraft(id: UUID(), role: .warmUp, sortOrder: 0, name: "Walk")
        let existingFinisher = cardioDraft(id: UUID(), role: .finisher, sortOrder: 0, name: "Run")
        moved.role = .finisher
        moved.sortOrder = 0

        let result = TemplateCardioDraftReducer.updating(
            moved,
            in: [movedWithRole(moved, role: .warmUp), existingFinisher]
        )

        XCTAssertEqual(result.map(\.id), [existingFinisher.id, moved.id])
        XCTAssertEqual(result.map(\.sortOrder), [0, 1])
        XCTAssertEqual(result.map(\.role), [.finisher, .finisher])
    }

    func testCardioDraftReducerSameRoleUpdateKeepsItsPosition() {
        let first = cardioDraft(id: UUID(), role: .main, sortOrder: 0, name: "Walk")
        var updated = cardioDraft(id: UUID(), role: .main, sortOrder: 1, name: "Run")
        let last = cardioDraft(id: UUID(), role: .main, sortOrder: 2, name: "Bike")
        updated.targetDurationSeconds = 1_200

        let result = TemplateCardioDraftReducer.updating(updated, in: [first, updated, last])

        XCTAssertEqual(result.map(\.id), [first.id, updated.id, last.id])
        XCTAssertEqual(result.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(result[1].targetDurationSeconds, 1_200)
    }

    func testCardioDraftReducerMovesWithinRoleAndPreservesIDs() {
        let first = cardioDraft(id: UUID(), role: .main, sortOrder: 0, name: "Walk")
        let second = cardioDraft(id: UUID(), role: .main, sortOrder: 1, name: "Run")
        let third = cardioDraft(id: UUID(), role: .main, sortOrder: 2, name: "Bike")

        let result = TemplateCardioDraftReducer.moving(
            activityID: third.id,
            direction: .up,
            in: [first, second, third]
        )

        XCTAssertEqual(result.map(\.id), [first.id, third.id, second.id])
        XCTAssertEqual(result.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(Set(result.map(\.id)), Set([first.id, second.id, third.id]))
    }

    func testCardioDraftReducerRemovesByIDAndNormalizesRoleOrder() {
        let first = cardioDraft(id: UUID(), role: .main, sortOrder: 0, name: "Walk")
        let removed = cardioDraft(id: UUID(), role: .main, sortOrder: 1, name: "Run")
        let last = cardioDraft(id: UUID(), role: .main, sortOrder: 2, name: "Bike")

        let result = TemplateCardioDraftReducer.removing(
            activityID: removed.id,
            from: [first, removed, last]
        )

        XCTAssertEqual(result.map(\.id), [first.id, last.id])
        XCTAssertEqual(result.map(\.sortOrder), [0, 1])
    }

    private func makeRequest(name: String) -> TemplateEditorSaveRequest {
        TemplateEditorSaveRequest(
            folderID: nil,
            templateID: nil,
            name: name,
            notes: "",
            exerciseDrafts: [],
            cardioDrafts: []
        )
    }

    private func savedTemplate(
        from operation: TemplateEditorSaveOperationResult
    ) -> TemplateEditorSaveResult? {
        guard case .saved(let result) = operation else { return nil }
        return result
    }

    private func cardioDraft(
        id: UUID,
        role: WorkoutCardioRole,
        sortOrder: Int,
        name: String
    ) -> TemplateCardioBlockDraft {
        TemplateCardioBlockDraft(
            id: id,
            phase: role == .finisher ? .postWorkout : .preWorkout,
            role: role,
            sortOrder: sortOrder,
            catalogExerciseUUID: "seed-\(name.lowercased())",
            exerciseNameSnapshot: name,
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "",
            trackingProfile: .machineDistance,
            goalKind: .time,
            targetDurationSeconds: 600,
            preferredDistanceUnit: .kilometers
        )
    }

    private func movedWithRole(
        _ draft: TemplateCardioBlockDraft,
        role: WorkoutCardioRole
    ) -> TemplateCardioBlockDraft {
        var copy = draft
        copy.role = role
        copy.phase = role == .finisher ? .postWorkout : .preWorkout
        return copy
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            TemplateSupersetGroup.self,
            TemplateExerciseDropStage.self,
        ])
        let configuration = ModelConfiguration(
            "TemplateEditorTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
