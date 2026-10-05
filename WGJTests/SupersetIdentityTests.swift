import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class SupersetIdentityTests: XCTestCase {
    func testLegacyGroupRepairKeepsLatestRestSettingRegardlessOfRecordOrder() throws {
        let context = ModelContext(try AppSchema.makeInMemoryContainer())
        context.autosaveEnabled = false
        let template = try makeTemplate(context)
        let session = try ActiveWorkoutSessionFactory(modelContext: context).createSessionFromTemplate(templateID: template.id)
        try WorkoutCompletionRepository(modelContext: context, boundaryEffects: .init(scheduleBackup: { _, _ in }))
            .completeWorkout(session: session)
        let original = try UserDataCloudBackupPayload(context: context)
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        for reversed in [false, true] {
            var payload = original
            var oldTemplate = try XCTUnwrap(payload.templateSupersetGroups?.first)
            oldTemplate.roundRestSeconds = 75
            oldTemplate.updatedAt = oldDate
            var latestTemplate = oldTemplate
            latestTemplate.roundRestSeconds = 120
            latestTemplate.updatedAt = oldDate.addingTimeInterval(10)
            var oldWorkout = try XCTUnwrap(payload.workoutSupersetGroups?.first)
            oldWorkout.roundRestSeconds = 75
            oldWorkout.updatedAt = oldDate
            var latestWorkout = oldWorkout
            latestWorkout.roundRestSeconds = 90
            latestWorkout.updatedAt = oldDate.addingTimeInterval(10)
            payload.templateSupersetGroups = reversed ? [latestTemplate, oldTemplate] : [oldTemplate, latestTemplate]
            payload.workoutSupersetGroups = reversed ? [latestWorkout, oldWorkout] : [oldWorkout, latestWorkout]
            try payload.repairLegacyCopiedIdentities()
            try payload.validate()
            XCTAssertEqual(payload.templateSupersetGroups?.map(\.roundRestSeconds), [120])
            XCTAssertEqual(payload.workoutSupersetGroups?.map(\.roundRestSeconds), [90])
            XCTAssertEqual(try BackupArchiveCodec.json(payload.templateSets), try BackupArchiveCodec.json(original.templateSets))
            XCTAssertEqual(try BackupArchiveCodec.json(payload.workoutSets), try BackupArchiveCodec.json(original.workoutSets))
            let repairedTemplateID = payload.templateSupersetGroups?.first?.id
            let repairedWorkoutID = payload.workoutSupersetGroups?.first?.id
            XCTAssertTrue(payload.templateExercises.allSatisfy { $0.supersetGroupID == repairedTemplateID })
            XCTAssertTrue(payload.workoutExercises.allSatisfy { $0.supersetGroupID == repairedWorkoutID })
            try payload.repairLegacyCopiedIdentities()
            XCTAssertEqual(payload.templateSupersetGroups?.first?.id, repairedTemplateID)
            XCTAssertEqual(payload.workoutSupersetGroups?.first?.id, repairedWorkoutID)
        }
    }

    func testLegacyGroupRepairRejectsConflictingLatestRecordsEvenWithOlderCopies() throws {
        let context = ModelContext(try AppSchema.makeInMemoryContainer())
        _ = try makeTemplate(context)
        var payload = try UserDataCloudBackupPayload(context: context)
        var old = try XCTUnwrap(payload.templateSupersetGroups?.first)
        old.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var latest = old
        latest.updatedAt = old.updatedAt.addingTimeInterval(10)
        latest.roundRestSeconds = 90
        var conflicting = latest
        conflicting.roundRestSeconds = 120
        payload.templateSupersetGroups = [latest, old, conflicting]
        XCTAssertThrowsError(try payload.repairLegacyCopiedIdentities())
        payload.templateSupersetGroups = [latest, old, latest]
        try payload.repairLegacyCopiedIdentities()
        try payload.validate()
        XCTAssertEqual(payload.templateSupersetGroups?.map(\.roundRestSeconds), [90])
    }

    func testNewSupersetUsesOnePersistedObjectAndRepeatedWorkoutsHaveIndependentIDs() throws {
        let context = ModelContext(try AppSchema.makeInMemoryContainer())
        context.autosaveEnabled = false
        let template = try makeTemplate(context)
        let templateGroups = try context.fetch(FetchDescriptor<TemplateSupersetGroup>())
        XCTAssertEqual(templateGroups.count, 1)
        let originalID = try XCTUnwrap(templateGroups.first?.id)
        let factory = ActiveWorkoutSessionFactory(modelContext: context)
        let completion = WorkoutCompletionRepository(modelContext: context,
            boundaryEffects: .init(scheduleBackup: { _, _ in }))
        var runtimeIDs = Set<UUID>()
        for _ in 0..<2 {
            var session = try factory.createSessionFromTemplate(templateID: template.id)
            let groupID = try XCTUnwrap(session.exercises.first?.superset?.groupID)
            XCTAssertNotEqual(groupID, originalID)
            runtimeIDs.insert(groupID)
            // Also exercise completion of snapshots written by older versions.
            for i in session.exercises.indices { session.exercises[i].superset?.groupID = originalID }
            try completion.completeWorkout(session: session)
        }
        XCTAssertEqual(runtimeIDs.count, 2)
        let groups = try context.fetch(FetchDescriptor<WorkoutSessionSupersetGroup>())
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.id)).count, 2)
        XCTAssertFalse(groups.contains { $0.id == originalID })
        try UserDataCloudBackupPayload(context: context).validate()
        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertNil(WorkoutTemplateSyncPreviewBuilder.buildPreview(template: template, session: saved))
        saved.supersetGroups?.first?.roundRestSeconds = 95
        let preview = try XCTUnwrap(WorkoutTemplateSyncPreviewBuilder.buildPreview(template: template, session: saved))
        XCTAssertEqual(Set(preview.mutation.exercises.compactMap { $0.superset?.groupID }), [originalID])
        XCTAssertTrue(preview.editedExercises.allSatisfy { $0.changes.contains { $0.contains("Superset rest") } })

        let repository = templates(context)
        _ = try repository.createTemplate(fromSessionID: saved.id, name: "Copy one")
        _ = try repository.createTemplate(fromSessionID: saved.id, name: "Copy two")
        try UserDataCloudBackupPayload(context: context).validate()
        let legacyRepository = WorkoutSessionRepository(modelContext: context)
        for _ in 0..<2 { _ = try legacyRepository.createSessionFromTemplate(templateID: template.id) }
        let allGroups = try context.fetch(FetchDescriptor<WorkoutSessionSupersetGroup>())
        XCTAssertEqual(allGroups.count, 4)
        XCTAssertEqual(Set(allGroups.map(\.id)).count, 4)
    }

    func testRepeatedImportsRekeySupersetsAndDropsWithoutChangingValues() throws {
        let context = ModelContext(try AppSchema.makeInMemoryContainer())
        context.autosaveEnabled = false
        let original = try makeTemplate(context)
        let transfer = TemplateTransferService(modelContext: context)
        let data = try transfer.exportData(templateID: original.id)
        for _ in 0..<2 { _ = try transfer.importTemplate(from: data) }
        let groups = try context.fetch(FetchDescriptor<TemplateSupersetGroup>())
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(Set(groups.map(\.id)).count, 3)
        let drops = try context.fetch(FetchDescriptor<TemplateExerciseDropStage>())
        XCTAssertEqual(drops.count, 6)
        XCTAssertEqual(Set(drops.map(\.id)).count, 6)
        XCTAssertTrue(drops.allSatisfy { $0.targetReps == 6 && $0.targetWeight == 10 })
        try UserDataCloudBackupPayload(context: context).validate()
    }

    func testLegacyBackupRepairIsOwnerScopedRepeatableAndRejectsAmbiguity() throws {
        let context = ModelContext(try AppSchema.makeInMemoryContainer())
        let template = try makeTemplate(context)
        _ = try makeTemplate(context)
        for _ in 0..<2 {
            let session = try ActiveWorkoutSessionFactory(modelContext: context).createSessionFromTemplate(templateID: template.id)
            try WorkoutCompletionRepository(modelContext: context, boundaryEffects: .init(scheduleBackup: { _, _ in }))
                .completeWorkout(session: session)
        }
        var payload = try UserDataCloudBackupPayload(context: context)
        let oldID = payload.templateSupersetGroups![0].id
        for i in payload.templateSupersetGroups!.indices { payload.templateSupersetGroups![i].id = oldID }
        for i in payload.templateExercises.indices { payload.templateExercises[i].supersetGroupID = oldID }
        payload.templateSupersetGroups!.append(payload.templateSupersetGroups![0])
        let workoutID = payload.workoutSupersetGroups![0].id
        for i in payload.workoutSupersetGroups!.indices { payload.workoutSupersetGroups![i].id = workoutID }
        for i in payload.workoutExercises.indices { payload.workoutExercises[i].supersetGroupID = workoutID }
        let dropID = payload.templateDropStages[0].id
        for i in payload.templateDropStages.indices { payload.templateDropStages[i].id = dropID }
        XCTAssertThrowsError(try payload.validate())
        var ambiguous = payload
        ambiguous.templateSupersetGroups![2].roundRestSeconds += 1
        XCTAssertThrowsError(try ambiguous.repairLegacyCopiedIdentities())
        ambiguous = payload
        ambiguous.templateDropStages.append(payload.templateDropStages[0])
        XCTAssertThrowsError(try ambiguous.repairLegacyCopiedIdentities())
        try payload.repairLegacyCopiedIdentities()
        try payload.validate()
        XCTAssertEqual(payload.templateSupersetGroups?.count, 2)
        XCTAssertEqual(Set(payload.workoutSupersetGroups!.map(\.id)).count, 2)
        XCTAssertEqual(Set(payload.templateDropStages.map(\.id)).count, 4)
        let ids = payload.templateSupersetGroups!.map(\.id)
        try payload.repairLegacyCopiedIdentities()
        XCTAssertEqual(payload.templateSupersetGroups!.map(\.id), ids)
    }

    func testLocalRepairPreservesRelationshipsAndDoesNotRepeatWrites() throws {
        let container = try AppSchema.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let template = try makeTemplate(context)
        _ = try makeTemplate(context)
        for _ in 0..<2 {
            let session = try ActiveWorkoutSessionFactory(modelContext: context).createSessionFromTemplate(templateID: template.id)
            try WorkoutCompletionRepository(modelContext: context, boundaryEffects: .init(scheduleBackup: { _, _ in }))
                .completeWorkout(session: session)
        }
        let workoutGroups = try context.fetch(FetchDescriptor<WorkoutSessionSupersetGroup>())
        let oldWorkoutID = workoutGroups[0].id
        for group in workoutGroups {
            group.id = oldWorkoutID
            for exercise in group.exercises ?? [] { exercise.supersetGroupID = oldWorkoutID }
        }
        let groups = try context.fetch(FetchDescriptor<TemplateSupersetGroup>())
        let oldID = groups[0].id
        for group in groups {
            group.id = oldID
            for exercise in group.exercises ?? [] { exercise.supersetGroupID = oldID }
        }
        context.insert(TemplateSupersetGroup(id: oldID, templateID: groups[0].templateID, roundRestSeconds: 75))
        let drops = try context.fetch(FetchDescriptor<TemplateExerciseDropStage>())
        let oldDropID = drops[0].id
        for drop in drops { drop.id = oldDropID }
        try context.saveWithRecoveryProtection()
        try LocalCopiedIdentityRepair.repair(in: container)
        let repaired = ModelContext(container)
        try UserDataCloudBackupPayload(context: repaired).validate()
        let repairedGroups = try repaired.fetch(FetchDescriptor<TemplateSupersetGroup>())
        XCTAssertEqual(repairedGroups.count, 3)
        XCTAssertEqual(Set(repairedGroups.map(\.id)).count, 3)
        XCTAssertEqual(try repaired.fetchCount(FetchDescriptor<TemplateExercise>()), 4)
        XCTAssertEqual(Set(try repaired.fetch(FetchDescriptor<WorkoutSessionSupersetGroup>()).map(\.id)).count, 2)
        let before = try repaired.fetch(FetchDescriptor<WorkoutTemplate>()).map(\.updatedAt).sorted()
        try LocalCopiedIdentityRepair.repair(in: container)
        let after = try ModelContext(container).fetch(FetchDescriptor<WorkoutTemplate>()).map(\.updatedAt).sorted()
        XCTAssertEqual(before, after)
    }

    func testRestoreRepairsLegacyIdentitiesAndPreservesExistingDataOnConflict() async throws {
        for mode in 0..<3 {
            try await assertLegacyRestore(chunked: mode != 0, previous: mode == 2)
        }
    }

    private func assertLegacyRestore(chunked: Bool, previous: Bool) async throws {
        let context = ModelContext(try AppSchema.makeInMemoryContainer())
        context.autosaveEnabled = false
        let template = try makeTemplate(context)
        _ = try makeTemplate(context)
        for _ in 0..<2 {
            let session = try ActiveWorkoutSessionFactory(modelContext: context).createSessionFromTemplate(templateID: template.id)
            try WorkoutCompletionRepository(modelContext: context, boundaryEffects: .init(scheduleBackup: { _, _ in }))
                .completeWorkout(session: session)
        }
        var payload = try UserDataCloudBackupPayload(context: context)
        let oldTemplateID = payload.templateSupersetGroups![0].id
        for i in payload.templateSupersetGroups!.indices { payload.templateSupersetGroups![i].id = oldTemplateID }
        for i in payload.templateExercises.indices { payload.templateExercises[i].supersetGroupID = oldTemplateID }
        payload.templateSupersetGroups!.append(payload.templateSupersetGroups![0])
        let oldWorkoutID = payload.workoutSupersetGroups![0].id
        for i in payload.workoutSupersetGroups!.indices { payload.workoutSupersetGroups![i].id = oldWorkoutID }
        for i in payload.workoutExercises.indices { payload.workoutExercises[i].supersetGroupID = oldWorkoutID }
        let oldDropID = payload.templateDropStages[0].id
        for i in payload.templateDropStages.indices { payload.templateDropStages[i].id = oldDropID }
        let target = try AppSchema.makeInMemoryContainer()
        let targetContext = ModelContext(target)
        let existing = try makeTemplate(targetContext)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let encoder = JSONEncoder()
        for conflicting in [true, false] {
            var input = payload
            if conflicting {
                input.templateSupersetGroups![2].roundRestSeconds += 1
            } else {
                // An old unused row kept the original rest while the live row
                // was edited later. Exercise the complete restore transaction.
                input.templateSupersetGroups![2].updatedAt = input.templateSupersetGroups![0].updatedAt.addingTimeInterval(-10)
                input.templateSupersetGroups![0].roundRestSeconds = 120
                var staleWorkout = input.workoutSupersetGroups![0]
                staleWorkout.updatedAt = staleWorkout.updatedAt.addingTimeInterval(-10)
                input.workoutSupersetGroups![0].roundRestSeconds = 90
                input.workoutSupersetGroups!.append(staleWorkout)
            }
            let record = UserDataCloudBackupRemoteRecord(updatedAt: .now, payloadData: try encoder.encode(input), contentSummary: input.contentSummary)
            let service = UserDataCloudBackupService(localContainer: target, backupStore: IdentityBackupStore(record: record, chunked: chunked),
                routeFiles: CardioRouteFiles(directory: root))
            do {
                _ = try await service.restoreLatestBackup(replacingLocalData: true, previousGeneration: previous)
                XCTAssertFalse(conflicting)
            } catch {
                XCTAssertTrue(conflicting, "Unexpected restore failure: \(error)")
                XCTAssertEqual(try ModelContext(target).fetch(FetchDescriptor<WorkoutTemplate>()).map(\.id), [existing.id])
            }
        }
        let restored = try UserDataCloudBackupPayload(context: ModelContext(target))
        try restored.validate()
        XCTAssertEqual(restored.workoutTemplates.count, 2)
        XCTAssertEqual(restored.workoutSessions.count, 2)
        XCTAssertEqual(restored.templateDropStages.count, 4)
        XCTAssertEqual(Set(restored.workoutSupersetGroups!.map(\.id)).count, 2)
        XCTAssertEqual(restored.templateSupersetGroups?.first { $0.templateID == payload.templateSupersetGroups![0].templateID }?.roundRestSeconds, 120)
        XCTAssertEqual(restored.workoutSupersetGroups?.first { $0.sessionID == payload.workoutSupersetGroups![0].sessionID }?.roundRestSeconds, 90)
    }

    private func templates(_ context: ModelContext) -> TemplateRepository {
        TemplateRepository(modelContext: context,
            boundaryEffects: .init(postLibraryChange: {}, scheduleBackup: { _, _ in }))
    }

    private func makeTemplate(_ context: ModelContext) throws -> WorkoutTemplate {
        let repository = templates(context)
        let template = try repository.createTemplate(name: "Pair", notes: "")
        let groupID = UUID()
        let drafts = [SupersetExercisePosition.first, .second].enumerated().map { index, position in
            TemplateExerciseDraft(catalogExerciseUUID: "review-\(index)", exerciseNameSnapshot: "Exercise \(index)",
                categorySnapshot: "Strength", muscleSummarySnapshot: "", restSeconds: 75,
                setDrafts: [.init(targetReps: 8, targetWeight: 20, dropStages: [.init(targetReps: 6, targetWeight: 10)])],
                superset: .init(groupID: groupID, position: position, roundRestSeconds: 75))
        }
        try repository.setExercises(templateID: template.id, drafts: drafts)
        return template
    }
}

