import HealthKit
import XCTest
@testable import WGJ

@MainActor
final class AppleHealthExportServiceTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var client: RecordingAppleHealthClient!
    private var journal: MemoryHealthExportJournalStore!
    private var service: AppleHealthExportService!

    override func setUp() async throws {
        suite = "AppleHealthExportTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        client = RecordingAppleHealthClient()
        journal = MemoryHealthExportJournalStore()
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDisabledByDefaultDoesNotAuthorizeOrExport() async {
        service.enqueue(workout())
        service.resumePending()
        XCTAssertFalse(service.isEnabled)
        XCTAssertFalse(service.sharesEstimatedCalories)
        XCTAssertTrue(client.authorizationRequests.isEmpty)
        XCTAssertTrue(client.saved.isEmpty)
        XCTAssertTrue(journal.value.pending.isEmpty)
    }

    func testDeniedWorkoutPermissionDoesNotEnableExport() async {
        client.canWriteWorkouts = false
        await service.setEnabled(true)
        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(client.authorizationRequests, [false])
        XCTAssertNotNil(service.message)
    }

    func testUnavailableHealthDoesNotRequestAuthorization() async {
        client.isAvailable = false
        await service.setEnabled(true)
        XCTAssertFalse(service.isEnabled)
        XCTAssertTrue(client.authorizationRequests.isEmpty)
    }

    func testWorkoutExportOmitsCaloriesUntilSeparatelyEnabledAndDeduplicates() async {
        await service.setEnabled(true)
        let snapshot = workout()
        service.enqueue(snapshot)
        service.enqueue(snapshot)
        await waitForExport()
        service.enqueue(snapshot)
        await waitForExport()
        XCTAssertEqual(client.saved.count, 1)
        XCTAssertNil(client.saved.first?.estimatedActiveCalories)
        XCTAssertTrue(journal.value.completedIDs.contains(snapshot.id))
        XCTAssertEqual(service.pendingCount, 0)
    }

    func testDeniedCaloriePermissionKeepsWorkoutExportEnabled() async {
        await service.setEnabled(true)
        client.canWriteEnergy = false
        await service.setSharesEstimatedCalories(true)
        XCTAssertTrue(service.isEnabled)
        XCTAssertFalse(service.sharesEstimatedCalories)
        XCTAssertEqual(client.authorizationRequests, [false, true])
        service.enqueue(workout())
        await waitForExport()
        XCTAssertNil(client.saved.first?.estimatedActiveCalories)
    }

    func testEstimatedCaloriesAreIncludedOnlyWithOptInAndPermission() async {
        await service.setEnabled(true)
        await service.setSharesEstimatedCalories(true)
        service.enqueue(workout())
        await waitForExport()
        XCTAssertEqual(client.saved.first?.estimatedActiveCalories, 105)
        XCTAssertEqual(client.saved.first?.calorieEstimateVersion, 2)
        XCTAssertEqual(client.authorizationRequests, [false, true])
    }

    func testFailedExportSurvivesServiceRecreationAndRetriesWithoutChangingIdentity() async {
        await service.setEnabled(true)
        client.failsSave = true
        let snapshot = workout()
        service.enqueue(snapshot)
        await waitForExport()
        XCTAssertEqual(service.pendingCount, 1)
        XCTAssertTrue(journal.value.completedIDs.isEmpty)

        client.failsSave = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.saved.map(\.syncIdentifier), [snapshot.syncIdentifier, snapshot.syncIdentifier])
        XCTAssertEqual(service.pendingCount, 0)
        XCTAssertTrue(journal.value.completedIDs.contains(snapshot.id))
    }

    func testRevokedWorkoutAccessKeepsQueueAndNeverPromptsOnRetry() async {
        await service.setEnabled(true)
        client.canWriteWorkouts = false
        service.enqueue(workout())
        service.resumePending()
        XCTAssertEqual(service.pendingCount, 1)
        XCTAssertTrue(client.saved.isEmpty)
        XCTAssertEqual(client.authorizationRequests, [false])
        client.canWriteWorkouts = true
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(service.pendingCount, 0)
    }

    func testDisablingCalorieSharingRemovesEstimatesFromPendingJobs() async {
        await service.setEnabled(true)
        await service.setSharesEstimatedCalories(true)
        client.failsSave = true
        service.enqueue(workout())
        await waitForExport()
        await service.setSharesEstimatedCalories(false)
        XCTAssertNil(journal.value.pending.first?.estimatedActiveCalories)
        client.failsSave = false
        service.resumePending()
        await waitForExport()
        XCTAssertNil(client.saved.last?.estimatedActiveCalories)
    }

    func testDisablingExportClearsQueueAndDoesNotBackfillAfterReenable() async {
        await service.setEnabled(true)
        client.failsSave = true
        service.enqueue(workout())
        await waitForExport()
        await service.setEnabled(false)
        XCTAssertEqual(service.pendingCount, 0)
        XCTAssertTrue(journal.value.pending.isEmpty)
        client.failsSave = false
        await service.setEnabled(true)
        await waitForExport()
        XCTAssertEqual(client.saved.count, 1)
    }

    func testQueueWriteFailureDoesNotStartExternalSaveAndCanRetry() async {
        await service.setEnabled(true)
        journal.failsSave = true
        service.enqueue(workout())
        XCTAssertEqual(service.pendingCount, 1)
        XCTAssertFalse(service.isExporting)
        XCTAssertTrue(client.saved.isEmpty)
        journal.failsSave = false
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.saved.count, 1)
        XCTAssertEqual(service.pendingCount, 0)
    }

    func testFailureRecordingSuccessKeepsJobRetryable() async {
        await service.setEnabled(true)
        client.beforeSaveReturns = { self.journal.failsSave = true }
        service.enqueue(workout())
        await waitForExport()
        XCTAssertEqual(service.pendingCount, 1)
        XCTAssertEqual(journal.value.pending.count, 1)
        XCTAssertTrue(journal.value.completedIDs.isEmpty)
        client.beforeSaveReturns = nil
        journal.failsSave = false
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(service.pendingCount, 0)
        XCTAssertEqual(Set(client.saved.map(\.syncIdentifier)).count, 1)
    }

    func testResetWhileSaveIsInFlightDoesNotRestoreDeletedQueueOrPreferences() async throws {
        await service.setEnabled(true)
        let started = expectation(description: "Export started")
        client.suspendsSave = true
        client.onSave = { started.fulfill() }
        service.enqueue(workout())
        await fulfillment(of: [started], timeout: 2)
        try service.resetLocalState()
        client.releaseSave()
        await waitForExport()
        XCTAssertFalse(service.isEnabled)
        XCTAssertFalse(service.sharesEstimatedCalories)
        assertEmptyJournal()
    }

    func testJournalReadFailureRetainsNewCompletionsAndMergesOnRetry() async {
        await service.setEnabled(true)
        let existing = workout()
        let added = workout()
        let completed = workout()
        journal.value = HealthExportJournal(pending: [existing], completedIDs: [completed.id])
        journal.failsLoad = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.enqueue(added)
        service.enqueue(added)
        service.enqueue(existing)
        service.enqueue(completed)
        XCTAssertTrue(client.saved.isEmpty)
        XCTAssertEqual(journal.value.pending, [existing])

        journal.failsLoad = false
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.saved.map(\.id), [existing.id, added.id])
        XCTAssertEqual(journal.value.completedIDs, [existing.id, added.id, completed.id])
        XCTAssertEqual(service.pendingCount, 0)
    }

    func testDisablingExportWhileJournalIsUnreadableDoesNotOverwriteHistoryOrResurrectJobs() async {
        await service.setEnabled(true)
        let existing = workout()
        let completedID = UUID()
        journal.value = HealthExportJournal(pending: [existing], completedIDs: [completedID])
        journal.failsLoad = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.enqueue(workout())
        await service.setEnabled(false)
        XCTAssertEqual(journal.value.pending, [existing])
        await service.setEnabled(true)
        journal.failsLoad = false
        service.resumePending()
        await waitForExport()
        XCTAssertTrue(client.saved.isEmpty)
        XCTAssertTrue(journal.value.pending.isEmpty)
        XCTAssertEqual(journal.value.completedIDs, [completedID])
    }

    func testFailedEnergyCleanupSurvivesRecreationAndRunsBeforeRetry() async {
        await service.setEnabled(true)
        let sampleID = UUID()
        let snapshot = workout()
        client.cleanupRequiredID = sampleID
        service.enqueue(snapshot)
        await waitForExport()
        XCTAssertEqual(journal.value.energyCleanupIDs, [sampleID])
        client.cleanupRequiredID = nil
        client.failsCleanup = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.saved.count, 1)
        XCTAssertEqual(journal.value.energyCleanupIDs, [sampleID])
        client.failsCleanup = false
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.events.suffix(2), ["cleanup", "save"])
        XCTAssertEqual(client.deletedEnergyIDs, [sampleID, sampleID])
        XCTAssertTrue(journal.value.energyCleanupIDs.isEmpty)
        XCTAssertTrue(journal.value.completedIDs.contains(snapshot.id))
    }

    func testCalorieOptOutWhileJournalIsUnreadableStillStripsEstimatesAfterReenable() async {
        await service.setEnabled(true)
        await service.setSharesEstimatedCalories(true)
        journal.value.pending = [workout()]
        journal.failsLoad = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        await service.setSharesEstimatedCalories(false)
        await service.setSharesEstimatedCalories(true)
        journal.failsLoad = false
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.saved.count, 1)
        XCTAssertNil(client.saved.first?.estimatedActiveCalories)
    }

    func testExportOptOutSurvivesRecreationBeforeJournalRecovery() async {
        await service.setEnabled(true)
        let completedID = UUID()
        journal.value = HealthExportJournal(pending: [workout()], completedIDs: [completedID])
        journal.failsLoad = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        await service.setEnabled(false)
        await service.setEnabled(true)
        journal.failsLoad = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertTrue(client.saved.isEmpty)
        XCTAssertTrue(journal.value.pending.isEmpty)
        XCTAssertEqual(journal.value.completedIDs, [completedID])
        service.enqueue(workout())
        await waitForExport()
        XCTAssertEqual(client.saved.count, 1, "The opt-out must not discard newly completed workouts")
    }

    func testCalorieOptOutSurvivesRecreationBeforeJournalRecovery() async {
        await service.setEnabled(true)
        await service.setSharesEstimatedCalories(true)
        journal.value.pending = [workout()]
        journal.failsLoad = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        await service.setSharesEstimatedCalories(false)
        await service.setSharesEstimatedCalories(true)
        journal.failsLoad = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.saved.count, 1)
        XCTAssertNil(client.saved.first?.estimatedActiveCalories)
        service.enqueue(workout())
        await waitForExport()
        XCTAssertEqual(client.saved.last?.estimatedActiveCalories, 105)
    }

    func testExportOptOutSurvivesRecreationAfterJournalWriteFailure() async {
        await service.setEnabled(true)
        client.failsSave = true
        service.enqueue(workout())
        await waitForExport()
        journal.failsSave = true
        await service.setEnabled(false)
        await service.setEnabled(true)
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        XCTAssertEqual(journal.value.pending.count, 1, "Failed write must not appear committed")
        journal.failsSave = false
        client.failsSave = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.saved.count, 1, "The canceled workout must not be attempted again")
        XCTAssertTrue(journal.value.pending.isEmpty)
    }

    func testResetDefersUnreadableJournalWithoutLosingCleanupIDs() async throws {
        await service.setEnabled(true)
        let sampleID = UUID()
        journal.value = HealthExportJournal(pending: [workout()], completedIDs: [UUID()], energyCleanupIDs: [sampleID])
        let original = journal.value
        journal.failsLoad = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        XCTAssertThrowsError(try service.resetLocalState())
        XCTAssertFalse(service.isEnabled)
        XCTAssertFalse(service.sharesEstimatedCalories)
        XCTAssertEqual(journal.value, original, "An unreadable journal must not be overwritten")
        journal.failsLoad = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.deletedEnergyIDs, [sampleID])
        XCTAssertTrue(client.saved.isEmpty)
        assertEmptyJournal()
    }

    func testResetMarkerSurvivesJournalWriteFailureAndServiceRecreation() async throws {
        await service.setEnabled(true)
        let sampleID = UUID()
        journal.value = HealthExportJournal(pending: [workout()], completedIDs: [UUID()], energyCleanupIDs: [sampleID])
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        journal.failsSave = true
        XCTAssertThrowsError(try service.resetLocalState())
        journal.failsSave = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.deletedEnergyIDs, [sampleID])
        XCTAssertTrue(client.saved.isEmpty)
        assertEmptyJournal()
    }

    func testCommittedOptOutIsNotReappliedToNewWorkoutsAfterInterruptedMarkerCleanup() async {
        await service.setEnabled(true)
        let canceled = workout()
        let added = workout()
        journal.value.pending = [canceled]
        journal.failsLoad = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        await service.setEnabled(false)
        await service.setEnabled(true)
        service.enqueue(added)
        journal.failsLoad = false
        // Model interruption after the file commit, before the separate UserDefaults update.
        journal.failsAfterSave = true
        service.resumePending()
        XCTAssertEqual(journal.value.pending.map(\.id), [added.id])
        XCTAssertTrue(client.saved.isEmpty)
        journal.failsAfterSave = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.saved.map(\.id), [added.id])
    }

    func testCommittedCalorieOptOutDoesNotStripNewEstimatesAfterInterruptedMarkerCleanup() async {
        await service.setEnabled(true)
        await service.setSharesEstimatedCalories(true)
        let previous = workout()
        let added = workout()
        journal.value.pending = [previous]
        journal.failsLoad = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        await service.setSharesEstimatedCalories(false)
        await service.setSharesEstimatedCalories(true)
        service.enqueue(added)
        journal.failsLoad = false
        journal.failsAfterSave = true
        service.resumePending()
        journal.failsAfterSave = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.saved.map(\.id), [previous.id, added.id])
        XCTAssertNil(client.saved.first?.estimatedActiveCalories)
        XCTAssertEqual(client.saved.last?.estimatedActiveCalories, 105)
    }

    func testDisablingExportStillRetriesFailedEnergyCleanupWithoutSavingWorkouts() async {
        await service.setEnabled(true)
        let sampleID = UUID()
        client.cleanupRequiredID = sampleID
        service.enqueue(workout())
        await waitForExport()
        client.cleanupRequiredID = nil
        await service.setEnabled(false)
        await waitForExport()
        XCTAssertEqual(client.saved.count, 1)
        XCTAssertEqual(client.deletedEnergyIDs, [sampleID])
        XCTAssertFalse(service.isEnabled)
        assertEmptyJournal()
    }

    func testJournalDecodesBeforeEnergyCleanupFieldWasAdded() throws {
        let oldJournal = Data("{\"pending\":[],\"completedIDs\":[]}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(HealthExportJournal.self, from: oldJournal), HealthExportJournal())
    }

    func testFileJournalRoundTripsAndExcludesHealthDataFromBackups() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileHealthExportJournalStore(directory: directory)
        let expected = HealthExportJournal(pending: [workout()], completedIDs: [UUID()], energyCleanupIDs: [UUID()],
                                           energyAttempts: [HealthEnergyExportAttempt(workoutID: UUID(), sampleID: UUID())])
        try store.save(expected)
        XCTAssertEqual(try store.load(), expected)
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(try directory.appendingPathComponent("journal.json")
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testInterruptedEnergyWaitsForCaloriePermissionAfterExportIsDisabled() async {
        let attempt = HealthEnergyExportAttempt(workoutID: UUID(), sampleID: UUID())
        journal.value = HealthExportJournal(energyAttempts: [attempt])
        client.canWriteWorkouts = false
        client.canWriteEnergy = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.queriedAttempts, [attempt])
        XCTAssertTrue(client.deletedEnergyIDs.isEmpty)
        XCTAssertEqual(journal.value.energyAttempts, [attempt])
        XCTAssertTrue(service.canRetry)
        client.canWriteEnergy = true
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.deletedEnergyIDs, [attempt.sampleID])
        XCTAssertTrue(client.saved.isEmpty)
        assertEmptyJournal()
    }

    func testInterruptedSuccessfulWorkoutKeepsEnergyAndDoesNotExportAgain() async {
        let export = workout()
        let attempt = HealthEnergyExportAttempt(workoutID: export.id, sampleID: UUID())
        defaults.set(true, forKey: "appleHealth.saveWorkouts")
        journal.value = HealthExportJournal(pending: [export], energyAttempts: [attempt])
        client.savedAttemptIDs.insert(attempt.sampleID)
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertTrue(client.deletedEnergyIDs.isEmpty)
        XCTAssertTrue(client.saved.isEmpty)
        XCTAssertTrue(journal.value.pending.isEmpty)
        XCTAssertEqual(journal.value.completedIDs, [export.id])
        XCTAssertTrue(journal.value.energyAttempts.isEmpty)
    }

    func testSuccessfulInterruptedExportKeepsEnergyWhenIntegrationWasDisabled() async {
        let attempt = HealthEnergyExportAttempt(workoutID: UUID(), sampleID: UUID())
        journal.value = HealthExportJournal(energyAttempts: [attempt])
        client.savedAttemptIDs.insert(attempt.sampleID)
        client.canWriteWorkouts = false
        client.canWriteEnergy = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertTrue(client.deletedEnergyIDs.isEmpty)
        assertEmptyJournal()
    }

    func testInterruptedExportQueryFailureKeepsRecoveryIntentUntilRetry() async {
        let attempt = HealthEnergyExportAttempt(workoutID: UUID(), sampleID: UUID())
        journal.value = HealthExportJournal(energyAttempts: [attempt])
        client.failsQuery = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(journal.value.energyAttempts, [attempt])
        XCTAssertTrue(service.canRetry)
        XCTAssertTrue(client.deletedEnergyIDs.isEmpty)
        client.failsQuery = false
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.deletedEnergyIDs, [attempt.sampleID])
        assertEmptyJournal()
    }

    func testCrashAfterHealthSaveBeforeLocalCommitPreservesSuccessfulEnergy() async throws {
        await service.setEnabled(true)
        await service.setSharesEstimatedCalories(true)
        let export = workout()
        client.beforeSaveReturns = { self.journal.failsSave = true }
        service.enqueue(export)
        await waitForExport()
        let attempt = try XCTUnwrap(journal.value.energyAttempts.first)
        XCTAssertEqual(attempt.workoutID, export.id)
        XCTAssertEqual(journal.value.pending, [export])
        // HealthKit committed, but the app's completion journal did not reach disk.
        client.savedAttemptIDs.insert(attempt.sampleID)
        client.beforeSaveReturns = nil
        journal.failsSave = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.saved.count, 1)
        XCTAssertTrue(client.deletedEnergyIDs.isEmpty)
        XCTAssertEqual(journal.value.completedIDs, [export.id])
        XCTAssertTrue(journal.value.energyAttempts.isEmpty)
    }

    func testResetRetainsInterruptedEnergyRecoveryWhenJournalCannotBeRead() async throws {
        let attempt = HealthEnergyExportAttempt(workoutID: UUID(), sampleID: UUID())
        journal.value = HealthExportJournal(energyAttempts: [attempt])
        journal.failsLoad = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        XCTAssertThrowsError(try service.resetLocalState())
        XCTAssertEqual(journal.value.energyAttempts, [attempt])
        journal.failsLoad = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.deletedEnergyIDs, [attempt.sampleID])
        assertEmptyJournal()
    }

    func testResetDuringEnergyWriteReconcilesSuccessWithoutDeletingExportedCalories() async throws {
        await service.setEnabled(true)
        await service.setSharesEstimatedCalories(true)
        let started = expectation(description: "Energy export started")
        client.suspendsSave = true
        client.onSave = { started.fulfill() }
        service.enqueue(workout())
        await fulfillment(of: [started], timeout: 2)
        let attempt = try XCTUnwrap(journal.value.energyAttempts.first)
        try service.resetLocalState()
        XCTAssertEqual(journal.value.energyAttempts, [attempt])
        client.savedAttemptIDs.insert(attempt.sampleID)
        client.releaseSave()
        await waitForExport()
        XCTAssertFalse(service.isEnabled)
        XCTAssertTrue(client.deletedEnergyIDs.isEmpty)
        XCTAssertEqual(client.queriedAttempts, [attempt])
        assertEmptyJournal()
    }

    func testRecoveryJournalFailureKeepsAttemptForRetryWithoutDuplicatingWorkout() async {
        let export = workout()
        let attempt = HealthEnergyExportAttempt(workoutID: export.id, sampleID: UUID())
        defaults.set(true, forKey: "appleHealth.saveWorkouts")
        journal.value = HealthExportJournal(pending: [export], energyAttempts: [attempt])
        client.savedAttemptIDs.insert(attempt.sampleID)
        journal.failsSave = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(journal.value.energyAttempts, [attempt])
        XCTAssertTrue(client.saved.isEmpty)
        journal.failsSave = false
        service.resumePending()
        await waitForExport()
        XCTAssertTrue(journal.value.energyAttempts.isEmpty)
        XCTAssertEqual(journal.value.completedIDs, [export.id])
        XCTAssertTrue(client.saved.isEmpty)
        XCTAssertTrue(client.deletedEnergyIDs.isEmpty)
    }

    func testRevokedEnergyPermissionDoesNotBlockWorkoutsWithLegacyCleanupIDs() async {
        let export = workout()
        let sampleID = UUID()
        defaults.set(true, forKey: "appleHealth.saveWorkouts")
        defaults.set(true, forKey: "appleHealth.shareEstimatedCalories")
        journal.value = HealthExportJournal(pending: [export], energyCleanupIDs: [sampleID])
        client.canWriteEnergy = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.saved.map(\.id), [export.id])
        XCTAssertNil(client.saved.first?.estimatedActiveCalories)
        XCTAssertTrue(client.deletedEnergyIDs.isEmpty)
        XCTAssertEqual(journal.value.energyCleanupIDs, [sampleID])
        XCTAssertTrue(service.message?.contains("Active Energy access") == true)
        XCTAssertTrue(service.canRetry)

        client.canWriteEnergy = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.deletedEnergyIDs, [sampleID])
        XCTAssertTrue(journal.value.energyCleanupIDs.isEmpty)
        XCTAssertEqual(client.saved.count, 1)
        XCTAssertTrue(client.authorizationRequests.isEmpty)
    }

    func testInterruptedEnergyBlocksOnlyItsWorkoutWhilePermissionIsRevoked() async {
        let interrupted = workout()
        let unrelated = workout()
        let attempt = HealthEnergyExportAttempt(workoutID: interrupted.id, sampleID: UUID())
        defaults.set(true, forKey: "appleHealth.saveWorkouts")
        defaults.set(true, forKey: "appleHealth.shareEstimatedCalories")
        journal.value = HealthExportJournal(pending: [interrupted, unrelated], energyAttempts: [attempt])
        client.canWriteEnergy = false
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.saved.map(\.id), [unrelated.id])
        XCTAssertNil(client.saved.first?.estimatedActiveCalories)
        XCTAssertEqual(journal.value.pending.map(\.id), [interrupted.id])
        XCTAssertEqual(journal.value.energyAttempts, [attempt])

        client.canWriteEnergy = true
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.deletedEnergyIDs, [attempt.sampleID])
        XCTAssertEqual(client.saved.map(\.id), [unrelated.id, interrupted.id])
        XCTAssertEqual(client.saved.last?.estimatedActiveCalories, 105)
        XCTAssertTrue(journal.value.pending.isEmpty)
        XCTAssertTrue(journal.value.energyAttempts.isEmpty)
        XCTAssertTrue(client.authorizationRequests.isEmpty)
    }

    func testFailedEnergyCleanupRetainsWorkoutIdentityAndAllowsUnrelatedExport() async {
        await service.setEnabled(true)
        await service.setSharesEstimatedCalories(true)
        let failed = workout()
        let unrelated = workout()
        let sampleID = UUID()
        client.cleanupRequiredID = sampleID
        service.enqueue(failed)
        await waitForExport()
        XCTAssertEqual(journal.value.energyAttempts, [HealthEnergyExportAttempt(workoutID: failed.id, sampleID: sampleID)])
        client.cleanupRequiredID = nil
        client.canWriteEnergy = false
        await service.setSharesEstimatedCalories(false)
        service.enqueue(unrelated)
        await waitForExport()
        XCTAssertEqual(client.saved.map(\.id), [failed.id, unrelated.id])
        XCTAssertNil(client.saved.last?.estimatedActiveCalories)
        XCTAssertEqual(journal.value.pending.map(\.id), [failed.id])
        XCTAssertEqual(journal.value.energyCleanupIDs, [sampleID])

        client.canWriteEnergy = true
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.deletedEnergyIDs, [sampleID])
        XCTAssertEqual(client.saved.map(\.id), [failed.id, unrelated.id, failed.id])
        XCTAssertNil(client.saved.last?.estimatedActiveCalories)
        XCTAssertTrue(journal.value.energyAttempts.isEmpty)
        XCTAssertTrue(journal.value.energyCleanupIDs.isEmpty)
    }

    func testAuthorizationDenialDuringCleanupStillAllowsWorkoutOnlyExport() async {
        let export = workout()
        let sampleID = UUID()
        defaults.set(true, forKey: "appleHealth.saveWorkouts")
        defaults.set(true, forKey: "appleHealth.shareEstimatedCalories")
        journal.value = HealthExportJournal(pending: [export], energyCleanupIDs: [sampleID])
        // Permission can change after the preflight authorization check.
        client.cleanupError = HKError(.errorAuthorizationDenied)
        service = AppleHealthExportService(client: client, journalStore: journal, defaults: defaults)
        service.resumePending()
        await waitForExport()
        XCTAssertEqual(client.saved.map(\.id), [export.id])
        XCTAssertNil(client.saved.first?.estimatedActiveCalories)
        XCTAssertEqual(journal.value.energyCleanupIDs, [sampleID])
        client.cleanupError = nil
        service.resumePending()
        await waitForExport()
        XCTAssertTrue(journal.value.energyCleanupIDs.isEmpty)
        XCTAssertEqual(client.saved.count, 1)
    }

    private func assertEmptyJournal(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(journal.value.pending.isEmpty, file: file, line: line)
        XCTAssertTrue(journal.value.completedIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(journal.value.energyAttempts.isEmpty, file: file, line: line)
        XCTAssertTrue(journal.value.energyCleanupIDs.isEmpty, file: file, line: line)
    }

    private func workout() -> HealthWorkoutExport {
        HealthWorkoutExport(id: UUID(), name: "Push", start: Date(timeIntervalSince1970: 1_700_000_000),
                            end: Date(timeIntervalSince1970: 1_700_001_800), activity: .strength,
                            estimatedActiveCalories: 105, calorieEstimateVersion: 2)
    }

    private func waitForExport() async {
        let deadline = Date().addingTimeInterval(2)
        while service.isExporting && Date() < deadline { await Task.yield() }
        XCTAssertFalse(service.isExporting)
    }
}

