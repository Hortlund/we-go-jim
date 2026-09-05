import CloudKit
import os
import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class UserDataCloudBackupServiceTests: XCTestCase {
    private enum RestoreTestError: Error {
        case checkpoint(UserDataCloudRestoreCheckpoint)
        case artifactCleanup
    }

    func testLocalContentSummaryCountsOnlyBackedUpRows() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        context.insert(UserProfile(displayName: "Andy"))
        context.insert(ExerciseCatalogItem(
            remoteUUID: "seed-bench",
            displayName: "Bench Press",
            sourceName: "seed"
        ))
        context.insert(ExerciseCatalogItem(
            remoteUUID: "custom-bench",
            displayName: "My Bench",
            sourceName: "custom"
        ))
        context.insert(WorkoutSession(name: "Active", status: .active))
        context.insert(WorkoutSession(name: "Completed", status: .completed, endedAt: .now))
        context.insert(WorkoutSession(
            name: "Archived",
            status: .completed,
            endedAt: .now,
            archivedAt: .now
        ))
        try context.save()

        let summary = try UserDataCloudBackupContentSummary.loadLocal(context: context)

        XCTAssertEqual(summary.profileCount, 1)
        XCTAssertEqual(summary.customExerciseCount, 1)
        XCTAssertEqual(summary.completedWorkoutCount, 2)
        XCTAssertEqual(summary.workoutTemplateCount, 0)
        XCTAssertEqual(summary.workoutExerciseCount, 0)
        XCTAssertEqual(summary.workoutSetCount, 0)
    }

    func testCompletionRepositoryReturnsExistingCompletedSessionWithoutDuplicateInsert() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let fixedSessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let runtime = ActiveWorkoutRuntimeSession(id: fixedSessionID, name: "Push")
        let repository = WorkoutCompletionRepository(modelContext: context)

        let first = try repository.completeWorkout(session: runtime)
        let second = try repository.completeWorkout(session: runtime)

        XCTAssertEqual(
            first,
            WorkoutCompletionCommitResult(sessionID: fixedSessionID, disposition: .inserted)
        )
        XCTAssertEqual(
            second,
            WorkoutCompletionCommitResult(sessionID: fixedSessionID, disposition: .alreadyCompleted)
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
    }

    func testRestorePolicyRejectsSnapshotForCompletedSession() {
        let fixedSessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        XCTAssertFalse(
            ActiveWorkoutRestorePolicy.shouldRestore(
                snapshotSessionID: fixedSessionID,
                completedSessionIDs: [fixedSessionID]
            )
        )
    }

    func testPresentationRestoreDeletesSnapshotForCompletedSession() async throws {
        try? await ActiveWorkoutSnapshotStore.shared.delete()
        addTeardownBlock {
            try? await ActiveWorkoutSnapshotStore.shared.delete()
        }
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let fixedSessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        context.insert(WorkoutSession(
            id: fixedSessionID,
            name: "Push",
            status: .completed,
            endedAt: .now
        ))
        try context.save()
        try await ActiveWorkoutSnapshotStore.shared.save(
            ActiveWorkoutRuntimeSession(id: fixedSessionID, name: "Push")
        )
        let presentationState = ActiveWorkoutPresentationState()
        let backgroundStore = AppBackgroundStore(container: container)
        let coordinator = ActiveWorkoutCoordinator(
            persistence: ModelContainerActiveWorkoutPersistence(backgroundStore: backgroundStore)
        )

        await presentationState.restoreActiveSessionIfNeeded(
            coordinator: coordinator,
            modelContext: context,
            backgroundStore: backgroundStore,
            allowsLegacyDraftImport: false
        )

        let retainedSnapshot = try await ActiveWorkoutSnapshotStore.shared.loadStoredSnapshot()
        XCTAssertNil(presentationState.activeSessionID)
        XCTAssertNil(retainedSnapshot)
    }

    func testPresentationRestoreStagesCachedPreviousPerformanceWithoutHistoryQuery() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WGJPresentationRestoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let backgroundStore = AppBackgroundStore(container: container)
        let snapshotStore = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let exerciseID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let previousSet = WorkoutPreviousSetSnapshot(reps: 13, weight: 12, unit: .kg)
        _ = try await snapshotStore.save(ActiveWorkoutStoredSnapshot(
            session: ActiveWorkoutRuntimeSession(id: sessionID, name: "Current"),
            scrollOffsetY: 428.5,
            previousSetSnapshotsByExerciseID: [exerciseID: [0: previousSet]]
        ))
        let coordinator = ActiveWorkoutCoordinator(
            snapshotStore: snapshotStore,
            persistence: ModelContainerActiveWorkoutPersistence(backgroundStore: backgroundStore)
        )
        let presentationState = ActiveWorkoutPresentationState()

        await presentationState.restoreActiveSessionIfNeeded(
            coordinator: coordinator,
            modelContext: context,
            backgroundStore: backgroundStore,
            allowsLegacyDraftImport: false,
            presentationPolicy: .present
        )

        let restored = presentationState.preparedPreviousPerformanceResolution(
            for: sessionID,
            exerciseID: exerciseID
        )
        XCTAssertEqual(restored?.previous(at: 0), previousSet)
        XCTAssertEqual(presentationState.preparedScrollOffsetY(for: sessionID), 428.5)
    }

    func testStageLocalDataDeletionDoesNotCommitUntilCallerSaves() throws {
        let container = try makeInMemoryContainer()
        let seedContext = ModelContext(container)
        seedContext.insert(UserProfile(displayName: "Durable Athlete"))
        try seedContext.save()

        let restoreContext = ModelContext(container)
        restoreContext.autosaveEnabled = false
        let service = AppDataDeletionService(
            modelContext: restoreContext,
            deleteCloudBackup: {},
            clearWeeklyGoalWidgetSnapshot: {},
            clearActiveWorkoutSnapshot: {}
        )

        try service.stageLocalDataDeletion()

        let observerContext = ModelContext(container)
        XCTAssertEqual(try observerContext.fetch(FetchDescriptor<UserProfile>()).count, 1)
        restoreContext.rollback()
        XCTAssertEqual(try observerContext.fetch(FetchDescriptor<UserProfile>()).count, 1)
    }

    func testReplacementRestoreFailuresPreserveOriginalData() async throws {
        let source = try makeInMemoryContainer()
        let sourceContext = ModelContext(source)
        sourceContext.insert(UserProfile(displayName: "Restored"))
        try sourceContext.save()
        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: source,
            backupStore: backupStore
        ).exportCurrentBackup()

        for checkpoint in UserDataCloudRestoreCheckpoint.allCases {
            let local = try makeInMemoryContainer()
            let localContext = ModelContext(local)
            localContext.insert(UserProfile(displayName: "Original"))
            try localContext.save()
            let transaction = UserDataCloudRestoreTransaction(
                container: local,
                dependencies: UserDataCloudRestoreDependencies(
                    checkpoint: { reached in
                        if reached == checkpoint {
                            throw RestoreTestError.checkpoint(reached)
                        }
                    },
                    save: { try $0.save() }
                )
            )
            let service = UserDataCloudBackupService(
                localContainer: local,
                backupStore: backupStore,
                restoreTransaction: transaction
            )

            do {
                _ = try await service.restoreLatestBackup(replacingLocalData: true)
                XCTFail("Expected checkpoint failure at \(checkpoint)")
            } catch RestoreTestError.checkpoint(let reached) {
                XCTAssertEqual(reached, checkpoint)
            }

            XCTAssertEqual(
                try ModelContext(local).fetch(FetchDescriptor<UserProfile>()).map(\.displayName),
                ["Original"]
            )
        }
    }

    func testRestoreRejectsUnsupportedSchemaBeforeDeletingLocalData() async throws {
        let source = try makeInMemoryContainer()
        let sourceContext = ModelContext(source)
        sourceContext.insert(UserProfile(displayName: "Restored"))
        try sourceContext.save()
        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: source,
            backupStore: backupStore
        ).exportCurrentBackup()
        let fetchedRecord = try await backupStore.fetchBackup()
        let exported = try XCTUnwrap(fetchedRecord)
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: exported.payloadData) as? [String: Any]
        )
        json["schemaVersion"] = 999
        await backupStore.replaceRecord(UserDataCloudBackupRemoteRecord(
            updatedAt: exported.updatedAt,
            payloadData: try JSONSerialization.data(withJSONObject: json)
        ))

        let local = try makeInMemoryContainer()
        let localContext = ModelContext(local)
        localContext.insert(UserProfile(displayName: "Original"))
        try localContext.save()

        do {
            _ = try await UserDataCloudBackupService(
                localContainer: local,
                backupStore: backupStore
            ).restoreLatestBackup(replacingLocalData: true)
            XCTFail("Expected unsupported schema validation to fail")
        } catch let error as UserDataCloudRestoreValidationError {
            XCTAssertEqual(error, .unsupportedSchemaVersion(999))
        }

        XCTAssertEqual(
            try ModelContext(local).fetch(FetchDescriptor<UserProfile>()).map(\.displayName),
            ["Original"]
        )
    }

    func testRestoreValidationRejectsOrphanedWorkoutSet() async throws {
        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let setID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let missingExerciseID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let source = try makeInMemoryContainer()
        let sourceContext = ModelContext(source)
        let session = WorkoutSession(
            id: sessionID,
            name: "Upper",
            status: .completed,
            endedAt: Date(timeIntervalSince1970: 2_000)
        )
        let exercise = WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            session: session
        )
        let set = WorkoutSessionSet(
            id: setID,
            sessionExerciseID: exerciseID,
            actualReps: 8,
            actualWeight: 100,
            isCompleted: true,
            sessionExercise: exercise
        )
        sourceContext.insert(session)
        sourceContext.insert(exercise)
        sourceContext.insert(set)
        session.exercises = [exercise]
        exercise.sets = [set]
        try sourceContext.save()
        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: source,
            backupStore: backupStore
        ).exportCurrentBackup()
        let fetchedRecord = try await backupStore.fetchBackup()
        let exported = try XCTUnwrap(fetchedRecord)
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: exported.payloadData) as? [String: Any]
        )
        var workoutSets = try XCTUnwrap(json["workoutSets"] as? [[String: Any]])
        workoutSets[0]["sessionExerciseID"] = missingExerciseID.uuidString
        json["workoutSets"] = workoutSets
        await backupStore.replaceRecord(UserDataCloudBackupRemoteRecord(
            updatedAt: exported.updatedAt,
            payloadData: try JSONSerialization.data(withJSONObject: json)
        ))

        let local = try makeInMemoryContainer()
        let localContext = ModelContext(local)
        localContext.insert(UserProfile(displayName: "Original"))
        try localContext.save()

        do {
            _ = try await UserDataCloudBackupService(
                localContainer: local,
                backupStore: backupStore
            ).restoreLatestBackup(replacingLocalData: true)
            XCTFail("Expected orphan validation to fail")
        } catch let error as UserDataCloudRestoreValidationError {
            XCTAssertEqual(
                error,
                .missingParent(
                    childEntity: "WorkoutSessionSet",
                    childIdentifier: setID.uuidString,
                    parentIdentifier: missingExerciseID.uuidString
                )
            )
        }

        XCTAssertEqual(
            try ModelContext(local).fetch(FetchDescriptor<UserProfile>()).map(\.displayName),
            ["Original"]
        )
    }

    func testReplacementRestoreArtifactFailureKeepsCommittedRestore() async throws {
        let source = try makeInMemoryContainer()
        let sourceContext = ModelContext(source)
        sourceContext.insert(UserProfile(displayName: "Restored"))
        try sourceContext.save()
        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: source,
            backupStore: backupStore
        ).exportCurrentBackup()
        let local = try makeInMemoryContainer()
        let localContext = ModelContext(local)
        localContext.insert(UserProfile(displayName: "Original"))
        try localContext.save()
        let defaultsSuiteName = UUID().uuidString
        let queue = AppDataArtifactCleanupQueue(
            defaultsSuiteName: defaultsSuiteName,
            cleanup: { _ in throw RestoreTestError.artifactCleanup }
        )
        let service = UserDataCloudBackupService(
            localContainer: local,
            backupStore: backupStore,
            artifactCleanupQueue: queue
        )

        let result = try await service.restoreLatestBackup(replacingLocalData: true)

        XCTAssertEqual(result?.cleanupWarnings.count, AppDataArtifact.allCases.count)
        XCTAssertEqual(
            try ModelContext(local).fetch(FetchDescriptor<UserProfile>()).map(\.displayName),
            ["Restored"]
        )
    }

    func testStorageDiagnosticsDoesNotPostLegacyRefreshEventsAfterRestore() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("WGJ/Views/Profile/AppStorageDiagnosticsView.swift"),
            encoding: .utf8
        )
        let restoreStart = try XCTUnwrap(source.range(of: "private func restoreCloudBackup()"))
        let restoreBody = source[restoreStart.lowerBound...]

        XCTAssertFalse(restoreBody.contains("WorkoutHistoryChangeBroadcaster.post()"))
        XCTAssertFalse(restoreBody.contains("TemplateLibraryChangeBroadcaster.post()"))
    }

    func testRootAndTemplateHomeObserveSingleRestoreEvent() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("WGJ/ContentView.swift"),
            encoding: .utf8
        )
        let startWorkoutHome = try String(
            contentsOf: repositoryRoot.appendingPathComponent("WGJ/Views/Workout/StartWorkoutHomeView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contentView.contains(".wgjUserDataRestoreDidComplete"))
        XCTAssertTrue(startWorkoutHome.contains(".wgjUserDataRestoreDidComplete"))
    }

    func testAppRetriesPendingArtifactCleanupAtLaunch() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("WGJ/WGJApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("AppDataArtifactCleanupQueue.shared.retryPending()"))
    }

    func testStartupRootViewChecksMetadataWithoutDownloadingOrRestoringBackup() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentViewURL = repositoryRoot
            .appendingPathComponent("WGJ")
            .appendingPathComponent("ContentView.swift")
        let contentViewSource = try String(contentsOf: contentViewURL, encoding: .utf8)

        XCTAssertTrue(contentViewSource.contains("CloudBackupStatusCheckScheduler.checkMetadataBestEffort"))
        XCTAssertTrue(contentViewSource.contains("startupCloudBackupStatusCheckTask?.cancel()"))
        XCTAssertTrue(contentViewSource.contains("resetCloudBackupSession()"))
        XCTAssertFalse(contentViewSource.contains("latestBackupSnapshot("))
        XCTAssertFalse(contentViewSource.contains("restoreLatestBackup("))
        XCTAssertFalse(contentViewSource.contains("app.startup-cloud-restore"))
    }

    func testCloudBackupStatusMessagesDistinguishChecksFromUploads() {
        let checking = UserDataSyncStatusSnapshot.checkingStatus()
        XCTAssertEqual(checking.state, .checking)
        XCTAssertEqual(checking.title, "Checking cloud backup")
        XCTAssertTrue(checking.detail.isEmpty)

        let checked = UserDataSyncStatusSnapshot.statusChecked(at: .now)
        XCTAssertEqual(checked.state, .checked)
        XCTAssertEqual(checked.title, "Cloud backup found")
        XCTAssertEqual(checked.detail, "An existing iCloud backup was found.")
        XCTAssertTrue(checked.hasKnownRemoteBackup)

        let missing = UserDataSyncStatusSnapshot.statusChecked(at: nil)
        XCTAssertFalse(missing.hasKnownRemoteBackup)

        let pending = UserDataSyncStatusSnapshot.pending()
        XCTAssertEqual(pending.state, .pending)
        XCTAssertEqual(pending.title, "Backing up to iCloud")
        XCTAssertTrue(pending.detail.contains("uploading"))

        let backedUp = UserDataSyncStatusSnapshot.backedUp()
        XCTAssertEqual(backedUp.state, .backedUp)
        XCTAssertEqual(backedUp.title, "Cloud backup complete")
        XCTAssertTrue(backedUp.detail.contains("was uploaded"))
    }

    func testCloudBackupMetadataFetchExcludesPayloadFields() {
        XCTAssertEqual(
            UserDataCloudBackupDescriptor.metadataFieldKeys,
            [UserDataCloudBackupDescriptor.Field.updatedAt, UserDataCloudBackupDescriptor.Field.contentSummary]
        )
        XCTAssertFalse(UserDataCloudBackupDescriptor.metadataFieldKeys.contains(
            UserDataCloudBackupDescriptor.Field.payloadAsset
        ))
        XCTAssertFalse(UserDataCloudBackupDescriptor.metadataFieldKeys.contains(
            UserDataCloudBackupDescriptor.Field.payloadData
        ))
    }

    func testCloudBackupCancellationPolicyRecognizesSwiftAndCloudKitCancellation() {
        XCTAssertTrue(CloudBackupOperationErrorPolicy.isCancellation(
            CancellationError(),
            taskWasCancelled: false
        ))
        XCTAssertTrue(CloudBackupOperationErrorPolicy.isCancellation(
            NSError(
                domain: CKErrorDomain,
                code: CKError.Code.operationCancelled.rawValue
            ),
            taskWasCancelled: false
        ))
        XCTAssertTrue(CloudBackupOperationErrorPolicy.isCancellation(
            RestoreTestError.artifactCleanup,
            taskWasCancelled: true
        ))
        XCTAssertFalse(CloudBackupOperationErrorPolicy.isCancellation(
            RestoreTestError.artifactCleanup,
            taskWasCancelled: false
        ))
    }

    func testLateStatusCheckCannotOverwriteActiveBackup() throws {
        let state = AppRuntimeState.shared
        defer { state.updateUserDataSyncStatus(.localOnly(reason: nil)) }
        state.updateUserDataSyncStatus(.localOnly(reason: nil))
        guard let revision = state.beginUserDataSyncStatusCheck(.checkingStatus()) else {
            return XCTFail("Expected the status check to start")
        }

        XCTAssertNil(state.beginUserDataSyncStatusCheck(.checkingContents()))

        state.updateUserDataSyncStatus(.pending())
        state.finishUserDataSyncStatusCheck(.statusChecked(at: .now), matching: revision)

        XCTAssertEqual(state.userDataSyncStatus.state, .pending)
        let blockedRevision = state.beginUserDataSyncStatusCheck(.checkingStatus())
        XCTAssertNil(blockedRevision)
    }

    func testCloudBackupBannerStatusObservationStaysOutOfMainTabShell() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let mainTabURL = repositoryRoot
            .appendingPathComponent("WGJ")
            .appendingPathComponent("Views")
            .appendingPathComponent("MainTabView.swift")
        let mainTabSource = try String(contentsOf: mainTabURL, encoding: .utf8)

        let mainTabStart = try XCTUnwrap(mainTabSource.range(of: "struct MainTabView: View"))
        let bannerHostStart = try XCTUnwrap(mainTabSource.range(of: "private struct CloudBackupStatusBannerHost"))
        let mainTabShell = mainTabSource[mainTabStart.lowerBound..<bannerHostStart.lowerBound]

        XCTAssertFalse(mainTabShell.contains("\\.userDataSyncStatus"))
        XCTAssertTrue(mainTabSource.contains("@Environment(\\.userDataSyncStatus) private var userDataSyncStatus"))
    }

    func testWorkoutCompletionBackupIsDeferredPastCompletionPresentation() {
        XCTAssertEqual(
            BoundaryCloudBackupScheduler.enqueueDelay(for: .workoutCompleted),
            WorkoutCompletionBackgroundWorkPolicy.quiescenceDelay
        )
        XCTAssertEqual(
            BoundaryCloudBackupScheduler.enqueueDelay(for: .workoutCompletionTemplateSaved),
            WorkoutCompletionBackgroundWorkPolicy.quiescenceDelay
        )
        XCTAssertEqual(
            BoundaryCloudBackupScheduler.enqueueDelay(for: .templateSaved),
            .zero
        )
        XCTAssertEqual(
            BoundaryCloudBackupScheduler.enqueueDelay(for: .workoutDeleted),
            .zero
        )
    }

    func testTemplateRepositoryCanUseWorkoutCompletionTemplateBackupReason() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let repository = TemplateRepository(
            modelContext: context,
            autoSaveChanges: false,
            userDataChangeBackupReason: .workoutCompletionTemplateSaved
        )

        XCTAssertEqual(repository.backupReasonForUserDataChanges, .workoutCompletionTemplateSaved)
    }

    func testDuplicateTemplatePreservesPreviousSetTargets() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let templateID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let setID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let template = WorkoutTemplate(
            id: templateID,
            folderID: TemplateRepository.unfiledFolderID,
            name: "Upper",
            notes: "Original"
        )
        let exercise = TemplateExercise(
            id: exerciseID,
            templateID: templateID,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            template: template
        )
        let set = TemplateExerciseSet(
            id: setID,
            templateExerciseID: exerciseID,
            targetReps: 8,
            targetWeight: 100,
            loadUnit: .kg,
            previousTargetReps: 7,
            previousTargetWeight: 95,
            previousLoadUnit: .kg,
            templateExercise: exercise
        )
        context.insert(template)
        context.insert(exercise)
        context.insert(set)
        template.exercises = [exercise]
        exercise.prescribedSets = [set]
        try context.save()

        let copied = try TemplateRepository(modelContext: context)
            .duplicateTemplate(id: templateID, name: "Upper Copy")

        let copiedExercise = try XCTUnwrap(copied.exercises?.first)
        let copiedSet = try XCTUnwrap(copiedExercise.prescribedSets?.first)
        XCTAssertNotEqual(copiedSet.id, setID)
        XCTAssertEqual(copiedSet.targetReps, 8)
        XCTAssertEqual(copiedSet.targetWeight, 100)
        XCTAssertEqual(copiedSet.previousTargetReps, 7)
        XCTAssertEqual(copiedSet.previousTargetWeight, 95)
        XCTAssertEqual(copiedSet.previousLoadUnit, .kg)
    }

    func testRemoveExerciseRejectsExerciseFromDifferentSession() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let firstSessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let secondSessionID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let firstExerciseID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let secondExerciseID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let firstSession = WorkoutSession(
            id: firstSessionID,
            name: "Push",
            status: .completed
        )
        let secondSession = WorkoutSession(
            id: secondSessionID,
            name: "Pull",
            status: .completed
        )
        let firstExercise = WorkoutSessionExercise(
            id: firstExerciseID,
            sessionID: firstSessionID,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            session: firstSession
        )
        let secondExercise = WorkoutSessionExercise(
            id: secondExerciseID,
            sessionID: secondSessionID,
            catalogExerciseUUID: "row",
            exerciseNameSnapshot: "Row",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            session: secondSession
        )
        for model in [
            firstSession,
            secondSession,
            firstExercise,
            secondExercise,
        ] as [any PersistentModel] {
            context.insert(model)
        }
        firstSession.exercises = [firstExercise]
        secondSession.exercises = [secondExercise]
        try context.save()

        XCTAssertThrowsError(
            try WorkoutSessionRepository(modelContext: context)
                .removeExercise(sessionID: firstSessionID, sessionExerciseID: secondExerciseID)
        ) { error in
            XCTAssertEqual(error as? WorkoutSessionRepositoryError, .sessionExerciseNotFound)
        }

        let remainingExercises = try context.fetch(FetchDescriptor<WorkoutSessionExercise>())
        XCTAssertEqual(Set(remainingExercises.map(\.id)), [firstExerciseID, secondExerciseID])
    }

    func testActiveDraftRemoveExerciseRejectsExerciseFromDifferentSession() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let firstSessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let secondSessionID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let firstExerciseID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let secondExerciseID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let firstSession = ActiveWorkoutDraftSession(
            id: firstSessionID,
            name: "Push"
        )
        let secondSession = ActiveWorkoutDraftSession(
            id: secondSessionID,
            name: "Pull"
        )
        let firstExercise = ActiveWorkoutDraftExercise(
            id: firstExerciseID,
            sessionID: firstSessionID,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            session: firstSession
        )
        let secondExercise = ActiveWorkoutDraftExercise(
            id: secondExerciseID,
            sessionID: secondSessionID,
            catalogExerciseUUID: "row",
            exerciseNameSnapshot: "Row",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            session: secondSession
        )
        for model in [
            firstSession,
            secondSession,
            firstExercise,
            secondExercise,
        ] as [any PersistentModel] {
            context.insert(model)
        }
        firstSession.exercises = [firstExercise]
        secondSession.exercises = [secondExercise]
        try context.save()

        XCTAssertThrowsError(
            try ActiveWorkoutDraftRepository(modelContext: context)
                .removeExercise(sessionID: firstSessionID, sessionExerciseID: secondExerciseID)
        ) { error in
            XCTAssertEqual(error as? WorkoutSessionRepositoryError, .sessionExerciseNotFound)
        }

        let remainingExercises = try context.fetch(FetchDescriptor<ActiveWorkoutDraftExercise>())
        XCTAssertEqual(Set(remainingExercises.map(\.id)), [firstExerciseID, secondExerciseID])
    }

    func testRestoreLatestBackupPreservesTemplateSupersetGroups() async throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        sourceContext.autosaveEnabled = false

        let folder = TemplateFolder(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Folder"
        )
        let template = WorkoutTemplate(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            folderID: folder.id,
            name: "Superset Template",
            folder: folder
        )
        let group = TemplateSupersetGroup(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            templateID: template.id,
            roundRestSeconds: 180,
            template: template
        )
        let firstExercise = TemplateExercise(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            templateID: template.id,
            catalogExerciseUUID: "bench",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            supersetGroupID: group.id,
            supersetPosition: .first,
            sortOrder: 0,
            template: template,
            supersetGroup: group
        )
        let secondExercise = TemplateExercise(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            templateID: template.id,
            catalogExerciseUUID: "row",
            exerciseNameSnapshot: "Row",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            supersetGroupID: group.id,
            supersetPosition: .second,
            sortOrder: 1,
            template: template,
            supersetGroup: group
        )
        for model in [
            folder,
            template,
            group,
            firstExercise,
            secondExercise,
        ] as [any PersistentModel] {
            sourceContext.insert(model)
        }
        folder.templates = [template]
        template.supersetGroups = [group]
        template.exercises = [firstExercise, secondExercise]
        group.exercises = [firstExercise, secondExercise]
        try sourceContext.save()

        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: sourceContainer,
            backupStore: backupStore
        ).exportCurrentBackup()

        let restoredContainer = try makeInMemoryContainer()
        _ = try await UserDataCloudBackupService(
            localContainer: restoredContainer,
            backupStore: backupStore
        ).restoreLatestBackup()

        let restoredContext = ModelContext(restoredContainer)
        let restoredGroups = try restoredContext.fetch(FetchDescriptor<TemplateSupersetGroup>())
        XCTAssertEqual(restoredGroups.count, 1)
        XCTAssertEqual(restoredGroups.first?.id, group.id)
        XCTAssertEqual(restoredGroups.first?.templateID, template.id)
        XCTAssertEqual(restoredGroups.first?.roundRestSeconds, 180)

        let restoredExercises = try restoredContext.fetch(FetchDescriptor<TemplateExercise>())
            .sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(restoredExercises.first?.supersetMembership?.roundRestSeconds, 180)
        XCTAssertEqual(restoredExercises.last?.supersetMembership?.roundRestSeconds, 180)
    }

    func testRestoreLatestBackupPreservesAllProfileSettings() async throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        sourceContext.autosaveEnabled = false
        let dateOfBirth = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "1990-05-20T00:00:00Z")
        )
        sourceContext.insert(UserProfile(
            displayName: "Peter",
            athleteType: .powerlifting,
            calorieEstimateSex: .female,
            dateOfBirth: dateOfBirth,
            heightCentimeters: 172.5,
            bodyWeightKilograms: 68.25,
            showsCalorieEstimates: false,
            preferredWeightUnit: .lb,
            preferredDistanceUnit: .miles,
            workoutNotificationStyle: .standard,
            weeklyWorkoutGoal: 5,
            isTrainingGuidanceEnabled: false,
            keepsScreenAwake: true,
            automaticallyClosesCompletedExercises: false,
            isBozarModeEnabled: true
        ))
        try sourceContext.save()

        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: sourceContainer,
            backupStore: backupStore
        ).exportCurrentBackup()

        let restoredContainer = try makeInMemoryContainer()
        let restoreResult = try await UserDataCloudBackupService(
            localContainer: restoredContainer,
            backupStore: backupStore
        ).restoreLatestBackup()

        let restoredContext = ModelContext(restoredContainer)
        let profiles = try restoredContext.fetch(FetchDescriptor<UserProfile>())
        XCTAssertNotNil(restoreResult)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.displayName, "Peter")
        XCTAssertEqual(profiles.first?.calorieEstimateSex, .female)
        XCTAssertEqual(profiles.first?.dateOfBirth, dateOfBirth)
        XCTAssertEqual(profiles.first?.heightCentimeters, 172.5)
        XCTAssertEqual(profiles.first?.bodyWeightKilograms, 68.25)
        XCTAssertEqual(profiles.first?.showsCalorieEstimates, false)
        XCTAssertEqual(profiles.first?.preferredWeightUnit, .lb)
        XCTAssertEqual(profiles.first?.preferredDistanceUnit, .miles)
        XCTAssertEqual(profiles.first?.workoutNotificationStyle, .standard)
        XCTAssertEqual(profiles.first?.weeklyWorkoutGoal, 5)
        XCTAssertEqual(profiles.first?.isTrainingGuidanceEnabled, false)
        XCTAssertEqual(profiles.first?.keepsScreenAwake, true)
        XCTAssertEqual(profiles.first?.automaticallyClosesCompletedExercises, false)
        XCTAssertEqual(profiles.first?.isBozarModeEnabled, true)
    }

    func testBackupRoundTripPreservesFlexibleCardioAndCustomTrackingProfile() async throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        sourceContext.autosaveEnabled = false
        let customExercise = ExerciseCatalogItem(
            remoteUUID: "custom-rower",
            displayName: "Garage Rower",
            categoryName: "Cardio",
            equipmentSummary: "Rower",
            cardioTrackingProfileRaw: WorkoutCardioTrackingProfile.rower.rawValue,
            isCurated: false,
            sourceName: "custom"
        )
        let template = WorkoutTemplate(
            folderID: TemplateRepository.unfiledFolderID,
            name: "Double Main"
        )
        let firstTemplateActivity = TemplateCardioBlock(
            templateID: template.id,
            phase: .preWorkout,
            role: .main,
            sortOrder: 0,
            catalogExerciseUUID: customExercise.remoteUUID,
            exerciseNameSnapshot: customExercise.displayName,
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Full Body",
            trackingProfile: .rower,
            goalKind: .time,
            targetDurationSeconds: 900,
            preferredDistanceUnit: .meters,
            template: template
        )
        let secondTemplateActivity = TemplateCardioBlock(
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
            targetDistanceMeters: 10_000,
            preferredDistanceUnit: .miles,
            template: template
        )
        let session = WorkoutSession(
            templateID: template.id,
            name: template.name,
            status: .completed,
            endedAt: Date(timeIntervalSince1970: 2_000)
        )
        let firstResult = WorkoutSessionCardioBlock(
            sessionID: session.id,
            sourceTemplateCardioID: firstTemplateActivity.id,
            phase: .preWorkout,
            role: .main,
            sortOrder: 0,
            catalogExerciseUUID: customExercise.remoteUUID,
            exerciseNameSnapshot: customExercise.displayName,
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Full Body",
            trackingProfile: .rower,
            goalKind: .time,
            targetDurationSeconds: 900,
            actualDurationSeconds: 875,
            actualDistanceMeters: 5_000,
            preferredDistanceUnit: .meters,
            resistanceLevel: 7,
            cardioNotes: "Steady",
            isCompleted: true,
            session: session
        )
        let secondResult = WorkoutSessionCardioBlock(
            sessionID: session.id,
            sourceTemplateCardioID: secondTemplateActivity.id,
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
            targetDistanceMeters: 10_000,
            actualDurationSeconds: 3_600,
            actualDistanceMeters: 10_000,
            preferredDistanceUnit: .miles,
            inclinePercent: 2.5,
            cardioNotes: "Negative split",
            isCompleted: true,
            session: session
        )
        for model in [
            customExercise,
            template,
            firstTemplateActivity,
            secondTemplateActivity,
            session,
            firstResult,
            secondResult,
        ] as [any PersistentModel] {
            sourceContext.insert(model)
        }
        template.cardioBlocks = [firstTemplateActivity, secondTemplateActivity]
        session.cardioBlocks = [firstResult, secondResult]
        try sourceContext.save()

        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: sourceContainer,
            backupStore: backupStore
        ).exportCurrentBackup()
        let restoredContainer = try makeInMemoryContainer()
        _ = try await UserDataCloudBackupService(
            localContainer: restoredContainer,
            backupStore: backupStore
        ).restoreLatestBackup()
        let restoredContext = ModelContext(restoredContainer)
        let restoredTemplateActivities = try restoredContext.fetch(FetchDescriptor<TemplateCardioBlock>())
            .sorted { $0.sortOrder < $1.sortOrder }
        let restoredResults = try restoredContext.fetch(FetchDescriptor<WorkoutSessionCardioBlock>())
            .sorted { $0.sortOrder < $1.sortOrder }
        let restoredCustom = try restoredContext.fetch(FetchDescriptor<ExerciseCatalogItem>()).first

        XCTAssertEqual(restoredTemplateActivities.map(\.role), [.main, .main])
        XCTAssertEqual(restoredTemplateActivities.map(\.sortOrder), [0, 1])
        XCTAssertEqual(restoredTemplateActivities.map(\.trackingProfile), [.rower, .walkRun])
        XCTAssertEqual(restoredTemplateActivities.map(\.goalKind), [.time, .distance])
        XCTAssertEqual(restoredTemplateActivities.map(\.targetDistanceMeters), [nil, 10_000])
        XCTAssertEqual(restoredResults.map(\.sourceTemplateCardioID), [firstTemplateActivity.id, secondTemplateActivity.id])
        XCTAssertEqual(restoredResults.map(\.role), [.main, .main])
        XCTAssertEqual(restoredResults.map(\.sortOrder), [0, 1])
        XCTAssertEqual(restoredResults.map(\.trackingProfile), [.rower, .walkRun])
        XCTAssertEqual(restoredResults.map(\.goalKind), [.time, .distance])
        XCTAssertEqual(restoredResults.map(\.targetDurationSeconds), [900, 0])
        XCTAssertEqual(restoredResults.map(\.targetDistanceMeters), [nil, 10_000])
        XCTAssertEqual(restoredResults.map(\.actualDurationSeconds), [875, 3_600])
        XCTAssertEqual(restoredResults.map(\.actualDistanceMeters), [5_000, 10_000])
        XCTAssertEqual(restoredResults.map(\.preferredDistanceUnit), [.meters, .miles])
        XCTAssertEqual(restoredResults.map(\.inclinePercent), [nil, 2.5])
        XCTAssertEqual(restoredResults.map(\.resistanceLevel), [7, nil])
        XCTAssertEqual(restoredResults.map(\.cardioNotes), ["Steady", "Negative split"])
        XCTAssertEqual(restoredResults.map(\.isCompleted), [true, true])
        XCTAssertEqual(restoredCustom?.cardioTrackingProfileRaw, WorkoutCardioTrackingProfile.rower.rawValue)
    }

    func testBackupRoundTripPreservesCustomExerciseMusclesAndAliases() async throws {
        let source = try makeInMemoryContainer()
        let sourceContext = ModelContext(source)
        let chest = MuscleGroup(remoteID: 10, name: "Chest", nameEn: "Chest")
        let triceps = MuscleGroup(remoteID: 20, name: "Triceps", nameEn: "Triceps")
        let custom = ExerciseCatalogItem(
            remoteUUID: "custom-floor-press",
            displayName: "Floor Press",
            categoryName: "Strength",
            equipmentSummary: "Dumbbells",
            instructionText: "Press from the floor.",
            isCurated: false,
            sourceName: "custom"
        )
        let shortAlias = ExerciseAlias(value: "DB Floor Press", exercise: custom)
        let longAlias = ExerciseAlias(value: "Dumbbell Floor Press", exercise: custom)
        for model in [chest, triceps, custom, shortAlias, longAlias] as [any PersistentModel] {
            sourceContext.insert(model)
        }
        custom.primaryMuscles = [chest]
        custom.secondaryMuscles = [triceps]
        custom.aliases = [shortAlias, longAlias]
        try sourceContext.save()

        let store = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: source,
            backupStore: store
        ).exportCurrentBackup()

        let restored = try makeInMemoryContainer()
        let restoredSeedContext = ModelContext(restored)
        restoredSeedContext.insert(MuscleGroup(remoteID: 10, name: "Chest", nameEn: "Chest"))
        restoredSeedContext.insert(MuscleGroup(remoteID: 20, name: "Triceps", nameEn: "Triceps"))
        try restoredSeedContext.save()

        _ = try await UserDataCloudBackupService(
            localContainer: restored,
            backupStore: store
        ).restoreLatestBackup()

        let restoredContext = ModelContext(restored)
        let restoredCustom = try XCTUnwrap(
            restoredContext.fetch(FetchDescriptor<ExerciseCatalogItem>())
                .first(where: { $0.remoteUUID == custom.remoteUUID })
        )
        XCTAssertEqual(restoredCustom.primaryMuscles.map(\.remoteID).sorted(), [10])
        XCTAssertEqual(restoredCustom.secondaryMuscles.map(\.remoteID).sorted(), [20])
        XCTAssertEqual(
            restoredCustom.aliases.map(\.value).sorted(),
            ["DB Floor Press", "Dumbbell Floor Press"]
        )
    }

    func testRestoreRejectsCustomExerciseWhenReferencedCatalogMuscleIsMissing() async throws {
        let source = try makeInMemoryContainer()
        let sourceContext = ModelContext(source)
        let chest = MuscleGroup(remoteID: 10, name: "Chest", nameEn: "Chest")
        let custom = ExerciseCatalogItem(
            remoteUUID: "custom-floor-press",
            displayName: "Floor Press",
            categoryName: "Strength",
            isCurated: false,
            sourceName: "custom"
        )
        sourceContext.insert(chest)
        sourceContext.insert(custom)
        custom.primaryMuscles = [chest]
        try sourceContext.save()

        let store = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: source,
            backupStore: store
        ).exportCurrentBackup()

        let restored = try makeInMemoryContainer()
        do {
            _ = try await UserDataCloudBackupService(
                localContainer: restored,
                backupStore: store
            ).restoreLatestBackup()
            XCTFail("Expected restore to reject a missing catalog muscle")
        } catch {
            XCTAssertEqual(
                error as? UserDataCloudRestoreValidationError,
                .missingCatalogMuscle(
                    exerciseIdentifier: custom.remoteUUID,
                    muscleIdentifier: chest.remoteID
                )
            )
        }

        let restoredContext = ModelContext(restored)
        XCTAssertTrue(try restoredContext.fetch(FetchDescriptor<ExerciseCatalogItem>()).isEmpty)
    }

    func testBackupWithoutNewCardioProfileFieldsUsesLegacyFallbacks() async throws {
        let source = try makeInMemoryContainer()
        let sourceContext = ModelContext(source)
        sourceContext.insert(UserProfile(displayName: "Legacy", preferredDistanceUnit: .miles))
        let custom = ExerciseCatalogItem(
            remoteUUID: "legacy-cardio",
            displayName: "Legacy Cardio",
            categoryName: "Cardio",
            equipmentSummary: "Machine",
            cardioTrackingProfileRaw: WorkoutCardioTrackingProfile.rower.rawValue,
            isCurated: false,
            sourceName: "custom"
        )
        let template = WorkoutTemplate(
            folderID: TemplateRepository.unfiledFolderID,
            name: "Legacy"
        )
        let activity = TemplateCardioBlock(
            templateID: template.id,
            phase: .postWorkout,
            catalogExerciseUUID: custom.remoteUUID,
            exerciseNameSnapshot: custom.displayName,
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "",
            targetDurationSeconds: 600,
            template: template
        )
        for model in [custom, template, activity] as [any PersistentModel] {
            sourceContext.insert(model)
        }
        template.cardioBlocks = [activity]
        try sourceContext.save()
        let store = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let fetchedRecord = try await store.fetchBackup()
        let record = try XCTUnwrap(fetchedRecord)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: record.payloadData) as? [String: Any])
        var profiles = try XCTUnwrap(json["profiles"] as? [[String: Any]])
        profiles[0].removeValue(forKey: "preferredDistanceUnitRaw")
        for key in [
            "calorieEstimateSexRaw",
            "dateOfBirth",
            "heightCentimeters",
            "bodyWeightKilograms",
            "showsCalorieEstimates",
        ] {
            profiles[0].removeValue(forKey: key)
        }
        json["profiles"] = profiles
        var customExercises = try XCTUnwrap(json["customExercises"] as? [[String: Any]])
        for key in [
            "cardioTrackingProfileRaw",
            "primaryMuscleRemoteIDs",
            "secondaryMuscleRemoteIDs",
            "aliases",
        ] {
            customExercises[0].removeValue(forKey: key)
        }
        json["customExercises"] = customExercises
        var templateActivities = try XCTUnwrap(json["templateCardioBlocks"] as? [[String: Any]])
        for key in ["roleRaw", "sortOrder", "trackingProfileRaw", "goalKindRaw", "targetDistanceMeters", "preferredDistanceUnitRaw"] {
            templateActivities[0].removeValue(forKey: key)
        }
        json["templateCardioBlocks"] = templateActivities
        await store.replaceRecord(UserDataCloudBackupRemoteRecord(
            updatedAt: record.updatedAt,
            payloadData: try JSONSerialization.data(withJSONObject: json)
        ))

        let restored = try makeInMemoryContainer()
        _ = try await UserDataCloudBackupService(localContainer: restored, backupStore: store).restoreLatestBackup()
        let restoredContext = ModelContext(restored)
        let restoredProfile = try XCTUnwrap(restoredContext.fetch(FetchDescriptor<UserProfile>()).first)
        let restoredCustom = try XCTUnwrap(restoredContext.fetch(FetchDescriptor<ExerciseCatalogItem>()).first)
        let restoredActivity = try XCTUnwrap(restoredContext.fetch(FetchDescriptor<TemplateCardioBlock>()).first)

        XCTAssertNil(restoredProfile.preferredDistanceUnitRaw)
        XCTAssertEqual(restoredProfile.preferredDistanceUnit, .regionalDefault(locale: .current))
        XCTAssertNil(restoredProfile.calorieEstimateSex)
        XCTAssertNil(restoredProfile.dateOfBirth)
        XCTAssertNil(restoredProfile.heightCentimeters)
        XCTAssertNil(restoredProfile.bodyWeightKilograms)
        XCTAssertTrue(restoredProfile.showsCalorieEstimates)
        XCTAssertNil(restoredCustom.cardioTrackingProfileRaw)
        XCTAssertTrue(restoredCustom.primaryMuscles.isEmpty)
        XCTAssertTrue(restoredCustom.secondaryMuscles.isEmpty)
        XCTAssertTrue(restoredCustom.aliases.isEmpty)
        XCTAssertEqual(restoredActivity.role, .finisher)
        XCTAssertEqual(restoredActivity.sortOrder, 0)
        XCTAssertEqual(restoredActivity.goalKind, .time)
        XCTAssertNil(restoredActivity.targetDistanceMeters)
    }

    func testBackupRoundTripPersistsSessionCalorieEstimateResults() async throws {
        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let source = try makeInMemoryContainer()
        let sourceContext = ModelContext(source)
        sourceContext.insert(WorkoutSession(
            id: sessionID,
            name: "Upper",
            status: .completed,
            endedAt: Date(timeIntervalSince1970: 2_000),
            estimatedActiveCalories: 145,
            calorieEstimateVersion: 1
        ))
        try sourceContext.save()
        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: source,
            backupStore: backupStore
        ).exportCurrentBackup()

        let restored = try makeInMemoryContainer()
        _ = try await UserDataCloudBackupService(
            localContainer: restored,
            backupStore: backupStore
        ).restoreLatestBackup()
        let restoredSession = try XCTUnwrap(
            ModelContext(restored).fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == sessionID }
        )

        XCTAssertEqual(restoredSession.estimatedActiveCalories, 145)
        XCTAssertEqual(restoredSession.calorieEstimateVersion, 1)
    }

    func testBackupWithoutSessionCalorieEstimateFieldsRestoresNilValues() async throws {
        let source = try makeInMemoryContainer()
        let sourceContext = ModelContext(source)
        sourceContext.insert(WorkoutSession(
            name: "Upper",
            status: .completed,
            endedAt: Date(timeIntervalSince1970: 2_000)
        ))
        try sourceContext.save()
        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: source,
            backupStore: backupStore
        ).exportCurrentBackup()
        let fetchedRecord = try await backupStore.fetchBackup()
        let exported = try XCTUnwrap(fetchedRecord)
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: exported.payloadData) as? [String: Any]
        )
        var workoutSessions = try XCTUnwrap(json["workoutSessions"] as? [[String: Any]])
        workoutSessions[0].removeValue(forKey: "estimatedActiveCalories")
        workoutSessions[0].removeValue(forKey: "calorieEstimateVersion")
        json["workoutSessions"] = workoutSessions
        await backupStore.replaceRecord(UserDataCloudBackupRemoteRecord(
            updatedAt: exported.updatedAt,
            payloadData: try JSONSerialization.data(withJSONObject: json)
        ))

        let restored = try makeInMemoryContainer()
        _ = try await UserDataCloudBackupService(
            localContainer: restored,
            backupStore: backupStore
        ).restoreLatestBackup()
        let restoredSession = try XCTUnwrap(
            ModelContext(restored).fetch(FetchDescriptor<WorkoutSession>()).first
        )

        XCTAssertNil(restoredSession.estimatedActiveCalories)
        XCTAssertNil(restoredSession.calorieEstimateVersion)
    }

    func testRestoreLatestBackupCanReplaceBrokenLocalTemplates() async throws {
        let templateID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let exerciseID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let folderID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        sourceContext.autosaveEnabled = false
        let sourceFolder = TemplateFolder(id: folderID, name: "Bro Split")
        let sourceTemplate = WorkoutTemplate(id: templateID, folderID: folderID, name: "Day 1 - Upper A", folder: sourceFolder)
        let sourceExercise = TemplateExercise(
            id: exerciseID,
            templateID: templateID,
            catalogExerciseUUID: "lat-pulldown",
            exerciseNameSnapshot: "Lat Pulldown",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            sortOrder: 0,
            template: sourceTemplate
        )
        sourceContext.insert(sourceFolder)
        sourceContext.insert(sourceTemplate)
        sourceContext.insert(sourceExercise)
        sourceFolder.templates = [sourceTemplate]
        sourceTemplate.exercises = [sourceExercise]
        try sourceContext.save()

        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: sourceContainer,
            backupStore: backupStore
        ).exportCurrentBackup()

        let brokenContainer = try makeInMemoryContainer()
        let brokenContext = ModelContext(brokenContainer)
        brokenContext.autosaveEnabled = false
        brokenContext.insert(WorkoutTemplate(id: templateID, folderID: folderID, name: "Day 1 - Upper A"))
        try brokenContext.save()

        let restoreResult = try await UserDataCloudBackupService(
            localContainer: brokenContainer,
            backupStore: backupStore
        ).restoreLatestBackup(replacingLocalData: true)

        let restoredContext = ModelContext(brokenContainer)
        let restoredTemplates = try restoredContext.fetch(FetchDescriptor<WorkoutTemplate>())
        let restoredExercises = try restoredContext.fetch(FetchDescriptor<TemplateExercise>())
        let restoredTemplate = try XCTUnwrap(restoredTemplates.first)
        let restoredExercise = try XCTUnwrap(restoredExercises.first)
        XCTAssertNotNil(restoreResult)
        XCTAssertEqual(restoredTemplates.count, 1)
        XCTAssertEqual(restoredExercises.count, 1)
        XCTAssertEqual(restoredExercise.exerciseNameSnapshot, "Lat Pulldown")
        XCTAssertEqual(restoredTemplate.folder?.id, folderID)
        XCTAssertEqual(restoredTemplate.exercises?.map(\.id), [exerciseID])
        XCTAssertEqual(restoredExercise.template?.id, templateID)
    }

    func testRestoreLatestBackupReplacingLocalDataClearsActiveWorkoutSnapshot() async throws {
        try? await ActiveWorkoutSnapshotStore.shared.delete()
        addTeardownBlock {
            try? await ActiveWorkoutSnapshotStore.shared.delete()
        }

        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        sourceContext.autosaveEnabled = false
        sourceContext.insert(WorkoutTemplate(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            folderID: TemplateRepository.unfiledFolderID,
            name: "Cloud Template"
        ))
        try sourceContext.save()

        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: sourceContainer,
            backupStore: backupStore
        ).exportCurrentBackup()

        let staleSnapshot = ActiveWorkoutRuntimeSession(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "Stale Local Workout",
            startedAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try await ActiveWorkoutSnapshotStore.shared.save(staleSnapshot)

        let restoreContainer = try makeInMemoryContainer()
        _ = try await UserDataCloudBackupService(
            localContainer: restoreContainer,
            backupStore: backupStore
        ).restoreLatestBackup(replacingLocalData: true)

        let storedSnapshot = try await ActiveWorkoutSnapshotStore.shared.loadStoredSnapshot()
        XCTAssertNil(storedSnapshot)
    }

    func testDeletingFolderRemovesTemplateRowsFromNextBackup() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let folderID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let templateID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let exerciseID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let setID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!

        for model in [
            TemplateFolder(id: folderID, name: "Bro Split"),
            WorkoutTemplate(id: templateID, folderID: folderID, name: "Day 1"),
            TemplateCardioBlock(
                id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
                templateID: templateID,
                phase: .preWorkout,
                catalogExerciseUUID: "crosstrainer",
                exerciseNameSnapshot: "Crosstrainer",
                categorySnapshot: "Cardio",
                muscleSummarySnapshot: "Quads",
                targetDurationSeconds: 300
            ),
            TemplateSupersetGroup(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                templateID: templateID,
                roundRestSeconds: 120
            ),
            TemplateExercise(
                id: exerciseID,
                templateID: templateID,
                catalogExerciseUUID: "lat-pulldown",
                exerciseNameSnapshot: "Lat Pulldown",
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Back"
            ),
            TemplateExerciseComponent(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                templateExerciseID: exerciseID,
                catalogExerciseUUID: "lat-pulldown",
                exerciseNameSnapshot: "Lat Pulldown",
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Back"
            ),
            TemplateExerciseSet(
                id: setID,
                templateExerciseID: exerciseID,
                targetReps: 10,
                targetWeight: 60
            ),
            TemplateExerciseDropStage(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                templateExerciseSetID: setID,
                targetReps: 8,
                targetWeight: 40
            ),
        ] as [any PersistentModel] {
            context.insert(model)
        }
        try context.save()

        try TemplateRepository(modelContext: context).deleteFolder(id: folderID)
        let snapshot = try await UserDataCloudBackupService(
            localContainer: container,
            backupStore: CapturingBackupStore()
        ).exportCurrentBackup()

        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TemplateExercise>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TemplateExerciseSet>()).count, 0)
        XCTAssertEqual(snapshot.contentSummary.templateFolderCount, 0)
        XCTAssertEqual(snapshot.contentSummary.workoutTemplateCount, 0)
        XCTAssertEqual(snapshot.contentSummary.templateExerciseCount, 0)
    }

    func testExportCurrentBackupPrunesOrphanedTemplateRows() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let missingFolderID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let templateID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutTemplate(id: templateID, folderID: missingFolderID, name: "Deleted Folder Template"))
        context.insert(TemplateExercise(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            templateID: templateID,
            catalogExerciseUUID: "lat-pulldown",
            exerciseNameSnapshot: "Lat Pulldown",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back"
        ))
        try context.save()

        let snapshot = try await UserDataCloudBackupService(
            localContainer: container,
            backupStore: CapturingBackupStore()
        ).exportCurrentBackup()

        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TemplateExercise>()).count, 0)
        XCTAssertEqual(snapshot.contentSummary.workoutTemplateCount, 0)
        XCTAssertEqual(snapshot.contentSummary.templateExerciseCount, 0)
    }

    func testHistoryOverviewSummaryUsesSessionExerciseIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Day 4 - Lower B",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            totalVolume: 600
        ))
        context.insert(WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "lat-pulldown",
            exerciseNameSnapshot: "Lat Pulldown",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            totalSetCount: 1,
            completedSetCount: 1,
            sortOrder: 0
        ))
        context.insert(WorkoutSessionSet(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            sessionExerciseID: exerciseID,
            sortOrder: 0,
            actualReps: 10,
            actualWeight: 60,
            isCompleted: true
        ))
        context.insert(WorkoutSessionCardioBlock(
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
            isCompleted: true
        ))
        try context.save()

        let loaded = try HistoryOverviewSnapshotLoader.load(
            modelContext: context,
            selectedDayFilter: nil,
            pageSize: 10
        )

        let rows = try XCTUnwrap(loaded.completedSessions.first?.summaryRows)
        XCTAssertEqual(rows.map(\.exercise), ["1 x Lat Pulldown", "Bike"])
        XCTAssertNotEqual(rows.first?.bestSet, "-")
        XCTAssertEqual(rows.last?.bestSet, "10 min")
    }

    func testHistoryOverviewBatchLoadingPreservesPaginationAndSummaries() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let fixtures: [(name: String, completedAt: TimeInterval, weight: Double)] = [
            ("Recent", 300, 90),
            ("Middle", 200, 80),
            ("Old", 100, 70),
        ]

        for (index, fixture) in fixtures.enumerated() {
            let session = WorkoutSession(
                name: fixture.name,
                status: .completed,
                startedAt: Date(timeIntervalSince1970: fixture.completedAt - 60),
                endedAt: Date(timeIntervalSince1970: fixture.completedAt),
                durationSeconds: 60
            )
            let exercise = WorkoutSessionExercise(
                sessionID: session.id,
                catalogExerciseUUID: "exercise-\(index)",
                exerciseNameSnapshot: "Exercise \(index)",
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Muscle",
                sortOrder: 0
            )
            let set = WorkoutSessionSet(
                sessionExerciseID: exercise.id,
                sortOrder: 0,
                actualReps: 10,
                actualWeight: fixture.weight,
                isCompleted: true
            )
            context.insert(session)
            context.insert(exercise)
            context.insert(set)
        }
        try context.save()

        let firstPage = try HistoryOverviewSnapshotLoader.load(
            modelContext: context,
            selectedDayFilter: nil,
            pageSize: 2
        )
        XCTAssertEqual(firstPage.completedSessions.map(\.name), ["Recent", "Middle"])
        XCTAssertTrue(firstPage.hasMorePages)
        XCTAssertEqual(firstPage.completedSessions.flatMap(\.summaryRows).count, 2)

        let lastLoaded = try XCTUnwrap(firstPage.completedSessions.last)
        let secondPage = try HistoryOverviewSnapshotLoader.loadPage(
            modelContext: context,
            after: WorkoutSessionPageCursor(
                completedAt: lastLoaded.displayDate,
                sessionID: lastLoaded.id
            ),
            pageSize: 2
        )
        XCTAssertEqual(secondPage.completedSessions.map(\.name), ["Old"])
        XCTAssertFalse(secondPage.hasMorePages)
        XCTAssertEqual(secondPage.completedSessions.first?.summaryRows.first?.exercise, "1 x Exercise 2")
        XCTAssertNotEqual(secondPage.completedSessions.first?.summaryRows.first?.bestSet, "-")
    }

    func testHistoryQueriesUseDisplayedCompletionDayForOvernightWorkouts() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startedAt = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2025,
            month: 12,
            day: 31,
            hour: 23,
            minute: 30
        )))
        let endedAt = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 1,
            hour: 0,
            minute: 30
        )))
        let selectedDay = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 1
        )))
        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        context.insert(WorkoutSession(
            id: sessionID,
            name: "New Year Session",
            status: .completed,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: 3_600
        ))
        try context.save()

        let repository = WorkoutSessionRepository(modelContext: context)
        let sessions = try repository.completedSessions(onDay: selectedDay, calendar: calendar)
        let counts = try repository.completedWorkoutCountsByDay(inMonthContaining: selectedDay, calendar: calendar)

        XCTAssertEqual(sessions.map(\.id), [sessionID])
        XCTAssertEqual(counts[calendar.startOfDay(for: selectedDay)], 1)
    }

    func testCompletedSessionsAreOrderedAndPagedByDisplayedCompletionDate() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let latestCompletionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let earlierCompletionID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let latestCompletion = WorkoutSession(
            id: latestCompletionID,
            name: "Started Earlier, Finished Later",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 400),
            durationSeconds: 300
        )
        let earlierCompletion = WorkoutSession(
            id: earlierCompletionID,
            name: "Started Later, Finished Earlier",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 300),
            endedAt: Date(timeIntervalSince1970: 350),
            durationSeconds: 50
        )
        context.insert(latestCompletion)
        context.insert(earlierCompletion)
        try context.save()

        let repository = WorkoutSessionRepository(modelContext: context)
        let firstPage = try repository.completedSessions(before: nil, limit: 1)
        let nextPage = try repository.completedSessions(before: Date(timeIntervalSince1970: 375), limit: 10)

        XCTAssertEqual(firstPage.map(\.id), [latestCompletionID])
        XCTAssertEqual(nextPage.map(\.id), [earlierCompletionID])
    }

    func testCompletedSessionsTreatMissingEndDateAsStartedDateWhenOrderingAndPaging() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let inProgressCompletionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let earlierCompletedID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutSession(
            id: inProgressCompletionID,
            name: "Legacy Completed Session",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 500),
            endedAt: nil,
            durationSeconds: 0
        ))
        context.insert(WorkoutSession(
            id: earlierCompletedID,
            name: "Earlier Completed Session",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 400),
            durationSeconds: 300
        ))
        try context.save()

        let repository = WorkoutSessionRepository(modelContext: context)
        let firstPage = try repository.completedSessions(before: nil, limit: 1)
        let nextPage = try repository.completedSessions(before: Date(timeIntervalSince1970: 450), limit: 10)

        XCTAssertEqual(firstPage.map(\.id), [inProgressCompletionID])
        XCTAssertEqual(nextPage.map(\.id), [earlierCompletedID])
    }

    func testCompletedSessionCursorDoesNotSkipMatchingCompletionTimestamps() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let completionDate = Date(timeIntervalSince1970: 500)
        let orderedIDs = [
            UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        ]
        for id in orderedIDs {
            context.insert(WorkoutSession(
                id: id,
                name: id.uuidString,
                status: .completed,
                startedAt: completionDate.addingTimeInterval(-100),
                endedAt: completionDate
            ))
        }
        try context.save()

        let repository = WorkoutSessionRepository(modelContext: context)
        let firstPage = try repository.completedSessions(after: nil, limit: 2)
        let cursor = WorkoutSessionPageCursor(
            completedAt: try XCTUnwrap(firstPage.last?.endedAt),
            sessionID: try XCTUnwrap(firstPage.last?.id)
        )
        let secondPage = try repository.completedSessions(after: cursor, limit: 2)

        XCTAssertEqual(firstPage.map(\.id), Array(orderedIDs.prefix(2)))
        XCTAssertEqual(secondPage.map(\.id), [orderedIDs[2]])
    }

    func testCompletedSessionPageMergesLegacyAndEndedDatesInDisplayOrder() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let expectedIDs = [
            UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        ]
        context.insert(WorkoutSession(
            id: expectedIDs[0],
            name: "Legacy newest",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 600),
            endedAt: nil
        ))
        context.insert(WorkoutSession(
            id: expectedIDs[1],
            name: "Ended middle",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 500)
        ))
        context.insert(WorkoutSession(
            id: expectedIDs[2],
            name: "Legacy oldest",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 400),
            endedAt: nil
        ))
        try context.save()

        let page = try WorkoutSessionRepository(modelContext: context)
            .completedSessions(after: nil, limit: 3)

        XCTAssertEqual(page.map(\.id), expectedIDs)
    }

    func testWorkoutHeatmapCatalogMappingsCanBeScopedToWorkoutExercises() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        context.insert(ExerciseCatalogItem(remoteUUID: "bench", displayName: "Bench Press"))
        context.insert(ExerciseCatalogItem(remoteUUID: "squat", displayName: "Squat"))
        try context.save()

        let mappings = try WorkoutMuscleHeatmapBuilder.catalogMappings(
            modelContext: context,
            catalogExerciseUUIDs: ["bench"]
        )

        XCTAssertEqual(Set(mappings.keys), ["bench"])
    }

    func testHistoryProjectionUsesSessionExerciseIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Day 4 - Lower B",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        ))
        context.insert(WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "lat-pulldown",
            exerciseNameSnapshot: "Lat Pulldown",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            sortOrder: 0
        ))
        context.insert(WorkoutSessionSet(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            sessionExerciseID: exerciseID,
            sortOrder: 0,
            actualReps: 10,
            actualWeight: 60,
            isCompleted: true
        ))
        try context.save()

        XCTAssertEqual(try HistoryProjectionRepository(modelContext: context).backfillIfNeeded(), 1)
        let facts = try context.fetch(FetchDescriptor<CompletedSetFact>())
        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts.first?.catalogExerciseUUID, "lat-pulldown")
        XCTAssertEqual(facts.first?.exerciseNameSnapshot, "Lat Pulldown")
    }

    func testWorkoutMetricsUseSessionExerciseIDsForPRsAndVolume() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let olderSessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let olderExerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutSession(
            id: olderSessionID,
            name: "Older Lower",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        ))
        context.insert(WorkoutSessionExercise(
            id: olderExerciseID,
            sessionID: olderSessionID,
            catalogExerciseUUID: "leg-press",
            exerciseNameSnapshot: "Leg Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Quadriceps",
            sortOrder: 0
        ))
        context.insert(WorkoutSessionSet(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            sessionExerciseID: olderExerciseID,
            sortOrder: 0,
            actualReps: 8,
            actualWeight: 100,
            isCompleted: true
        ))

        let newerSessionID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let newerExerciseID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        context.insert(WorkoutSession(
            id: newerSessionID,
            name: "Newer Lower",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 300),
            endedAt: Date(timeIntervalSince1970: 400)
        ))
        context.insert(WorkoutSessionExercise(
            id: newerExerciseID,
            sessionID: newerSessionID,
            catalogExerciseUUID: "leg-press",
            exerciseNameSnapshot: "Leg Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Quadriceps",
            sortOrder: 0
        ))
        context.insert(WorkoutSessionSet(
            id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            sessionExerciseID: newerExerciseID,
            sortOrder: 0,
            actualReps: 8,
            actualWeight: 120,
            isCompleted: true
        ))
        try context.save()

        _ = try HistoryProjectionRepository(modelContext: context).backfillIfNeeded()

        let metrics = WorkoutMetricsService(modelContext: context)
        let sessionPRs = try metrics.sessionPRAchievements(sessionID: newerSessionID)
        let setPRs = try metrics.sessionSetPRAchievements(sessionID: newerSessionID)
        let summary = try metrics.sessionSummary(sessionID: newerSessionID)

        XCTAssertEqual(sessionPRs.map(\.exerciseName), ["Leg Press"])
        XCTAssertEqual(setPRs.count, 1)
        XCTAssertEqual(Set(setPRs[0].kinds), Set([.strength, .weight, .volume]))
        XCTAssertEqual(summary.totalVolume, 960)
        XCTAssertEqual(summary.prHitsCount, 1)
    }

    func testHistoryDetailUsesSessionSetIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Day 4 - Lower B",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        ))
        context.insert(WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "leg-press",
            exerciseNameSnapshot: "Leg Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Quadriceps",
            totalSetCount: 1,
            completedSetCount: 1
        ))
        context.insert(WorkoutSessionSet(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            sessionExerciseID: exerciseID,
            actualReps: 7,
            actualWeight: 120,
            isCompleted: true
        ))
        try context.save()

        let snapshot = try HistoryDetailSnapshotBuilder.load(
            modelContext: context,
            sessionID: sessionID
        )

        let drafts = snapshot.localState.setDraftsByExerciseID[exerciseID]
        XCTAssertEqual(drafts?.count, 1)
        XCTAssertEqual(drafts?.first?.actualReps, 7)
        XCTAssertEqual(drafts?.first?.actualWeight, 120)
    }

    func testHistoryDetailExposesPersonalRecordHighlights() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let olderSessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let olderExerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutSession(
            id: olderSessionID,
            name: "Older Lower",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        ))
        context.insert(WorkoutSessionExercise(
            id: olderExerciseID,
            sessionID: olderSessionID,
            catalogExerciseUUID: "leg-press",
            exerciseNameSnapshot: "Leg Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Quadriceps",
            sortOrder: 0
        ))
        context.insert(WorkoutSessionSet(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            sessionExerciseID: olderExerciseID,
            sortOrder: 0,
            actualReps: 8,
            actualWeight: 100,
            isCompleted: true
        ))

        let newerSessionID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let newerExerciseID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let newerSetID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        context.insert(WorkoutSession(
            id: newerSessionID,
            name: "Newer Lower",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 300),
            endedAt: Date(timeIntervalSince1970: 400)
        ))
        context.insert(WorkoutSessionExercise(
            id: newerExerciseID,
            sessionID: newerSessionID,
            catalogExerciseUUID: "leg-press",
            exerciseNameSnapshot: "Leg Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Quadriceps",
            sortOrder: 0
        ))
        context.insert(WorkoutSessionSet(
            id: newerSetID,
            sessionExerciseID: newerExerciseID,
            sortOrder: 0,
            actualReps: 8,
            actualWeight: 120,
            isCompleted: true
        ))
        try context.save()

        _ = try HistoryProjectionRepository(modelContext: context).backfillIfNeeded()

        let snapshot = try HistoryDetailSnapshotBuilder.load(
            modelContext: context,
            sessionID: newerSessionID
        )

        XCTAssertEqual(snapshot.personalRecordHighlights.count, 1)
        XCTAssertEqual(snapshot.personalRecordHighlights[0].sessionExerciseID, newerExerciseID)
        XCTAssertEqual(snapshot.personalRecordHighlights[0].setID, newerSetID)
        XCTAssertEqual(snapshot.personalRecordHighlights[0].exerciseName, "Leg Press")
        XCTAssertEqual(snapshot.personalRecordHighlights[0].setTitle, "Working Set 1")
        XCTAssertEqual(snapshot.personalRecordHighlights[0].performanceText, "120 kg x 8")
        XCTAssertEqual(snapshot.personalRecordHighlights[0].detailText, "Strength + Weight + Volume PR · 152 kg e1RM")
    }

    func testPreviousValuesUseSessionSetIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Day 4 - Lower B",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        ))
        context.insert(WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "leg-press",
            exerciseNameSnapshot: "Leg Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Quadriceps"
        ))
        context.insert(WorkoutSessionSet(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            sessionExerciseID: exerciseID,
            actualReps: 7,
            actualWeight: 120,
            isCompleted: true
        ))
        try context.save()

        let previousMaps = try WorkoutSessionRepository(modelContext: context).previousSetMaps(
            forExercises: ["leg-press"],
            before: Date(timeIntervalSince1970: 300),
            excludingSessionID: nil
        )

        XCTAssertEqual(previousMaps["leg-press"]?[0]?.reps, 7)
        XCTAssertEqual(previousMaps["leg-press"]?[0]?.weight, 120)
    }

    func testActiveWorkoutTemplateStartUsesTemplateChildIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let templateID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let setID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        context.insert(WorkoutTemplate(
            id: templateID,
            folderID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            name: "Day 1 - Upper A"
        ))
        context.insert(TemplateCardioBlock(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            templateID: templateID,
            phase: .preWorkout,
            catalogExerciseUUID: "crosstrainer",
            exerciseNameSnapshot: "Crosstrainer",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Quadriceps",
            targetDurationSeconds: 300
        ))
        context.insert(TemplateExercise(
            id: exerciseID,
            templateID: templateID,
            catalogExerciseUUID: "lat-pulldown",
            exerciseNameSnapshot: "Lat Pulldown",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            targetRepMin: 8,
            targetRepMax: 12,
            restSeconds: 120
        ))
        context.insert(TemplateExerciseComponent(
            id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            templateExerciseID: exerciseID,
            catalogExerciseUUID: "lat-pulldown-wide",
            exerciseNameSnapshot: "Wide Lat Pulldown",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            sortOrder: 0
        ))
        context.insert(TemplateExerciseSet(
            id: setID,
            templateExerciseID: exerciseID,
            targetReps: 10,
            targetWeight: 60,
            loadUnit: .kg
        ))
        context.insert(TemplateExerciseDropStage(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            templateExerciseSetID: setID,
            targetReps: 8,
            targetWeight: 45,
            loadUnit: .kg
        ))
        try context.save()

        let session = try ActiveWorkoutSessionFactory(modelContext: context)
            .createSessionFromTemplate(templateID: templateID)

        XCTAssertEqual(session.cardioBlocks.count, 1)
        XCTAssertEqual(session.exercises.count, 1)
        XCTAssertEqual(session.exercises.first?.components.count, 1)
        XCTAssertEqual(session.exercises.first?.exerciseNameSnapshot, "Wide Lat Pulldown")
        XCTAssertEqual(session.exercises.first?.setDrafts.count, 1)
        XCTAssertEqual(session.exercises.first?.setDrafts.first?.targetReps, 10)
        XCTAssertEqual(session.exercises.first?.setDrafts.first?.targetWeight, 60)
        XCTAssertEqual(session.exercises.first?.setDrafts.first?.dropStages.first?.targetWeight, 45)
    }

    func testCreateTemplateFromWorkoutUsesSessionSetIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let setID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Day 4 - Lower B",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        ))
        context.insert(WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "leg-press",
            exerciseNameSnapshot: "Leg Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Quadriceps",
            restSeconds: 150
        ))
        context.insert(WorkoutSessionSet(
            id: setID,
            sessionExerciseID: exerciseID,
            actualReps: 7,
            actualWeight: 120,
            actualLoadUnit: .kg,
            isCompleted: true
        ))
        context.insert(WorkoutSessionDropStage(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            sessionSetID: setID,
            actualReps: 5,
            actualWeight: 90,
            actualLoadUnit: .kg,
            isCompleted: true
        ))
        try context.save()

        _ = try TemplateRepository(modelContext: context)
            .createTemplate(fromSessionID: sessionID, name: "Copied Lower")

        let templateSets = try context.fetch(FetchDescriptor<TemplateExerciseSet>())
        let templateDropStages = try context.fetch(FetchDescriptor<TemplateExerciseDropStage>())
        XCTAssertEqual(templateSets.count, 1)
        XCTAssertEqual(templateSets.first?.targetReps, 7)
        XCTAssertEqual(templateSets.first?.targetWeight, 120)
        XCTAssertEqual(templateDropStages.first?.targetReps, 5)
        XCTAssertEqual(templateDropStages.first?.targetWeight, 90)
    }

    func testProgressComparisonUsesSessionChildIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let templateID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let olderSessionID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let newerSessionID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let olderExerciseID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let newerExerciseID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!

        for model in [
            WorkoutSession(
                id: olderSessionID,
                templateID: templateID,
                name: "Day 4 - Lower B",
                status: .completed,
                startedAt: Date(timeIntervalSince1970: 100),
                endedAt: Date(timeIntervalSince1970: 200)
            ),
            WorkoutSession(
                id: newerSessionID,
                templateID: templateID,
                name: "Day 4 - Lower B",
                status: .completed,
                startedAt: Date(timeIntervalSince1970: 300),
                endedAt: Date(timeIntervalSince1970: 400)
            ),
            WorkoutSessionExercise(
                id: olderExerciseID,
                sessionID: olderSessionID,
                catalogExerciseUUID: "leg-press",
                exerciseNameSnapshot: "Leg Press",
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Quadriceps"
            ),
            WorkoutSessionExercise(
                id: newerExerciseID,
                sessionID: newerSessionID,
                catalogExerciseUUID: "leg-press",
                exerciseNameSnapshot: "Leg Press",
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Quadriceps"
            ),
            WorkoutSessionSet(
                sessionExerciseID: olderExerciseID,
                actualReps: 8,
                actualWeight: 100,
                isCompleted: true
            ),
            WorkoutSessionSet(
                sessionExerciseID: newerExerciseID,
                actualReps: 8,
                actualWeight: 120,
                isCompleted: true
            ),
        ] as [any PersistentModel] {
            context.insert(model)
        }
        try context.save()

        let snapshot = try WorkoutProgressSnapshotLoader.load(
            modelContext: context,
            selectedPreviousSessionID: olderSessionID,
            selectedCurrentSessionID: newerSessionID
        )

        guard case let .ready(comparison) = snapshot.state else {
            return XCTFail("Expected progress comparison")
        }
        XCTAssertEqual(comparison.exerciseComparisons.count, 1)
        XCTAssertEqual(comparison.exerciseComparisons.first?.exerciseName, "Leg Press")
        XCTAssertEqual(comparison.exerciseComparisons.first?.direction, .up)
        XCTAssertEqual(comparison.currentWorkout.completedSetCount, 1)
    }

    func testProgressLoaderReturnsInsufficientHistoryWithNoCompletedWorkouts() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let snapshot = try WorkoutProgressSnapshotLoader.load(
            modelContext: context,
            selectedPreviousSessionID: nil,
            selectedCurrentSessionID: nil
        )

        XCTAssertEqual(snapshot.state, .insufficientHistory(availableWorkoutCount: 0))
        XCTAssertTrue(snapshot.workoutOptions.isEmpty)
    }

    func testProgressLoaderReturnsInsufficientHistoryWithOneCompletedWorkout() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Only Workout",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        ))
        try context.save()

        let snapshot = try WorkoutProgressSnapshotLoader.load(
            modelContext: context,
            selectedPreviousSessionID: nil,
            selectedCurrentSessionID: nil
        )

        XCTAssertEqual(snapshot.state, .insufficientHistory(availableWorkoutCount: 1))
        XCTAssertEqual(snapshot.workoutOptions.map(\.sessionID), [sessionID])
    }

    func testHistoryDetailMuscleHeatmapUsesSessionSetIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        for model in [
            WorkoutSession(
                id: sessionID,
                name: "Day 4 - Lower B",
                status: .completed,
                startedAt: Date(timeIntervalSince1970: 100),
                endedAt: Date(timeIntervalSince1970: 200)
            ),
            WorkoutSessionExercise(
                id: exerciseID,
                sessionID: sessionID,
                catalogExerciseUUID: "custom-leg-press",
                exerciseNameSnapshot: "Leg Press",
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Quadriceps"
            ),
            WorkoutSessionSet(
                sessionExerciseID: exerciseID,
                actualReps: 8,
                actualWeight: 120,
                isCompleted: true
            ),
        ] as [any PersistentModel] {
            context.insert(model)
        }
        try context.save()

        let snapshot = try HistoryDetailSnapshotBuilder.load(
            modelContext: context,
            sessionID: sessionID
        )

        XCTAssertFalse(snapshot.muscleHeatmap.entries.isEmpty)
        XCTAssertTrue(snapshot.muscleHeatmap.topRegionNames.contains("Quadriceps"))
    }

    func testExportCurrentBackupIncludesOnlyCompletedWorkoutChildren() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let completedSession = WorkoutSession(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Completed",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100
        )
        let completedExercise = WorkoutSessionExercise(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            sessionID: completedSession.id,
            catalogExerciseUUID: "completed-bench",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            totalSetCount: 1,
            completedSetCount: 1,
            session: completedSession
        )
        let completedSet = WorkoutSessionSet(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            sessionExerciseID: completedExercise.id,
            sortOrder: 0,
            actualReps: 8,
            actualWeight: 100,
            isCompleted: true,
            sessionExercise: completedExercise
        )

        let activeSession = WorkoutSession(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            name: "Active",
            status: .active,
            startedAt: Date(timeIntervalSince1970: 300)
        )
        let activeExercise = WorkoutSessionExercise(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            sessionID: activeSession.id,
            catalogExerciseUUID: "active-squat",
            exerciseNameSnapshot: "Squat",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Legs",
            totalSetCount: 1,
            completedSetCount: 0,
            session: activeSession
        )
        let activeSet = WorkoutSessionSet(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            sessionExerciseID: activeExercise.id,
            sortOrder: 0,
            actualReps: 5,
            actualWeight: 120,
            isCompleted: false,
            sessionExercise: activeExercise
        )

        for model in [
            completedSession,
            completedExercise,
            completedSet,
            activeSession,
            activeExercise,
            activeSet,
        ] as [any PersistentModel] {
            context.insert(model)
        }
        try context.save()

        let backupStore = CapturingBackupStore()
        let snapshot = try await UserDataCloudBackupService(
            localContainer: container,
            backupStore: backupStore
        ).exportCurrentBackup()

        let summary = snapshot.contentSummary
        let completedWorkoutCount = summary.completedWorkoutCount
        let workoutExerciseCount = summary.workoutExerciseCount
        let workoutSetCount = summary.workoutSetCount
        XCTAssertEqual(completedWorkoutCount, 1)
        XCTAssertEqual(workoutExerciseCount, 1)
        XCTAssertEqual(workoutSetCount, 1)
    }

    func testStartupMetadataChecksRunOnceAndExplicitRefreshCanRunAgain() async throws {
        let state = AppRuntimeState.makeTestingInstance()
        let context = ModelContext(try makeInMemoryContainer())
        let summary = try UserDataCloudBackupContentSummary.loadLocal(context: context)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let metadata = UserDataCloudBackupRemoteMetadata(updatedAt: .now, contentSummary: summary)
        for _ in 0..<20 {
            await CloudBackupStatusCheckScheduler.checkMetadata(isStartup: true, state: state) {
                calls.withLock { $0 += 1 }
                return metadata
            }
        }
        XCTAssertEqual(calls.withLock { $0 }, 1)
        XCTAssertEqual(state.cloudBackupContentSummary, summary)
        await CloudBackupStatusCheckScheduler.checkMetadata(isStartup: false, state: state) {
            calls.withLock { $0 += 1 }
            return nil
        }
        XCTAssertEqual(calls.withLock { $0 }, 2)
        XCTAssertNil(state.cloudBackupContentSummary)
        XCTAssertNil(state.cloudBackupUpdatedAt)
    }

    func testFailedStartupCheckDoesNotRetryOnNavigation() async {
        let state = AppRuntimeState.makeTestingInstance()
        let calls = OSAllocatedUnfairLock(initialState: 0)
        for _ in 0..<10 {
            await CloudBackupStatusCheckScheduler.checkMetadata(isStartup: true, state: state) {
                calls.withLock { $0 += 1 }
                throw CKError(.networkUnavailable)
            }
        }
        XCTAssertEqual(calls.withLock { $0 }, 1)
        XCTAssertEqual(state.userDataSyncStatus.state, .checkFailed)
    }

    func testOlderMetadataCannotReplaceUploadedCountsAndResetRejectsOldAccountResults() throws {
        let state = AppRuntimeState.makeTestingInstance()
        let context = ModelContext(try makeInMemoryContainer())
        let summary = try UserDataCloudBackupContentSummary.loadLocal(context: context)
        let snapshot = UserDataCloudBackupRemoteSnapshot(updatedAt: .now, contentSummary: summary)
        let check = try XCTUnwrap(state.beginCloudBackupMetadataCheck(isStartup: true))
        state.recordSuccessfulCloudBackup(snapshot)
        state.finishCloudBackupMetadataCheck(nil, matching: check)
        XCTAssertEqual(state.cloudBackupContentSummary, summary)
        XCTAssertEqual(state.cloudBackupUpdatedAt, snapshot.updatedAt)
        state.updateUserDataSyncStatus(.pending())
        XCTAssertNil(state.beginCloudBackupMetadataCheck(isStartup: false))
        state.updateUserDataSyncStatus(.degraded("Offline"))
        XCTAssertEqual(state.cloudBackupUpdatedAt, snapshot.updatedAt)
        let oldSession = state.cloudBackupSessionRevision
        state.resetCloudBackupSession()
        state.recordSuccessfulCloudBackup(snapshot, sessionRevision: oldSession)
        XCTAssertNil(state.cloudBackupContentSummary)
        XCTAssertNotNil(state.beginCloudBackupMetadataCheck(isStartup: true))
        state.recordCloudBackupDeletion()
        state.finishCloudBackupMetadataCheck(.init(updatedAt: snapshot.updatedAt, contentSummary: summary), matching: check)
        XCTAssertNil(state.cloudBackupContentSummary)
    }

    func testLegacyMetadataDoesNotClaimTheBackupIsMissingOrKeepOldCounts() throws {
        let state = AppRuntimeState.makeTestingInstance()
        let context = ModelContext(try makeInMemoryContainer())
        let summary = try UserDataCloudBackupContentSummary.loadLocal(context: context)
        state.recordSuccessfulCloudBackup(.init(updatedAt: .distantPast, contentSummary: summary))
        let check = try XCTUnwrap(state.beginCloudBackupMetadataCheck(isStartup: false))
        let date = Date()
        state.finishCloudBackupMetadataCheck(.init(updatedAt: date), matching: check)
        XCTAssertNil(state.cloudBackupContentSummary)
        XCTAssertEqual(state.cloudBackupUpdatedAt, date)
        XCTAssertTrue(state.userDataSyncStatus.hasKnownRemoteBackup)
    }

    func testExportCarriesSummaryWithoutFetchingTheBackupAgain() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(UserProfile(displayName: "Athlete"))
        try context.save()
        let store = CapturingBackupStore()
        let exported = try await UserDataCloudBackupService(localContainer: container, backupStore: store).exportCurrentBackup()
        let readsAfterExport = await store.payloadReadCount()
        XCTAssertEqual(readsAfterExport, 0)
        let stored = try await store.fetchBackup()
        XCTAssertEqual(stored?.contentSummary, exported.contentSummary)
        XCTAssertEqual(exported.contentSummary.profileCount, 1)
        let encoded = try JSONEncoder().encode(exported.contentSummary)
        XCTAssertEqual(try JSONDecoder().decode(UserDataCloudBackupContentSummary.self, from: encoded), exported.contentSummary)
    }

    func testProfileNavigationDoesNotRequestRemoteContents() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("WGJ/Views/Profile/ProfileView.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("latestBackupSnapshot("))
        XCTAssertFalse(source.contains("refreshCloudBackupDetails"))
        XCTAssertFalse(source.contains("shouldRetryCloudBackupDetailsWhenAvailable"))
    }

    func testWidgetReadsStayLocalAndExplicitMutationsBackUpOnce() throws {
        let context = ModelContext(try makeInMemoryContainer())
        context.autosaveEnabled = false
        let reasons = OSAllocatedUnfairLock(initialState: [BoundaryCloudBackupReason]())
        let repository = ProfileWidgetRepository(modelContext: context, boundaryEffects: .init { _, reason in
            reasons.withLock { $0.append(reason) }
        })
        _ = try repository.configurations()
        _ = try repository.configurationSnapshots()
        XCTAssertTrue(reasons.withLock { $0.isEmpty })
        try repository.setEnabled(kind: .prs, isEnabled: false)
        try repository.setEnabled(kind: .prs, isEnabled: false)
        let config = try repository.createExerciseTrendConfig(metric: .oneRepMax, catalogExerciseUUID: "bench", exerciseName: "Bench", isEnabled: true)
        try repository.updateExerciseTrendConfig(id: config.id, metric: .oneRepMax, catalogExerciseUUID: "squat", exerciseName: "Squat")
        try repository.updateExerciseTrendConfig(id: config.id, metric: .oneRepMax, catalogExerciseUUID: "squat", exerciseName: "Squat")
        try repository.removeConfig(id: config.id)
        XCTAssertEqual(reasons.withLock { $0 }, Array(repeating: .profileWidgetsSaved, count: 4))
        XCTAssertFalse(context.hasChanges)
    }

    func testProfileBootstrapAndUnchangedSavesDoNotUpload() throws {
        let context = ModelContext(try makeInMemoryContainer())
        context.autosaveEnabled = false
        let reasons = OSAllocatedUnfairLock(initialState: [BoundaryCloudBackupReason]())
        let backfills = OSAllocatedUnfairLock(initialState: 0)
        let repository = ProfileRepository(modelContext: context, boundaryEffects: .init { _, reason in
            reasons.withLock { $0.append(reason) }
        }, scheduleCalorieBackfill: { _ in backfills.withLock { $0 += 1 } })
        _ = try repository.loadOrCreateProfile()
        XCTAssertTrue(reasons.withLock { $0.isEmpty })
        try repository.saveProfile(name: "Andy", athleteType: nil, avatarImageData: nil)
        try repository.saveProfile(name: "Andy", athleteType: nil, avatarImageData: nil)
        try repository.updateWeeklyWorkoutGoal(5)
        try repository.updateWeeklyWorkoutGoal(5)
        XCTAssertEqual(reasons.withLock { $0 }, [.profileSaved, .settingsSaved])
        let calories = WorkoutCalorieProfileSnapshot(sex: nil, dateOfBirth: nil, heightCentimeters: 180, bodyWeightKilograms: 80, showsCalorieEstimates: false)
        try repository.saveProfile(name: "Andy", athleteType: nil, avatarImageData: nil, calorieProfile: calories)
        try repository.saveProfile(name: "Andy", athleteType: nil, avatarImageData: nil, calorieProfile: calories)
        XCTAssertEqual(backfills.withLock { $0 }, 1)
        XCTAssertEqual(reasons.withLock { $0 }, [.profileSaved, .settingsSaved])
    }

    func testWorkoutCompletionBacksUpOnceIncludingRepeatedFinish() throws {
        let context = ModelContext(try makeInMemoryContainer())
        context.autosaveEnabled = false
        let reasons = OSAllocatedUnfairLock(initialState: [BoundaryCloudBackupReason]())
        let repository = WorkoutCompletionRepository(modelContext: context, boundaryEffects: .init { _, reason in
            reasons.withLock { $0.append(reason) }
        })
        let runtime = ActiveWorkoutRuntimeSession(name: "Push")
        _ = try repository.completeWorkout(session: runtime)
        _ = try repository.completeWorkout(session: runtime)
        XCTAssertEqual(reasons.withLock { $0 }, [.workoutCompleted])
    }

    func testCompletedWorkoutEditsArchiveRestoreAndDeleteBackUpAfterCommit() throws {
        let context = ModelContext(try makeInMemoryContainer())
        context.autosaveEnabled = false
        let session = WorkoutSession(name: "Push", status: .completed, endedAt: .now)
        context.insert(session)
        try context.save()
        let reasons = OSAllocatedUnfairLock(initialState: [BoundaryCloudBackupReason]())
        let repository = WorkoutSessionRepository(modelContext: context, weeklyGoalWidgetPublisher: nil, autoSaveChanges: false, boundaryEffects: .init { _, reason in
            reasons.withLock { $0.append(reason) }
        })
        try repository.updateSessionName(sessionID: session.id, name: "Pull")
        try repository.recalculateSessionSummary(sessionID: session.id)
        XCTAssertTrue(reasons.withLock { $0.isEmpty })
        try repository.finalizeDeferredUserDataChangesIfNeeded()
        try repository.finalizeDeferredUserDataChangesIfNeeded()
        XCTAssertEqual(reasons.withLock { $0 }, [.workoutEdited])
        try repository.archiveSession(id: session.id)
        try repository.finalizeDeferredUserDataChangesIfNeeded()
        try repository.archiveSession(id: session.id)
        try repository.finalizeDeferredUserDataChangesIfNeeded()
        try repository.restoreArchivedSession(id: session.id)
        try repository.finalizeDeferredUserDataChangesIfNeeded()
        try repository.deleteSession(id: session.id)
        try repository.finalizeDeferredUserDataChangesIfNeeded()
        XCTAssertEqual(reasons.withLock { $0 }, [.workoutEdited, .workoutEdited, .workoutEdited, .workoutDeleted])
        XCTAssertTrue(try ModelContext(context.container).fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
    }

    func testActiveWorkoutAndRolledBackHistoryEditsDoNotBackUp() throws {
        let context = ModelContext(try makeInMemoryContainer())
        context.autosaveEnabled = false
        let session = WorkoutSession(name: "Active", status: .active)
        context.insert(session)
        try context.save()
        let reasons = OSAllocatedUnfairLock(initialState: [BoundaryCloudBackupReason]())
        let repository = WorkoutSessionRepository(modelContext: context, weeklyGoalWidgetPublisher: nil, autoSaveChanges: false, boundaryEffects: .init { _, reason in
            reasons.withLock { $0.append(reason) }
        })
        try repository.updateSessionName(sessionID: session.id, name: "Active edit")
        try repository.recalculateSessionSummary(sessionID: session.id)
        try repository.finalizeDeferredUserDataChangesIfNeeded()
        XCTAssertTrue(reasons.withLock { $0.isEmpty })
        session.status = .completed
        try context.save()
        try repository.recalculateSessionSummary(sessionID: session.id)
        context.rollback()
        try repository.finalizeDeferredUserDataChangesIfNeeded()
        XCTAssertTrue(reasons.withLock { $0.isEmpty })
    }

    func testTemplateFolderAndDuplicateBoundariesUseTheInjectedScheduler() throws {
        let context = ModelContext(try makeInMemoryContainer())
        context.autosaveEnabled = false
        let reasons = OSAllocatedUnfairLock(initialState: [BoundaryCloudBackupReason]())
        let repository = TemplateRepository(modelContext: context, boundaryEffects: .init(postLibraryChange: {}, scheduleBackup: { _, reason in
            reasons.withLock { $0.append(reason) }
        }))
        let folder = try repository.createFolder(name: "Training")
        let template = try repository.createTemplate(folderID: folder.id, name: "Push", notes: "")
        try repository.updateTemplate(id: template.id, name: "Pull", notes: "")
        try repository.updateTemplate(id: template.id, name: "Pull", notes: "")
        let copy = try repository.duplicateTemplate(id: template.id)
        try repository.deleteTemplate(id: copy.id)
        try repository.deleteFolder(id: folder.id)
        XCTAssertEqual(reasons.withLock { $0 }, Array(repeating: .templateSaved, count: 6))
    }

    func testCustomExerciseCreateUpdateDeleteAndNoOpBoundaries() throws {
        let context = ModelContext(try makeInMemoryContainer())
        context.autosaveEnabled = false
        let reasons = OSAllocatedUnfairLock(initialState: [BoundaryCloudBackupReason]())
        let repository = ExerciseCatalogRepository(modelContext: context, boundaryEffects: .init { _, reason in
            reasons.withLock { $0.append(reason) }
        })
        var draft = CustomExerciseDraft.emptyCardio
        draft.name = "My Bike"
        let exercise = try repository.createCustomExercise(draft: draft)
        try repository.updateCustomExercise(exercise, draft: draft)
        XCTAssertEqual(reasons.withLock { $0 }, [.customExerciseSaved])
        draft.name = "My Stationary Bike"
        try repository.updateCustomExercise(exercise, draft: draft)
        try repository.deleteCustomExercise(exercise)
        XCTAssertEqual(reasons.withLock { $0 }, Array(repeating: .customExerciseSaved, count: 3))
        XCTAssertTrue(try ModelContext(context.container).fetch(FetchDescriptor<ExerciseCatalogItem>()).isEmpty)
    }

    func testAutomaticAndManualBackupsShareOneSerialCoalescingQueue() async throws {
        let container = try makeInMemoryContainer()
        let probe = BackupExportProbe()
        let queue = BoundaryCloudBackupExportQueue { _, reason, _ in await probe.export(reason) }
        await queue.enqueue(container: container, reason: .templateSaved, sessionRevision: 0)
        await probe.waitForStarts(1)
        await queue.enqueue(container: container, reason: .profileSaved, sessionRevision: 0)
        await queue.enqueue(container: container, reason: .settingsSaved, sessionRevision: 0)
        await probe.release()
        await probe.waitForStarts(2)
        await probe.release()
        let manual = Task { await queue.enqueueAndWait(container: container, sessionRevision: 0) }
        await probe.waitForStarts(3)
        await probe.release()
        await manual.value
        let recorded = await probe.recorded()
        XCTAssertEqual(recorded.reasons, [.templateSaved, .settingsSaved, .manual])
        XCTAssertEqual(recorded.maxConcurrent, 1)
    }

    func testMetadataRejectsCountsLeftBehindByAnOlderAppUpload() throws {
        let context = ModelContext(try makeInMemoryContainer())
        let summary = try UserDataCloudBackupContentSummary.loadLocal(context: context)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let data = try UserDataCloudBackupDescriptor.encodeSummary(summary, updatedAt: date)
        XCTAssertEqual(UserDataCloudBackupDescriptor.decodeSummary(data, updatedAt: date), summary)
        XCTAssertNil(UserDataCloudBackupDescriptor.decodeSummary(data, updatedAt: date.addingTimeInterval(1)))
        XCTAssertNil(UserDataCloudBackupDescriptor.decodeSummary(Data("invalid".utf8), updatedAt: date))
        XCTAssertNil(UserDataCloudBackupDescriptor.decodeSummary(nil, updatedAt: date))
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
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
            CachedCoachNarrative.self,
            CachedCoachFollowUpNarrative.self,
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
        ])

        return try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            ]
        )
    }
}

