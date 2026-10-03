import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class AppleHealthExportService {
    static let shared = AppleHealthExportService()
    nonisolated deinit { }

    private(set) var isEnabled: Bool
    private(set) var sharesEstimatedCalories: Bool
    private(set) var isAuthorizing = false
    private(set) var isExporting = false
    private(set) var pendingCount = 0
    private(set) var message: String?
    var isAvailable: Bool { client.isAvailable }
    var canRetry: Bool { pendingCount > 0 || !hasLoadedJournal || (!journal.energyCleanupIDs.isEmpty || !journal.energyAttempts.isEmpty) }

    @ObservationIgnored private let client: any AppleHealthClient
    @ObservationIgnored private let journalStore: any HealthExportJournalStoring
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var journal = HealthExportJournal()
    @ObservationIgnored private var hasLoadedJournal = false
    @ObservationIgnored private var hasUnpersistedJournalChanges = false
    @ObservationIgnored private var discardPendingWhenLoaded = false
    @ObservationIgnored private var stripPendingEnergyWhenLoaded = false
    @ObservationIgnored private var resetJournalWhenLoaded = false
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    private static let enabledKey = "appleHealth.saveWorkouts"
    private static let energyKey = "appleHealth.shareEstimatedCalories"
    private static let discardPendingKey = "appleHealth.discardPendingExports"
    private static let stripPendingEnergyKey = "appleHealth.stripPendingEnergy"
    private static let resetJournalKey = "appleHealth.resetJournal"

    init(client: any AppleHealthClient = HealthKitAppleHealthClient(),
         journalStore: any HealthExportJournalStoring = FileHealthExportJournalStore(),
         defaults: UserDefaults = .standard) {
        self.client = client
        self.journalStore = journalStore
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        sharesEstimatedCalories = defaults.bool(forKey: Self.energyKey)
        discardPendingWhenLoaded = !isEnabled || defaults.string(forKey: Self.discardPendingKey) != nil
        stripPendingEnergyWhenLoaded = !sharesEstimatedCalories || defaults.string(forKey: Self.stripPendingEnergyKey) != nil
        resetJournalWhenLoaded = defaults.string(forKey: Self.resetJournalKey) != nil
        loadJournalIfNeeded()
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isAuthorizing else { return }
        if !enabled {
            generation += 1
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            discardPendingWhenLoaded = true
            defaults.set(UUID().uuidString, forKey: Self.discardPendingKey)
            journal.pending.removeAll()
            if hasLoadedJournal, persistJournal() { message = nil }
            resumePending()
            return
        }
        guard isAvailable else {
            message = "Apple Health is unavailable on this device."
            return
        }
        isAuthorizing = true
        let currentGeneration = generation
        defer { isAuthorizing = false }
        do {
            try await client.requestAuthorization(includeEnergy: sharesEstimatedCalories)
            guard generation == currentGeneration else { return }
            guard client.canWriteWorkouts else {
                message = "Allow WGJ to save Workouts in the Health app to enable export."
                return
            }
            // Preserve invalidation even if access is re-enabled before the journal recovers.
            if discardPendingWhenLoaded, defaults.string(forKey: Self.discardPendingKey) == nil {
                defaults.set(UUID().uuidString, forKey: Self.discardPendingKey)
            }
            isEnabled = true
            defaults.set(true, forKey: Self.enabledKey)
            message = nil
            resumePending()
        } catch {
            guard generation == currentGeneration else { return }
            message = "Apple Health could not be connected. Please try again."
        }
    }

    func setSharesEstimatedCalories(_ enabled: Bool) async {
        guard !isAuthorizing else { return }
        if !enabled {
            sharesEstimatedCalories = false
            defaults.set(false, forKey: Self.energyKey)
            stripPendingEnergyWhenLoaded = true
            defaults.set(UUID().uuidString, forKey: Self.stripPendingEnergyKey)
            // Revoking this preference also removes calories from queued exports.
            for index in journal.pending.indices { journal.pending[index].estimatedActiveCalories = nil }
            if hasLoadedJournal { persistJournal() }
            return
        }
        guard isEnabled, isAvailable else { return }
        isAuthorizing = true
        let currentGeneration = generation
        defer { isAuthorizing = false }
        do {
            try await client.requestAuthorization(includeEnergy: true)
            guard generation == currentGeneration else { return }
            guard client.canWriteEnergy else {
                message = "Allow WGJ to save Active Energy in the Health app to share estimates. Workouts can still be exported."
                return
            }
            if stripPendingEnergyWhenLoaded, defaults.string(forKey: Self.stripPendingEnergyKey) == nil {
                defaults.set(UUID().uuidString, forKey: Self.stripPendingEnergyKey)
            }
            sharesEstimatedCalories = true
            defaults.set(true, forKey: Self.energyKey)
            message = nil
        } catch {
            guard generation == currentGeneration else { return }
            message = "Calorie sharing could not be enabled. Workouts can still be exported."
        }
    }

    func enqueue(_ snapshot: HealthWorkoutExport) {
        guard isEnabled else { return }
        // Retain new work even when the on-disk journal cannot be read. Never overwrite that
        // journal with an incomplete view; merge these snapshots once loading succeeds.
        let loaded = loadJournalIfNeeded()
        guard !journal.completedIDs.contains(snapshot.id),
              !journal.pending.contains(where: { $0.id == snapshot.id }) else { return }
        var snapshot = snapshot
        if !sharesEstimatedCalories { snapshot.estimatedActiveCalories = nil }
        journal.pending.append(snapshot)
        pendingCount = journal.pending.count
        guard loaded else { return }
        guard persistJournal() else { return }
        resumePending()
    }

    /// Only retries existing jobs; never scans history, prompts for access, or backfills old workouts.
    func resumePending() {
        guard isAvailable, exportTask == nil, loadJournalIfNeeded() else { return }
        if hasUnpersistedJournalChanges && !persistJournal() { return }
        guard (!journal.energyCleanupIDs.isEmpty || !journal.energyAttempts.isEmpty) || (isEnabled && !journal.pending.isEmpty) else { return }
        guard !isEnabled || client.canWriteWorkouts || (!journal.energyCleanupIDs.isEmpty || !journal.energyAttempts.isEmpty) else {
            message = "Workout access is off in Apple Health. Your workouts remain saved in WGJ."
            return
        }
        let currentGeneration = generation
        isExporting = true
        exportTask = Task { [weak self] in
            guard let self else { return }
            await self.exportPending(generation: currentGeneration)
            self.exportTask = nil
            self.isExporting = false
            if self.generation != currentGeneration { self.resumePending() }
        }
    }

    func resetLocalState() throws {
        generation += 1
        isEnabled = false
        sharesEstimatedCalories = false
        defaults.removeObject(forKey: Self.enabledKey)
        defaults.removeObject(forKey: Self.energyKey)
        discardPendingWhenLoaded = true
        stripPendingEnergyWhenLoaded = true
        resetJournalWhenLoaded = true
        defaults.set(UUID().uuidString, forKey: Self.discardPendingKey)
        defaults.set(UUID().uuidString, forKey: Self.stripPendingEnergyKey)
        defaults.set(UUID().uuidString, forKey: Self.resetJournalKey)
        journal.pending.removeAll()
        journal.completedIDs.removeAll()
        pendingCount = 0
        // A failed read must never replace stored cleanup IDs with an empty in-memory set.
        // The durable reset marker applies when a later retry can finally open the journal.
        guard loadJournalIfNeeded() else { throw HealthExportResetError.unreadableJournal }
        try saveJournal()
        message = nil
        resumePending()
    }

    private func exportPending(generation currentGeneration: Int) async {
        message = nil
        var cleanupDeferred = false
        defer {
            if cleanupDeferred, generation == currentGeneration {
                let warning = "Calorie cleanup is waiting for Active Energy access in Apple Health. Other workouts can still be exported."
                message = message.map { $0 + " " + warning } ?? warning
            }
        }
        // Resolve interrupted writes before retries, even after export was switched off.
        for attempt in journal.energyAttempts {
            do {
                let saved = journal.energyCleanupIDs.contains(attempt.sampleID)
                    ? false : try await client.hasSavedWorkout(for: attempt)
                guard generation == currentGeneration else { return }
                if !saved {
                    guard client.canWriteEnergy else {
                        cleanupDeferred = true
                        continue
                    }
                    do { try await client.deleteEnergySample(id: attempt.sampleID) }
                    catch {
                        guard generation == currentGeneration else { return }
                        if energyCleanupIsUnauthorized(error) {
                            cleanupDeferred = true
                            continue
                        }
                        throw error
                    }
                }
                guard generation == currentGeneration else { return }
                let previousJournal = journal
                journal.energyAttempts.remove(attempt)
                journal.energyCleanupIDs.remove(attempt.sampleID)
                if saved, journal.pending.contains(where: { $0.id == attempt.workoutID }) {
                    journal.pending.removeAll { $0.id == attempt.workoutID }
                    journal.completedIDs.insert(attempt.workoutID)
                }
                guard persistJournal() else {
                    journal = previousJournal
                    pendingCount = journal.pending.count
                    return
                }
            } catch {
                guard generation == currentGeneration else { return }
                message = "Apple Health could not check an interrupted export. Please unlock your iPhone and retry."
                return
            }
        }
        // Older journals contain cleanup UUIDs without a workout identity. Keep those
        // obligations too, but revoked calorie access must not stop workout-only saves.
        let unresolvedAttemptIDs = Set(journal.energyAttempts.map(\.sampleID))
        for id in journal.energyCleanupIDs where !unresolvedAttemptIDs.contains(id) {
            guard client.canWriteEnergy else {
                cleanupDeferred = true
                continue
            }
            do {
                try await client.deleteEnergySample(id: id)
                guard generation == currentGeneration else { return }
                journal.energyCleanupIDs.remove(id)
                guard persistJournal() else {
                    journal.energyCleanupIDs.insert(id)
                    return
                }
            } catch {
                guard generation == currentGeneration else { return }
                if energyCleanupIsUnauthorized(error) {
                    cleanupDeferred = true
                    continue
                }
                message = "Apple Health could not remove calories from a failed export. Please retry."
                return
            }
        }
        if !isEnabled { message = nil }
        let unresolvedWorkoutIDs = Set(journal.energyAttempts.map(\.workoutID))
        while isEnabled, generation == currentGeneration,
              let next = journal.pending.first(where: { !unresolvedWorkoutIDs.contains($0.id) }) {
            guard client.canWriteWorkouts else {
                message = "Workout access is off in Apple Health. Your workouts remain saved in WGJ."
                return
            }
            var export = next
            if !sharesEstimatedCalories || !client.canWriteEnergy || cleanupDeferred { export.estimatedActiveCalories = nil }
            do {
                try await client.save(export) { attempt in
                    guard self.generation == currentGeneration, self.isEnabled else { throw CancellationError() }
                    self.journal.energyAttempts.insert(attempt)
                    try self.saveJournal()
                }
                guard generation == currentGeneration else { return }
                let previousJournal = journal
                journal.energyAttempts = journal.energyAttempts.filter { $0.workoutID != next.id }
                journal.pending.removeAll { $0.id == next.id }
                journal.completedIDs.insert(next.id)
                guard persistJournal() else {
                    journal = previousJournal
                    pendingCount = journal.pending.count
                    return
                }
                message = sharesEstimatedCalories && !client.canWriteEnergy
                    ? "Workout saved to Apple Health. Calories were omitted because Active Energy access is off."
                    : "Workout saved to Apple Health."
            } catch {
                let attempts = journal.energyAttempts.filter { $0.workoutID == next.id }
                journal.energyAttempts.subtract(attempts)
                if let cleanup = error as? AppleHealthEnergyCleanupRequired {
                    // Retain the workout identity, so only this job waits for cleanup.
                    journal.energyAttempts.insert(HealthEnergyExportAttempt(workoutID: next.id, sampleID: cleanup.sampleID))
                    journal.energyCleanupIDs.insert(cleanup.sampleID)
                    guard persistJournal() else { return }
                } else if !attempts.isEmpty {
                    guard persistJournal() else { return }
                }
                guard generation == currentGeneration else { return }
                message = "Apple Health export failed. Your workout is saved in WGJ. Retry here or reopen WGJ."
                return
            }
        }
    }

    private func energyCleanupIsUnauthorized(_ error: any Error) -> Bool {
        let error = error as NSError
        return !client.canWriteEnergy || (error.domain == HKErrorDomain
            && [HKError.Code.errorAuthorizationDenied.rawValue,
                HKError.Code.errorAuthorizationNotDetermined.rawValue].contains(error.code))
    }

    @discardableResult
    private func loadJournalIfNeeded() -> Bool {
        guard !hasLoadedJournal else { return true }
        do {
            let original = try journalStore.load()
            var loaded = original
            let discardToken = defaults.string(forKey: Self.discardPendingKey)
            let energyToken = defaults.string(forKey: Self.stripPendingEnergyKey)
            let resetToken = defaults.string(forKey: Self.resetJournalKey)
            if resetJournalWhenLoaded, resetToken != loaded.appliedResetToken { loaded.completedIDs.removeAll() }
            if !isEnabled || (discardPendingWhenLoaded && (discardToken == nil || discardToken != loaded.appliedDiscardPendingToken)) {
                loaded.pending.removeAll()
            }
            if !sharesEstimatedCalories || (stripPendingEnergyWhenLoaded && (energyToken == nil || energyToken != loaded.appliedStripPendingEnergyToken)) {
                for index in loaded.pending.indices { loaded.pending[index].estimatedActiveCalories = nil }
            }
            for var snapshot in journal.pending where !loaded.completedIDs.contains(snapshot.id)
                && !loaded.pending.contains(where: { $0.id == snapshot.id }) {
                if !sharesEstimatedCalories { snapshot.estimatedActiveCalories = nil }
                loaded.pending.append(snapshot)
            }
            loaded.energyCleanupIDs.formUnion(journal.energyCleanupIDs)
            loaded.energyAttempts.formUnion(journal.energyAttempts)
            journal = loaded
            // Clearing an unloaded queue or merging new completions must reach disk even
            // when there are no workouts left to export.
            hasUnpersistedJournalChanges = loaded != original
                || discardToken != nil
                || energyToken != nil
                || resetJournalWhenLoaded
            if !hasUnpersistedJournalChanges {
                // Loading an already-empty/stripped queue settles the preference-derived
                // intent; a later opt-in must not turn it into a new cancellation.
                discardPendingWhenLoaded = false
                stripPendingEnergyWhenLoaded = false
            }
            hasLoadedJournal = true
            pendingCount = journal.pending.count
            return true
        } catch {
            message = "Apple Health's local export queue could not be opened. Please try again."
            return false
        }
    }

    @discardableResult
    private func persistJournal() -> Bool {
        do {
            try saveJournal()
            return true
        } catch {
            return false
        }
    }

    private func saveJournal() throws {
        pendingCount = journal.pending.count
        // Commit which intents were applied alongside the queue. If the process ends before
        // clearing UserDefaults, reloading must not apply an old intent to newer completions.
        if let token = defaults.string(forKey: Self.discardPendingKey) { journal.appliedDiscardPendingToken = token }
        if let token = defaults.string(forKey: Self.stripPendingEnergyKey) { journal.appliedStripPendingEnergyToken = token }
        if let token = defaults.string(forKey: Self.resetJournalKey) { journal.appliedResetToken = token }
        do {
            try journalStore.save(journal)
            hasUnpersistedJournalChanges = false
            // Clear consent/reset markers only after their effects are committed to disk.
            defaults.removeObject(forKey: Self.discardPendingKey)
            defaults.removeObject(forKey: Self.stripPendingEnergyKey)
            defaults.removeObject(forKey: Self.resetJournalKey)
            discardPendingWhenLoaded = false
            stripPendingEnergyWhenLoaded = false
            resetJournalWhenLoaded = false
        } catch {
            hasUnpersistedJournalChanges = true
            message = "Apple Health's local export queue could not be saved. Your workout remains in WGJ."
            throw error
        }
    }
}

nonisolated private enum HealthExportResetError: LocalizedError {
    case unreadableJournal

    var errorDescription: String? {
        "Apple Health's export queue could not be opened. Its reset will be retried when the queue is available."
    }
}