@MainActor
private final class MemoryHealthExportJournalStore: HealthExportJournalStoring {
    var value = HealthExportJournal()
    var failsSave = false
    var failsLoad = false
    var failsAfterSave = false
    func load() throws -> HealthExportJournal {
        if failsLoad { throw CocoaError(.fileReadUnknown) }
        return value
    }
    func save(_ journal: HealthExportJournal) throws {
        if failsSave { throw CocoaError(.fileWriteUnknown) }
        value = journal
        if failsAfterSave { throw CocoaError(.fileWriteUnknown) }
    }
}

@MainActor
private final class RecordingAppleHealthClient: AppleHealthClient {
    var isAvailable = true
    var canWriteWorkouts = true
    var canWriteEnergy = true
    var authorizationRequests: [Bool] = []
    var saved: [HealthWorkoutExport] = []
    var failsSave = false
    var cleanupRequiredID: UUID?
    var failsCleanup = false
    var cleanupError: (any Error)?
    var deletedEnergyIDs: [UUID] = []
    var events: [String] = []
    var recordedAttempts: [HealthEnergyExportAttempt] = []
    var savedAttemptIDs: Set<UUID> = []
    var failsQuery = false
    var queriedAttempts: [HealthEnergyExportAttempt] = []
    var suspendsSave = false
    var onSave: (() -> Void)?
    var beforeSaveReturns: (() -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?

    func requestAuthorization(includeEnergy: Bool) async throws {
        authorizationRequests.append(includeEnergy)
    }
    func save(_ workout: HealthWorkoutExport, recordEnergy: (HealthEnergyExportAttempt) throws -> Void) async throws {
        if workout.estimatedActiveCalories != nil {
            let attempt = HealthEnergyExportAttempt(workoutID: workout.id, sampleID: UUID())
            try recordEnergy(attempt)
            recordedAttempts.append(attempt)
        }
        events.append("save")
        saved.append(workout)
        onSave?()
        if suspendsSave {
            await withCheckedContinuation { continuation = $0 }
        }
        if failsSave { throw CocoaError(.fileWriteUnknown) }
        if let cleanupRequiredID { throw AppleHealthEnergyCleanupRequired(sampleID: cleanupRequiredID) }
        beforeSaveReturns?()
    }
    func hasSavedWorkout(for attempt: HealthEnergyExportAttempt) async throws -> Bool {
        queriedAttempts.append(attempt)
        if failsQuery { throw CocoaError(.fileReadNoPermission) }
        return savedAttemptIDs.contains(attempt.sampleID)
    }
    func deleteEnergySample(id: UUID) async throws {
        events.append("cleanup")
        deletedEnergyIDs.append(id)
        guard canWriteEnergy else { throw HKError(.errorAuthorizationDenied) }
        if let cleanupError { throw cleanupError }
        if failsCleanup { throw CocoaError(.fileWriteUnknown) }
    }
    func releaseSave() { continuation?.resume(); continuation = nil }
}
