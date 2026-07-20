import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class TemplateTransferServiceTests: XCTestCase {
    func testTemplateRepositoryDoesNotExposeDeprecatedPhaseAdapters() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("WGJ/Services/TemplateRepository.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("func cardioBlocks(templateID:"))
        XCTAssertFalse(source.contains("func setCardioBlocks(templateID:"))
    }

    func testFlexibleCardioRoundTripPreservesOrderedPlansAndCanonicalDistance() throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        sourceContext.autosaveEnabled = false
        let template = WorkoutTemplate(
            folderID: TemplateRepository.unfiledFolderID,
            name: "Cardio Mix"
        )
        let originalMeters = 1_234.567_890_123_456_7
        let first = TemplateCardioBlock(
            templateID: template.id,
            phase: .preWorkout,
            role: .main,
            sortOrder: 0,
            catalogExerciseUUID: "custom-row",
            exerciseNameSnapshot: "Row",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Full Body",
            trackingProfile: .rower,
            goalKind: .time,
            targetDurationSeconds: 900,
            preferredDistanceUnit: .meters,
            template: template
        )
        let second = TemplateCardioBlock(
            templateID: template.id,
            phase: .preWorkout,
            role: .main,
            sortOrder: 1,
            catalogExerciseUUID: "custom-run",
            exerciseNameSnapshot: "Run",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            trackingProfile: .walkRun,
            goalKind: .distance,
            targetDurationSeconds: 0,
            targetDistanceMeters: originalMeters,
            preferredDistanceUnit: .miles,
            template: template
        )
        template.cardioBlocks = [first, second]
        sourceContext.insert(template)
        sourceContext.insert(first)
        sourceContext.insert(second)
        try sourceContext.save()

        let exported = try TemplateTransferService(modelContext: sourceContext)
            .exportData(templateID: template.id)
        let decoded = try makeDecoder().decode(TemplateTransferEnvelope.self, from: exported)
        XCTAssertEqual(decoded.formatVersion, 7)
        guard case .template(let transferred) = decoded.artifact else {
            return XCTFail("Expected a template transfer")
        }
        XCTAssertNil(transferred.preWorkoutCardio)
        XCTAssertNil(transferred.postWorkoutCardio)
        XCTAssertEqual(transferred.cardioActivities?.map(\.role), [.main, .main])
        XCTAssertEqual(transferred.cardioActivities?.map(\.sortOrder), [0, 1])
        XCTAssertEqual(transferred.cardioActivities?.map(\.goalKind), [.time, .distance])
        XCTAssertEqual(transferred.cardioActivities?.last?.targetDistanceMeters, originalMeters)
        XCTAssertEqual(transferred.cardioActivities?.last?.preferredDistanceUnit, .miles)

        let destinationContainer = try makeInMemoryContainer()
        let destinationContext = ModelContext(destinationContainer)
        destinationContext.autosaveEnabled = false
        let imported = try TemplateTransferService(modelContext: destinationContext)
            .importTemplate(from: exported)
        let repository = TemplateRepository(modelContext: destinationContext)
        let restored = try repository.cardioActivities(templateID: imported.id)

        XCTAssertEqual(restored.map(\.role), [.main, .main])
        XCTAssertEqual(restored.map(\.sortOrder), [0, 1])
        XCTAssertEqual(restored.map(\.trackingProfile), [.rower, .walkRun])
        XCTAssertEqual(restored.map(\.goalKind), [.time, .distance])
        XCTAssertEqual(restored.map(\.targetDurationSeconds), [900, 0])
        XCTAssertEqual(restored.map(\.targetDistanceMeters), [nil, originalMeters])
        XCTAssertEqual(restored.map(\.preferredDistanceUnit), [.meters, .miles])

        let importedDistance = try XCTUnwrap(restored.last)
        let setupDraft = WorkoutCardioSetupDraft(templateCardio: TemplateCardioBlockDraft(model: importedDistance))
        let unchangedSetup = try WorkoutCardioSetupValidator.validated(setupDraft)
        let unchangedDraft = TemplateCardioBlockDraft(
            id: importedDistance.id,
            phase: TemplateCardioDraftReducer.legacyPhase(for: unchangedSetup.role),
            role: unchangedSetup.role,
            sortOrder: importedDistance.sortOrder,
            catalogExerciseUUID: importedDistance.catalogExerciseUUID,
            exerciseNameSnapshot: importedDistance.exerciseNameSnapshot,
            categorySnapshot: importedDistance.categorySnapshot,
            muscleSummarySnapshot: importedDistance.muscleSummarySnapshot,
            trackingProfile: unchangedSetup.trackingProfile,
            goalKind: unchangedSetup.goalKind,
            targetDurationSeconds: unchangedSetup.targetDurationSeconds,
            targetDistanceMeters: unchangedSetup.targetDistanceMeters,
            preferredDistanceUnit: unchangedSetup.preferredDistanceUnit
        )
        try repository.setCardioActivities(templateID: imported.id, drafts: [
            TemplateCardioBlockDraft(model: restored[0]),
            unchangedDraft,
        ])

        XCTAssertEqual(
            try repository.cardioActivities(templateID: imported.id).last?.targetDistanceMeters,
            originalMeters
        )
    }

    func testLegacyPreAndPostFixtureImportsWithRoleFallback() throws {
        let versionFive = Data(
            """
            {
              "formatVersion": 5,
              "exportedAt": "2026-07-20T12:00:00Z",
              "template": {
                "name": "Legacy Cardio",
                "notes": "",
                "preWorkoutCardio": {
                  "catalogExerciseUUID": "legacy-walk",
                  "exerciseNameSnapshot": "Walk",
                  "categorySnapshot": "Cardio",
                  "muscleSummarySnapshot": "Legs",
                  "targetDurationSeconds": 300
                },
                "postWorkoutCardio": {
                  "catalogExerciseUUID": "legacy-bike",
                  "exerciseNameSnapshot": "Bike",
                  "categorySnapshot": "Cardio",
                  "muscleSummarySnapshot": "Legs",
                  "targetDurationSeconds": 600
                },
                "exercises": []
              }
            }
            """.utf8
        )
        let versionSix = Data(
            """
            {
              "formatVersion": 6,
              "exportedAt": "2026-07-20T12:00:00Z",
              "artifact": {
                "kind": "template",
                "template": {
                  "name": "Legacy Cardio",
                  "notes": "",
                  "preWorkoutCardio": {
                    "catalogExerciseUUID": "legacy-walk",
                    "exerciseNameSnapshot": "Walk",
                    "categorySnapshot": "Cardio",
                    "muscleSummarySnapshot": "Legs",
                    "targetDurationSeconds": 300
                  },
                  "postWorkoutCardio": {
                    "catalogExerciseUUID": "legacy-bike",
                    "exerciseNameSnapshot": "Bike",
                    "categorySnapshot": "Cardio",
                    "muscleSummarySnapshot": "Legs",
                    "targetDurationSeconds": 600
                  },
                  "exercises": []
                }
              }
            }
            """.utf8
        )

        for data in [versionFive, versionSix] {
            let container = try makeInMemoryContainer()
            let context = ModelContext(container)
            let imported = try TemplateTransferService(modelContext: context).importTemplate(from: data)
            let activities = try TemplateRepository(modelContext: context)
                .cardioActivities(templateID: imported.id)

            XCTAssertEqual(activities.map(\.role), [.warmUp, .finisher])
            XCTAssertEqual(activities.map(\.sortOrder), [0, 0])
            XCTAssertEqual(activities.map(\.goalKind), [.time, .time])
            XCTAssertEqual(activities.map(\.targetDurationSeconds), [300, 600])
        }
    }

    func testPlainTextExportGroupsRolesAndPrintsOnlyConfiguredGoal() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let repository = TemplateRepository(modelContext: context)
        let template = try repository.createTemplate(name: "Race Day", notes: "")
        try repository.setCardioActivities(templateID: template.id, drafts: [
            cardioDraft(name: "Walk", role: .warmUp, order: 0, goal: .time, duration: 300),
            cardioDraft(name: "Run", role: .main, order: 0, goal: .distance, distance: 5_000, unit: .kilometers),
            cardioDraft(name: "Stretch", role: .finisher, order: 0, goal: .open),
        ])

        let data = try TemplateTransferService(modelContext: context)
            .exportData(templateID: template.id, format: .text)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains("Warm-up\nExercise: Walk\nGoal: 5:00"))
        XCTAssertTrue(text.contains("Main cardio\nExercise: Run\nGoal: 5 km"))
        XCTAssertTrue(text.contains("Finisher\nExercise: Stretch\nGoal: Open"))
        XCTAssertFalse(text.contains("Duration: 0s"))
        XCTAssertFalse(text.contains("Distance: 0"))
    }

    private func cardioDraft(
        name: String,
        role: WorkoutCardioRole,
        order: Int,
        goal: WorkoutCardioGoalKind,
        duration: Int = 0,
        distance: Double? = nil,
        unit: WorkoutDistanceUnit? = nil
    ) -> TemplateCardioBlockDraft {
        TemplateCardioBlockDraft(
            phase: TemplateCardioDraftReducer.legacyPhase(for: role),
            role: role,
            sortOrder: order,
            catalogExerciseUUID: "custom-\(name.lowercased())",
            exerciseNameSnapshot: name,
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Full Body",
            trackingProfile: .walkRun,
            goalKind: goal,
            targetDurationSeconds: duration,
            targetDistanceMeters: distance,
            preferredDistanceUnit: unit
        )
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try AppSchema.makeInMemoryContainer(name: "TemplateTransferServiceTests-\(UUID().uuidString)")
    }
}
