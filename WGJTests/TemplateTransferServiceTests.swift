import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class TemplateTransferServiceTests: XCTestCase {
    func testCustomLoadMeaningSurvivesTransferAndWorkoutLogging() throws {
        for kind in ExerciseLoadKind.allCases {
            let source = ModelContext(try makeInMemoryContainer())
            source.autosaveEnabled = false
            let exercise = ExerciseCatalogItem(remoteUUID: "shared-custom", displayName: "Custom Pull",
                categoryName: "Back", loadTrackingRaw: kind.rawValue, sourceName: "custom")
            source.insert(exercise)
            let muscle = MuscleGroup(remoteID: 4, name: "Back", nameEn: "Back")
            source.insert(muscle)
            exercise.primaryMuscles = [muscle]
            let templates = TemplateRepository(modelContext: source)
            let template = try templates.createTemplate(name: "Shared Plan", notes: "")
            var draft = TemplateExerciseDraft(selection: ExerciseCatalogSelection(catalogItem: exercise), preferredLoadUnit: .kg)
            draft.setDrafts = [.init(targetReps: 8, targetWeight: 30, loadUnit: .kg)]
            try templates.importExercises(templateID: template.id, drafts: [draft])
            let exporter = TemplateTransferService(modelContext: source)
            let data = try exporter.exportData(templateID: template.id)
            let text = String(decoding: try exporter.exportData(templateID: template.id, format: .text), as: UTF8.self)
            XCTAssertTrue(text.contains("Weight means: \(kind.title)"))

            let destination = ModelContext(try makeInMemoryContainer())
            destination.autosaveEnabled = false
            let imported = try TemplateTransferService(modelContext: destination).importTemplate(from: data)
            let importedExercises = try TemplateRepository(modelContext: destination).exercises(in: imported.id)
            let id = try XCTUnwrap(importedExercises.first?.catalogExerciseUUID)
            let catalog = try XCTUnwrap(ExerciseCatalogRepository(modelContext: destination).exerciseMap(for: [id])[id])
            XCTAssertEqual(catalog.loadKind, kind)
            XCTAssertEqual(TrainingGuidanceCatalogSnapshot(exercise: catalog).loadKind, kind)

            let sessions = WorkoutSessionRepository(modelContext: destination)
            let session = try sessions.createSessionFromTemplate(templateID: imported.id)
            let sessionExercise = try XCTUnwrap(sessions.sessionExercises(sessionID: session.id).first)
            let set = try XCTUnwrap(sessions.sessionSets(sessionExerciseID: sessionExercise.id).first)
            set.actualWeight = 30
            set.actualLoadUnit = .kg
            set.actualReps = 8
            set.isCompleted = true
            session.status = .completed
            session.endedAt = .now
            try destination.saveWithRecoveryProtection()
            let metrics = WorkoutMetricsService(modelContext: destination)
            XCTAssertEqual(try metrics.totalVolume(sessionID: session.id), kind == .assistance ? 0 : 240)
            let progress = try XCTUnwrap(metrics.exerciseProgressDataset(for: id))
            XCTAssertEqual(progress.usesAssistance, kind == .assistance)
            XCTAssertEqual(progress.usesAddedWeight, kind == .addedWeight)
            XCTAssertEqual(try metrics.bestEstimatedOneRepMax(for: id) == nil, kind != .resistance)
            let expectedMuscles = WorkoutMuscleHeatmapBuilder.scores(forCatalogExerciseUUID: id,
                catalogMappings: [:], fallbackMuscleSummary: "Back")
            XCTAssertFalse(expectedMuscles.isEmpty)
            let completion = try XCTUnwrap(WorkoutCompletionSnapshotBuilder.build(sessionID: session.id, modelContext: destination))
            let history = try HistoryDetailSnapshotBuilder.load(modelContext: destination, sessionID: session.id)
            let profile = try metrics.profileDashboardSnapshot()
            for entries in [completion.muscleHeatmap.entries, history.muscleHeatmap.entries, profile.weeklyMuscleHeatmap.entries] {
                XCTAssertEqual(Dictionary(uniqueKeysWithValues: entries.map { ($0.region, $0.score) }), expectedMuscles)
            }
            XCTAssertEqual(try UserDataCloudBackupPayload(context: destination).customExercises
                .first { $0.remoteUUID == id }?.loadTrackingRaw, kind.rawValue)
        }
    }

    func testImportingLoadMetadataRebuildsLegacyHistoryForTemplatesAndFolders() throws {
        for importFolder in [false, true] {
            let source = ModelContext(try makeInMemoryContainer())
            source.autosaveEnabled = false
            let templates = TemplateRepository(modelContext: source)
            let folder = try templates.createFolder(name: "Shared Folder")
            let template = try templates.createTemplate(folderID: folder.id, name: "Shared Plan", notes: "")
            let id = "custom-legacy-pull"
            let draft = TemplateExerciseDraft(catalogExerciseUUID: id, exerciseNameSnapshot: "Custom Pull",
                categorySnapshot: "Back", muscleSummarySnapshot: "Back", notes: "", targetRepMin: nil,
                targetRepMax: nil, restSeconds: 120, setDrafts: [.init(targetReps: 8, targetWeight: 40, loadUnit: .kg)])
            try templates.importExercises(templateID: template.id, drafts: [draft])
            let exporter = TemplateTransferService(modelContext: source)
            let oldEnvelope = try makeDecoder().decode(TemplateTransferEnvelope.self, from: exporter.exportData(templateID: template.id))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let legacyData = try encoder.encode(TemplateTransferEnvelope(formatVersion: 7, artifact: oldEnvelope.artifact))

            let destination = ModelContext(try makeInMemoryContainer())
            destination.autosaveEnabled = false
            let importer = TemplateTransferService(modelContext: destination)
            let imported = try importer.importTemplate(from: legacyData)
            let sessions = WorkoutSessionRepository(modelContext: destination)
            var completed: [WorkoutSession] = []
            for index in 0..<2 {
                let session = try sessions.createSessionFromTemplate(templateID: imported.id)
                let exercise = try XCTUnwrap(sessions.sessionExercises(sessionID: session.id).first)
                let set = try XCTUnwrap(sessions.sessionSets(sessionExerciseID: exercise.id).first)
                set.actualWeight = index == 0 ? 40 : 50
                set.actualLoadUnit = .kg
                set.actualReps = index == 0 ? 8 : 12
                set.isCompleted = true
                session.startedAt = Date().addingTimeInterval(Double(index - 2) * 86_400)
                session.endedAt = session.startedAt.addingTimeInterval(3600)
                session.status = .completed
                completed.append(session)
            }
            try destination.saveWithRecoveryProtection()
            _ = try sessions.backfillCompletedSessionSummariesIfNeeded()
            let metrics = WorkoutMetricsService(modelContext: destination)
            XCTAssertEqual(completed.map(\.totalVolume), [320, 600])
            XCTAssertEqual(completed.map(\.prHitsCount), [1, 1])
            XCTAssertNotNil(try metrics.personalRecords().first?.estimatedOneRepMax)

            source.insert(ExerciseCatalogItem(remoteUUID: id, displayName: "Custom Pull", categoryName: "Back",
                loadTrackingRaw: "assistance", sourceName: "custom"))
            try source.saveWithRecoveryProtection()
            let data = try importFolder ? exporter.exportData(folderID: folder.id, format: .bundle)
                : exporter.exportData(templateID: template.id)
            _ = try importer.importTransfer(from: data)
            XCTAssertEqual(completed.map(\.totalVolume), [0, 0])
            XCTAssertEqual(completed.map(\.prHitsCount), [1, 0])
            let record = try XCTUnwrap(metrics.personalRecords().first)
            XCTAssertTrue(record.usesAssistance)
            XCTAssertNil(record.estimatedOneRepMax)
            XCTAssertEqual(record.weight, 40)
            XCTAssertEqual(try metrics.profileDashboardSnapshot().overviewStats.totalPRHits, 1)
            XCTAssertFalse(destination.hasChanges)
            let dates = completed.map(\.updatedAt)
            _ = try importer.importTransfer(from: data)
            XCTAssertEqual(completed.map(\.updatedAt), dates)
        }
    }

    func testTransferredLoadMeaningDoesNotOverwriteConflictingLocalExerciseAndSurvivesRotation() throws {
        let source = ModelContext(try makeInMemoryContainer())
        source.autosaveEnabled = false
        let assisted = ExerciseCatalogItem(remoteUUID: "same-id", displayName: "Custom Pull", categoryName: "Back",
            loadTrackingRaw: "assistance", sourceName: "custom")
        let added = ExerciseCatalogItem(remoteUUID: "alternative-id", displayName: "Custom Dip", categoryName: "Arms",
            loadTrackingRaw: "addedWeight", sourceName: "custom")
        source.insert(assisted)
        source.insert(added)
        let templates = TemplateRepository(modelContext: source)
        let template = try templates.createTemplate(name: "Rotation", notes: "")
        var draft = TemplateExerciseDraft(selection: ExerciseCatalogSelection(catalogItem: assisted), preferredLoadUnit: .kg)
        draft.components = [TemplateExerciseComponentDraft(catalogItem: assisted), TemplateExerciseComponentDraft(catalogItem: added)]
        try templates.importExercises(templateID: template.id, drafts: [draft])
        let data = try TemplateTransferService(modelContext: source).exportData(templateID: template.id)

        let destination = ModelContext(try makeInMemoryContainer())
        destination.autosaveEnabled = false
        let local = ExerciseCatalogItem(remoteUUID: "same-id", displayName: "Custom Pull", categoryName: "Back",
            loadTrackingRaw: "resistance", sourceName: "custom")
        destination.insert(local)
        try destination.saveWithRecoveryProtection()
        let importer = TemplateTransferService(modelContext: destination)
        let first = try importer.importTemplate(from: data)
        let second = try importer.importTemplate(from: data)
        let importedTemplates = TemplateRepository(modelContext: destination)
        let firstRow = try XCTUnwrap(importedTemplates.exercises(in: first.id).first)
        let secondRow = try XCTUnwrap(importedTemplates.exercises(in: second.id).first)
        XCTAssertNotEqual(firstRow.catalogExerciseUUID, local.remoteUUID)
        XCTAssertEqual(firstRow.catalogExerciseUUID, secondRow.catalogExerciseUUID)
        XCTAssertEqual(local.loadKind, .resistance)
        let components = try importedTemplates.components(for: firstRow.id)
        XCTAssertEqual(components.count, 2)
        let catalog = try ExerciseCatalogRepository(modelContext: destination).exerciseMap(for: components.map(\.catalogExerciseUUID))
        XCTAssertEqual(components.compactMap { catalog[$0.catalogExerciseUUID]?.loadKind }, [.assistance, .addedWeight])
        let reexported = try TemplateTransferService(modelContext: destination).exportData(templateID: first.id)
        let envelope = try makeDecoder().decode(TemplateTransferEnvelope.self, from: reexported)
        guard case let .template(transferred) = envelope.artifact else { return XCTFail("Expected template") }
        XCTAssertEqual(transferred.exercises.first?.loadKind, .assistance)
        XCTAssertEqual(transferred.exercises.first?.components?.compactMap(\.loadKind), [.assistance, .addedWeight])
    }

    func testRepeatedExportsKeepEarlierSharedFileIntact() throws {
        let context = ModelContext(try makeInMemoryContainer())
        context.autosaveEnabled = false
        let template = WorkoutTemplate(folderID: TemplateRepository.unfiledFolderID, name: "Same Name")
        context.insert(template)
        try context.save()
        let service = TemplateTransferService(modelContext: context)
        let firstURL = try service.writeExportFile(templateID: template.id)
        defer { try? FileManager.default.removeItem(at: firstURL.deletingLastPathComponent()) }
        let original = try Data(contentsOf: firstURL)
        template.notes = "Changed after the first share sheet opened"
        try context.save()
        let secondURL = try service.writeExportFile(templateID: template.id)
        defer { try? FileManager.default.removeItem(at: secondURL.deletingLastPathComponent()) }
        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(firstURL.lastPathComponent, secondURL.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: firstURL), original)
        XCTAssertNotEqual(try Data(contentsOf: secondURL), original)
    }

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
        sourceContext.insert(template)
        sourceContext.insert(first)
        sourceContext.insert(second)
        template.cardioBlocks = [first, second]
        try sourceContext.save()

        let exported = try TemplateTransferService(modelContext: sourceContext)
            .exportData(templateID: template.id)
        let decoded = try makeDecoder().decode(TemplateTransferEnvelope.self, from: exported)
        XCTAssertEqual(decoded.formatVersion, 8)
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

    func testPlainTextExportHandlesDistanceBeyondIntegerRange() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let repository = TemplateRepository(modelContext: context)
        let template = try repository.createTemplate(name: "Distance", notes: "")
        try repository.setCardioActivities(templateID: template.id, drafts: [
            cardioDraft(name: "Run", role: .main, order: 0, goal: .distance, distance: 1e25, unit: .kilometers),
        ])
        let data = try TemplateTransferService(modelContext: context)
            .exportData(templateID: template.id, format: .text)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("Goal: \(String(WorkoutDistanceUnit.kilometers.value(fromMeters: 1e25))) km"))
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