private actor IdentityBackupStore: UserDataCloudBackupStoring {
    let record: UserDataCloudBackupRemoteRecord
    let chunked: Bool
    init(record: UserDataCloudBackupRemoteRecord, chunked: Bool) {
        self.record = record
        self.chunked = chunked
    }
    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        guard chunked else { return record }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: record.payloadData) as? [String: Any])
        // Split rows across transport chunks, including colliding groups/drops.
        // Exercise the same combiner used by CloudKit before service-level repair.
        let combiner = UserDataBackupPayloadCodec.Combiner()
        for part in 0..<2 {
            var chunk = object
            for (key, value) in object {
                if let rows = value as? [Any] {
                    chunk[key] = rows.enumerated().filter { $0.offset % 2 == part }.map(\.element)
                }
            }
            let bytes = try JSONSerialization.data(withJSONObject: chunk, options: [.sortedKeys])
            try combiner.append(BackupArchiveCodec.decode(BackupArchiveCodec.encode(bytes)))
        }
        return try .init(updatedAt: record.updatedAt, payloadData: combiner.finish(generatedAt: record.updatedAt),
            contentSummary: record.contentSummary)
    }
    func fetchPreviousBackup() async throws -> UserDataCloudBackupRemoteRecord? { try await fetchBackup() }
    func fetchBackupMetadata() async throws -> UserDataCloudBackupRemoteMetadata? {
        let record = record
        return await MainActor.run { .init(updatedAt: record.updatedAt, contentSummary: record.contentSummary) }
    }
    func saveBackup(_ record: UserDataCloudBackupRemoteRecord, expectedUpdatedAt: Date?) async throws {
        throw CocoaError(.featureUnsupported)
    }
    func deleteBackup() async throws { throw CocoaError(.featureUnsupported) }
}
