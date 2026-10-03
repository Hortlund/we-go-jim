import HealthKit
import XCTest
@testable import WGJ

@MainActor
final class AppleHealthWorkoutWriterTests: XCTestCase {
    func testFailuresAfterEnergyInsertionRemoveOnlyThisAttemptsSample() async {
        for stage in [RecordingHealthWorkoutBuilder.Stage.samples, .end, .finish] {
            let builder = RecordingHealthWorkoutBuilder()
            let earlierSampleID = UUID()
            builder.persistedEnergyIDs = [earlierSampleID]
            builder.failingStage = stage
            var deleted: [UUID] = []
            do {
                try await AppleHealthWorkoutWriter.save(workout(), builder: builder, includeEnergy: true, recordEnergy: { _ in }) { id in
                    deleted.append(id)
                    builder.persistedEnergyIDs.remove(id)
                }
                XCTFail("Expected failure at \(stage)")
            } catch {
                XCTAssertFalse(error is AppleHealthEnergyCleanupRequired)
            }
            XCTAssertEqual(deleted, builder.attemptedEnergyIDs)
            XCTAssertEqual(deleted.count, 1)
            XCTAssertEqual(builder.persistedEnergyIDs, [earlierSampleID])
            XCTAssertTrue(builder.discarded)
        }
    }

    func testSuccessfulExportKeepsEnergyAndNeverRunsCleanup() async throws {
        let builder = RecordingHealthWorkoutBuilder()
        try await AppleHealthWorkoutWriter.save(workout(), builder: builder, includeEnergy: true, recordEnergy: { _ in }) { _ in
            XCTFail("A successful workout must keep its energy sample")
        }
        XCTAssertEqual(builder.persistedEnergyIDs.count, 1)
        XCTAssertTrue(builder.finished)
        XCTAssertFalse(builder.discarded)
    }

    func testFailureWithoutEnergyDoesNotRunCleanup() async {
        let builder = RecordingHealthWorkoutBuilder()
        builder.failingStage = .finish
        do {
            try await AppleHealthWorkoutWriter.save(workout(), builder: builder, includeEnergy: false, recordEnergy: { _ in }) { _ in
                XCTFail("No energy was written")
            }
            XCTFail("Expected workout failure")
        } catch {
            XCTAssertFalse(error is AppleHealthEnergyCleanupRequired)
        }
        XCTAssertTrue(builder.persistedEnergyIDs.isEmpty)
        XCTAssertTrue(builder.discarded)
    }

    func testCleanupFailureReturnsSampleIdentityForDurableRetry() async {
        let builder = RecordingHealthWorkoutBuilder()
        builder.failingStage = .finish
        do {
            try await AppleHealthWorkoutWriter.save(workout(), builder: builder, includeEnergy: true, recordEnergy: { _ in }) { _ in
                throw CocoaError(.fileWriteUnknown)
            }
            XCTFail("Expected cleanup failure")
        } catch let error as AppleHealthEnergyCleanupRequired {
            XCTAssertEqual(builder.persistedEnergyIDs, [error.sampleID])
            XCTAssertEqual(builder.attemptedEnergyIDs, [error.sampleID])
        } catch {
            XCTFail("Expected sample identity for cleanup, got \(error)")
        }
    }

    func testRecoveryIdentityIsCommittedBeforeEnergyInsertionAndMatchesWorkoutMetadata() async throws {
        let builder = RecordingHealthWorkoutBuilder()
        let export = workout()
        var recorded: HealthEnergyExportAttempt?
        try await AppleHealthWorkoutWriter.save(export, builder: builder, includeEnergy: true, recordEnergy: { attempt in
            XCTAssertTrue(builder.persistedEnergyIDs.isEmpty)
            XCTAssertTrue(builder.attemptedEnergyIDs.isEmpty)
            XCTAssertEqual(attempt.workoutID, export.id)
            recorded = attempt
        }) { _ in XCTFail("Successful workout must keep energy") }
        let attempt = try XCTUnwrap(recorded)
        XCTAssertEqual(builder.persistedEnergyIDs, [attempt.sampleID])
        XCTAssertEqual(builder.metadata[HealthEnergyExportAttempt.metadataKey] as? String, attempt.sampleID.uuidString)
    }

    func testRecoveryJournalFailurePreventsEnergyInsertion() async {
        let builder = RecordingHealthWorkoutBuilder()
        do {
            try await AppleHealthWorkoutWriter.save(workout(), builder: builder, includeEnergy: true, recordEnergy: { _ in
                throw CocoaError(.fileWriteUnknown)
            }) { _ in XCTFail("No energy was inserted") }
            XCTFail("Expected recovery journal failure")
        } catch { }
        XCTAssertTrue(builder.attemptedEnergyIDs.isEmpty)
        XCTAssertFalse(builder.finished)
        XCTAssertTrue(builder.discarded)
    }

    private func workout() -> HealthWorkoutExport {
        HealthWorkoutExport(id: UUID(), name: "Push", start: Date(timeIntervalSince1970: 1_700_000_000),
                            end: Date(timeIntervalSince1970: 1_700_001_800), activity: .strength,
                            estimatedActiveCalories: 105, calorieEstimateVersion: 2)
    }
}

@MainActor
private final class RecordingHealthWorkoutBuilder: AppleHealthWorkoutBuilding {
    enum Stage { case samples, end, finish }
    var failingStage: Stage?
    var persistedEnergyIDs: Set<UUID> = []
    var attemptedEnergyIDs: [UUID] = []
    var metadata: [String: Any] = [:]
    var discarded = false
    var finished = false

    func beginCollection(at date: Date) async throws { }
    func addMetadata(_ metadata: [String: Any]) async throws {
        self.metadata.merge(metadata) { _, new in new }
    }
    func addSamples(_ samples: [HKSample]) async throws {
        attemptedEnergyIDs.append(contentsOf: samples.map(\.uuid))
        persistedEnergyIDs.formUnion(samples.map(\.uuid))
        if failingStage == .samples { throw CocoaError(.fileWriteUnknown) }
    }
    func endCollection(at date: Date) async throws {
        if failingStage == .end { throw CocoaError(.fileWriteUnknown) }
    }
    func finishExport() async throws {
        if failingStage == .finish { throw CocoaError(.fileWriteUnknown) }
        finished = true
    }
    // HealthKit's discard leaves inserted samples in the database.
    func discardWorkout() { discarded = true }
}