private actor CapturingBackupStore: UserDataCloudBackupStoring {
    private var record: UserDataCloudBackupRemoteRecord?
    private var payloadReads = 0

    func saveBackup(_ record: UserDataCloudBackupRemoteRecord) async throws {
        self.record = record
    }

    func deleteBackup() async throws {
        record = nil
    }

    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        payloadReads += 1
        return record
    }

    func payloadReadCount() -> Int { payloadReads }

    func fetchBackupMetadata() async throws -> UserDataCloudBackupRemoteMetadata? {
        nil
    }

    func replaceRecord(_ record: UserDataCloudBackupRemoteRecord) {
        self.record = record
    }
}

private actor BackupExportProbe {
    private var reasons: [BoundaryCloudBackupReason] = []
    private var active = 0
    private var maxConcurrent = 0
    private var releases: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func export(_ reason: BoundaryCloudBackupReason) async {
        active += 1
        maxConcurrent = max(maxConcurrent, active)
        reasons.append(reason)
        let ready = startWaiters.filter { $0.0 <= reasons.count }
        startWaiters.removeAll { $0.0 <= reasons.count }
        for (_, waiter) in ready { waiter.resume() }
        await withCheckedContinuation { releases.append($0) }
        active -= 1
    }

    func waitForStarts(_ count: Int) async {
        guard reasons.count < count else { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func release() { releases.removeFirst().resume() }
    func recorded() -> (reasons: [BoundaryCloudBackupReason], maxConcurrent: Int) { (reasons, maxConcurrent) }
}
