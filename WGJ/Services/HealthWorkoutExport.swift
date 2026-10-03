import Foundation
import HealthKit

/// A value snapshot taken after the local completion commit. Never pass SwiftData models to HealthKit.
nonisolated struct HealthWorkoutExport: Codable, Equatable, Sendable, Identifiable {
    enum Activity: String, Codable, Sendable {
        case strength, crossTraining, walking, running, cycling, rowing, elliptical, stairs, other

        var healthKitType: HKWorkoutActivityType {
            switch self {
            case .strength: .traditionalStrengthTraining
            case .crossTraining: .crossTraining
            case .walking: .walking
            case .running: .running
            case .cycling: .cycling
            case .rowing: .rowing
            case .elliptical: .elliptical
            case .stairs: .stairClimbing
            case .other: .other
            }
        }
    }

    let id: UUID
    let name: String
    let start: Date
    let end: Date
    let activity: Activity
    var estimatedActiveCalories: Int?
    let calorieEstimateVersion: Int?

    var syncIdentifier: String { "wgj.workout.\(id.uuidString)" }

    static func snapshot(from session: WorkoutSession) -> Self? {
        guard session.status == .completed, let end = session.endedAt,
              end > session.startedAt,
              end.timeIntervalSince(session.startedAt) <= 24 * 60 * 60 else { return nil }
        let hasStrength = (session.exercises ?? []).contains { exercise in
            (exercise.sets ?? []).contains { WorkoutSessionSetDraft(model: $0).isCycleCompleted }
        }
        let cardio = (session.cardioBlocks ?? []).filter {
            $0.isCompleted && ($0.actualDurationSeconds ?? 0) > 0
        }
        guard hasStrength || !cardio.isEmpty else { return nil }
        let activity: Activity
        if hasStrength {
            activity = cardio.isEmpty ? .strength : .crossTraining
        } else {
            let activities = Set(cardio.map { activityType(name: $0.exerciseNameSnapshot, profile: $0.trackingProfile) })
            activity = activities.count == 1 ? activities.first! : .crossTraining
        }
        return Self(id: session.id, name: session.name, start: session.startedAt, end: end,
                    activity: activity, estimatedActiveCalories: session.estimatedActiveCalories,
                    calorieEstimateVersion: session.calorieEstimateVersion)
    }

    static func activityType(name: String, profile: WorkoutCardioTrackingProfile?) -> Activity {
        let name = name.lowercased()
        if profile == .rower || name.contains("row") { return .rowing }
        if profile == .stairClimber || name.contains("stair") { return .stairs }
        if name.contains("elliptical") || name.contains("cross trainer") || name.contains("crosstrainer") { return .elliptical }
        if name.contains("bike") || name.contains("cycl") { return .cycling }
        if name.contains("run") || name.contains("jog") { return .running }
        if name.contains("walk") { return .walking }
        // A treadmill or distance profile alone doesn't tell us whether the person walked or ran.
        return .other
    }
}

/// Written before HealthKit inserts calories; retained until the workout's outcome is durable.
nonisolated struct HealthEnergyExportAttempt: Codable, Hashable, Sendable {
    let workoutID: UUID
    let sampleID: UUID
    static let metadataKey = "se.highball.wgj.energySampleID"
}

nonisolated struct HealthExportJournal: Codable, Equatable, Sendable {
    var pending: [HealthWorkoutExport] = []
    var completedIDs: Set<UUID> = []
    var energyCleanupIDs: Set<UUID> = []
    var energyAttempts: Set<HealthEnergyExportAttempt> = []
    var appliedDiscardPendingToken: String?
    var appliedStripPendingEnergyToken: String?
    var appliedResetToken: String?

    init(pending: [HealthWorkoutExport] = [], completedIDs: Set<UUID> = [], energyCleanupIDs: Set<UUID> = [],
         energyAttempts: Set<HealthEnergyExportAttempt> = []) {
        self.pending = pending
        self.completedIDs = completedIDs
        self.energyCleanupIDs = energyCleanupIDs
        self.energyAttempts = energyAttempts
    }

    private enum CodingKeys: String, CodingKey {
        case pending, completedIDs, energyCleanupIDs, energyAttempts
        case appliedDiscardPendingToken, appliedStripPendingEnergyToken, appliedResetToken
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pending = try values.decode([HealthWorkoutExport].self, forKey: .pending)
        completedIDs = try values.decode(Set<UUID>.self, forKey: .completedIDs)
        energyCleanupIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .energyCleanupIDs) ?? []
        energyAttempts = try values.decodeIfPresent(Set<HealthEnergyExportAttempt>.self, forKey: .energyAttempts) ?? []
        appliedDiscardPendingToken = try values.decodeIfPresent(String.self, forKey: .appliedDiscardPendingToken)
        appliedStripPendingEnergyToken = try values.decodeIfPresent(String.self, forKey: .appliedStripPendingEnergyToken)
        appliedResetToken = try values.decodeIfPresent(String.self, forKey: .appliedResetToken)
    }
}

@MainActor
protocol HealthExportJournalStoring {
    func load() throws -> HealthExportJournal
    func save(_ journal: HealthExportJournal) throws
}

/// Device-local and excluded from iCloud device backups as well as WGJ's CloudKit payload.
@MainActor
final class FileHealthExportJournalStore: HealthExportJournalStoring {
    private let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("AppleHealthExport", isDirectory: true)) {
        self.directory = directory
    }

    func load() throws -> HealthExportJournal {
        let file = directory.appendingPathComponent("journal.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return HealthExportJournal() }
        return try JSONDecoder().decode(HealthExportJournal.self, from: Data(contentsOf: file))
    }

    func save(_ journal: HealthExportJournal) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let file = directory.appendingPathComponent("journal.json")
        try JSONEncoder().encode(journal).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var protectedFile = file
        try protectedFile.setResourceValues(values)
    }
}
