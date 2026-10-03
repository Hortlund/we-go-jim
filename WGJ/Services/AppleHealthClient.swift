import Foundation
import HealthKit

@MainActor
protocol AppleHealthClient {
    var isAvailable: Bool { get }
    var canWriteWorkouts: Bool { get }
    var canWriteEnergy: Bool { get }
    func requestAuthorization(includeEnergy: Bool) async throws
    func save(_ workout: HealthWorkoutExport, recordEnergy: (HealthEnergyExportAttempt) throws -> Void) async throws
    func deleteEnergySample(id: UUID) async throws
    func hasSavedWorkout(for attempt: HealthEnergyExportAttempt) async throws -> Bool
}

/// A failed export whose attempt-specific energy sample still needs removal.
nonisolated struct AppleHealthEnergyCleanupRequired: Error {
    let sampleID: UUID
}

@MainActor
protocol AppleHealthWorkoutBuilding {
    func beginCollection(at date: Date) async throws
    func addMetadata(_ metadata: [String: Any]) async throws
    func addSamples(_ samples: [HKSample]) async throws
    func endCollection(at date: Date) async throws
    func finishExport() async throws
    func discardWorkout()
}

extension HKWorkoutBuilder: AppleHealthWorkoutBuilding {
    func finishExport() async throws {
        // A nil workout without an error is a successful save while the phone is locked.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            finishWorkout { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}

@MainActor
final class HealthKitAppleHealthClient: AppleHealthClient {
    private lazy var store = HKHealthStore()
    private lazy var energyType = HKQuantityType(.activeEnergyBurned)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var canWriteWorkouts: Bool { isAvailable && store.authorizationStatus(for: .workoutType()) == .sharingAuthorized }
    var canWriteEnergy: Bool { isAvailable && store.authorizationStatus(for: energyType) == .sharingAuthorized }

    func requestAuthorization(includeEnergy: Bool) async throws {
        guard isAvailable else { throw HKError(.errorHealthDataUnavailable) }
        var types: Set<HKSampleType> = [.workoutType()]
        if includeEnergy { types.insert(energyType) }
        // Export only: no permission to read other apps' workouts or personal health data.
        try await store.requestAuthorization(toShare: types, read: [])
    }

    func save(_ workout: HealthWorkoutExport, recordEnergy: (HealthEnergyExportAttempt) throws -> Void) async throws {
        guard isAvailable else { throw HKError(.errorHealthDataUnavailable) }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workout.activity.healthKitType
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
        try await AppleHealthWorkoutWriter.save(workout, builder: builder, includeEnergy: canWriteEnergy, recordEnergy: recordEnergy) { id in
            try await self.deleteEnergySample(id: id)
        }
    }

    func hasSavedWorkout(for attempt: HealthEnergyExportAttempt) async throws -> Bool {
        guard isAvailable else { throw HKError(.errorHealthDataUnavailable) }
        // HealthKit lets an app read samples it saved even without read authorization.
        // Check this exact attempt, so an earlier successful retry cannot mask an orphan.
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObjects(withMetadataKey: HealthEnergyExportAttempt.metadataKey,
                                       allowedValues: [attempt.sampleID.uuidString]),
        ])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1,
                                      sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: !(samples ?? []).isEmpty) }
            }
            store.execute(query)
        }
    }

    func deleteEnergySample(id: UUID) async throws {
        guard isAvailable else { throw HKError(.errorHealthDataUnavailable) }
        // Exact UUID, never a sync identifier: a retry must not remove an earlier successful export.
        _ = try await store.deleteObjects(of: energyType, predicate: HKQuery.predicateForObject(with: id))
    }
}

@MainActor
enum AppleHealthWorkoutWriter {
    static func save(_ workout: HealthWorkoutExport, builder: any AppleHealthWorkoutBuilding,
                     includeEnergy: Bool, recordEnergy: (HealthEnergyExportAttempt) throws -> Void,
                     deleteEnergy: (UUID) async throws -> Void) async throws {
        var energySampleID: UUID?
        do {
            try await builder.beginCollection(at: workout.start)
            try await builder.addMetadata([
                HKMetadataKeySyncIdentifier: workout.syncIdentifier,
                HKMetadataKeySyncVersion: NSNumber(value: 1),
                HKMetadataKeyWorkoutBrandName: "We Go Jim",
                "se.highball.wgj.workoutName": workout.name,
            ])
            if includeEnergy, let calories = workout.estimatedActiveCalories, calories > 0 {
                let energy = HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(calories)),
                    start: workout.start, end: workout.end,
                    metadata: [
                        HKMetadataKeySyncIdentifier: workout.syncIdentifier + ".active-energy",
                        HKMetadataKeySyncVersion: NSNumber(value: 1),
                        "se.highball.wgj.isEstimated": true,
                        "se.highball.wgj.calorieEstimateVersion": workout.calorieEstimateVersion ?? 0,
                    ]
                )
                // Commit recovery information before any sample can reach HealthKit.
                try recordEnergy(HealthEnergyExportAttempt(workoutID: workout.id, sampleID: energy.uuid))
                energySampleID = energy.uuid
                try await builder.addMetadata([HealthEnergyExportAttempt.metadataKey: energy.uuid.uuidString])
                try await builder.addSamples([energy])
            }
            try await builder.endCollection(at: workout.end)
            try await builder.finishExport()
        } catch {
            builder.discardWorkout()
            // discardWorkout does not delete samples already written by addSamples.
            if let energySampleID {
                do { try await deleteEnergy(energySampleID) }
                catch { throw AppleHealthEnergyCleanupRequired(sampleID: energySampleID) }
            }
            throw error
        }
    }
}
