import Foundation
import SwiftData

struct WorkoutPRRecord: Identifiable, Equatable {
    let id: String
    let catalogExerciseUUID: String
    let exerciseName: String
    let estimatedOneRepMax: Double
    let weight: Double
    let reps: Int
    let loadUnit: TemplateLoadUnit
    let achievedAt: Date
}

struct SessionPRAchievement: Identifiable, Equatable {
    let id: String
    let catalogExerciseUUID: String
    let exerciseName: String
    let estimatedOneRepMax: Double
    let weight: Double
    let reps: Int
    let loadUnit: TemplateLoadUnit
}

struct WorkoutSessionSummaryMetrics: Equatable {
    let totalVolume: Double
    let prHitsCount: Int
}

enum WorkoutPersonalRecordKind: String, Identifiable, CaseIterable, Equatable, Hashable, Comparable {
    case strength
    case weight
    case reps
    case volume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength:
            return "Strength"
        case .weight:
            return "Weight"
        case .reps:
            return "Reps"
        case .volume:
            return "Volume"
        }
    }

    var chipTitle: String {
        "\(title) PR"
    }

    var systemImage: String {
        switch self {
        case .strength:
            return "bolt.fill"
        case .weight:
            return "scalemass.fill"
        case .reps:
            return "repeat"
        case .volume:
            return "chart.bar.fill"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .strength:
            return 0
        case .weight:
            return 1
        case .reps:
            return 2
        case .volume:
            return 3
        }
    }

    static func < (lhs: WorkoutPersonalRecordKind, rhs: WorkoutPersonalRecordKind) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

struct SessionSetPRAchievement: Identifiable, Equatable {
    let id: String
    let sessionExerciseID: UUID
    let setID: UUID
    let catalogExerciseUUID: String
    let exerciseName: String
    let kinds: [WorkoutPersonalRecordKind]
    let estimatedOneRepMax: Double?
    let weight: Double?
    let reps: Int
    let volume: Double?
    let loadUnit: TemplateLoadUnit
}

struct WeeklyWorkoutProgressPoint: Identifiable, Equatable {
    let id: String
    let weekStart: Date
    let completedWorkouts: Int
    let goal: Int
}

struct ExerciseHistoryOption: Identifiable, Equatable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let lastPerformedAt: Date

    var id: String { catalogExerciseUUID }
}

struct ExerciseMetricPoint: Identifiable, Equatable {
    let id: String
    let completedAt: Date
    let value: Double
}

struct ExerciseMetricSeries: Equatable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let loadUnit: TemplateLoadUnit
    let points: [ExerciseMetricPoint]
}

struct ProfileOverviewStats: Equatable {
    let totalWorkouts: Int
    let totalPRHits: Int
    let totalDurationSeconds: Int
    let currentStreakDays: Int
    let longestStreakDays: Int
    let activeDaysThisMonth: Int
    let firstWorkoutDate: Date?

    static let empty = ProfileOverviewStats(
        totalWorkouts: 0,
        totalPRHits: 0,
        totalDurationSeconds: 0,
        currentStreakDays: 0,
        longestStreakDays: 0,
        activeDaysThisMonth: 0,
        firstWorkoutDate: nil
    )
}

struct ProfileTopExerciseStat: Identifiable, Equatable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let sessionCount: Int
    let lastPerformedAt: Date

    var id: String { catalogExerciseUUID }
}

struct ProfileActivityDay: Identifiable, Equatable {
    let date: Date
    let workoutCount: Int

    var id: String { date.formatted(date: .numeric, time: .omitted) }
}

struct ProfileDashboardSnapshot: Equatable {
    let personalRecords: [WorkoutPRRecord]
    let weeklyProgress: [WeeklyWorkoutProgressPoint]
    let weeklyGoal: Int
    let overviewStats: ProfileOverviewStats
    let topExercises: [ProfileTopExerciseStat]
    let activityDays: [ProfileActivityDay]
}

private struct WeightedWorkingSetMetric: Equatable {
    let setID: UUID
    let sortOrder: Int
    let weight: Double
    let reps: Int
    let unit: TemplateLoadUnit
}

private struct BodyweightWorkingSetMetric: Equatable {
    let setID: UUID
    let sortOrder: Int
    let reps: Int
}

private enum CompletedWorkingSetMetric: Equatable {
    case weighted(WeightedWorkingSetMetric)
    case bodyweight(BodyweightWorkingSetMetric)

    var setID: UUID {
        switch self {
        case let .weighted(metric):
            return metric.setID
        case let .bodyweight(metric):
            return metric.setID
        }
    }

    var reps: Int {
        switch self {
        case let .weighted(metric):
            return metric.reps
        case let .bodyweight(metric):
            return metric.reps
        }
    }

    var sortOrder: Int {
        switch self {
        case let .weighted(metric):
            return metric.sortOrder
        case let .bodyweight(metric):
            return metric.sortOrder
        }
    }

    var loadUnit: TemplateLoadUnit {
        switch self {
        case let .weighted(metric):
            return metric.unit
        case .bodyweight:
            return .bodyweight
        }
    }
}

private struct BestSetPresentation: Equatable {
    let displayText: String
}

private enum WorkoutMetricsPolicy {
    static let summaryMetricsVersion = 1

    nonisolated static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        if reps == 1 { return weight }
        return weight * (1 + (Double(reps) / 30.0))
    }

    nonisolated static func normalizedLoad(_ value: Double, unit: TemplateLoadUnit) -> Double {
        switch unit {
        case .kg:
            return value
        case .lb:
            return value * 0.45359237
        case .bodyweight:
            return value
        }
    }

    nonisolated static func completedWorkingMetric(from set: WorkoutSessionSet) -> CompletedWorkingSetMetric? {
        guard set.isCompleted, !set.isWarmup else {
            return nil
        }

        guard let actualReps = set.actualReps, actualReps > 0 else {
            return nil
        }

        switch set.actualLoadUnit {
        case .kg, .lb:
            guard let actualWeight = set.actualWeight, actualWeight > 0 else {
                return nil
            }

            return .weighted(
                WeightedWorkingSetMetric(
                    setID: set.id,
                    sortOrder: set.sortOrder,
                    weight: actualWeight,
                    reps: actualReps,
                    unit: set.actualLoadUnit
                )
            )
        case .bodyweight:
            return .bodyweight(
                BodyweightWorkingSetMetric(
                    setID: set.id,
                    sortOrder: set.sortOrder,
                    reps: actualReps
                )
            )
        }
    }

    nonisolated static func completedWorkingMetrics(from sets: [WorkoutSessionSet]) -> [CompletedWorkingSetMetric] {
        sets
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { set in
                completedWorkingMetric(from: set)
            }
    }

    nonisolated static func completedWeightedWorkingMetrics(from sets: [WorkoutSessionSet]) -> [WeightedWorkingSetMetric] {
        completedWorkingMetrics(from: sets).compactMap { metric -> WeightedWorkingSetMetric? in
            guard case let .weighted(weightedMetric) = metric else {
                return nil
            }
            return weightedMetric
        }
    }

    nonisolated static func bestSetPresentation(from sets: [WorkoutSessionSet]) -> BestSetPresentation? {
        let workingMetrics = completedWorkingMetrics(from: sets)
        let weightedMetrics = workingMetrics.compactMap { metric -> WeightedWorkingSetMetric? in
            guard case let .weighted(weightedMetric) = metric else {
                return nil
            }
            return weightedMetric
        }

        if let bestWeightedMetric = weightedMetrics.reduce(nil as WeightedWorkingSetMetric?, { currentBest, metric in
            guard let currentBest else { return metric }
            return isBetterWeightedMetric(metric, than: currentBest) ? metric : currentBest
        }) {
            return BestSetPresentation(
                displayText: "\(WGJFormatters.decimalString(bestWeightedMetric.weight)) \(bestWeightedMetric.unit.shortLabel) x \(bestWeightedMetric.reps)"
            )
        }

        let bodyweightMetrics = workingMetrics.compactMap { metric -> BodyweightWorkingSetMetric? in
            guard case let .bodyweight(bodyweightMetric) = metric else {
                return nil
            }
            return bodyweightMetric
        }

        if let bestBodyweightMetric = bodyweightMetrics.reduce(nil as BodyweightWorkingSetMetric?, { currentBest, metric in
            guard let currentBest else { return metric }
            return isBetterBodyweightMetric(metric, than: currentBest) ? metric : currentBest
        }) {
            return BestSetPresentation(displayText: "\(bestBodyweightMetric.reps) reps")
        }

        return nil
    }

    nonisolated static func bestSetText(from sets: [WorkoutSessionSet], emptyText: String) -> String {
        bestSetPresentation(from: sets)?.displayText ?? emptyText
    }

    nonisolated static func normalizedEstimatedOneRepMax(for metric: WeightedWorkingSetMetric) -> Double {
        normalizedLoad(estimatedOneRepMax(weight: metric.weight, reps: metric.reps), unit: metric.unit)
    }

    nonisolated static func normalizedWeight(for metric: WeightedWorkingSetMetric) -> Double {
        normalizedLoad(metric.weight, unit: metric.unit)
    }

    nonisolated static func normalizedVolume(for metric: WeightedWorkingSetMetric) -> Double {
        normalizedWeight(for: metric) * Double(metric.reps)
    }

    nonisolated static func isBetterWeightedMetric(_ candidate: WeightedWorkingSetMetric, than existing: WeightedWorkingSetMetric) -> Bool {
        let candidateOneRepMax = normalizedEstimatedOneRepMax(for: candidate)
        let existingOneRepMax = normalizedEstimatedOneRepMax(for: existing)
        if candidateOneRepMax != existingOneRepMax {
            return candidateOneRepMax > existingOneRepMax
        }

        let candidateWeight = normalizedWeight(for: candidate)
        let existingWeight = normalizedWeight(for: existing)
        if candidateWeight != existingWeight {
            return candidateWeight > existingWeight
        }

        if candidate.reps != existing.reps {
            return candidate.reps > existing.reps
        }

        return candidate.sortOrder < existing.sortOrder
    }

    nonisolated static func isBetterBodyweightMetric(_ candidate: BodyweightWorkingSetMetric, than existing: BodyweightWorkingSetMetric) -> Bool {
        if candidate.reps != existing.reps {
            return candidate.reps > existing.reps
        }

        return candidate.sortOrder < existing.sortOrder
    }
}

@MainActor
final class WorkoutMetricsService {
    static let currentSummaryMetricsVersion = WorkoutMetricsPolicy.summaryMetricsVersion

    private let modelContext: ModelContext
    private let calendar: Calendar
    private let repository: WorkoutSessionRepository
    private var cachedGoal: Int?
    private var cachedMetricsSnapshot: MetricsSnapshotCache?

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.repository = WorkoutSessionRepository(modelContext: modelContext)
    }

    static func bestSetText(for sets: [WorkoutSessionSet], emptyText: String = "-") -> String {
        WorkoutMetricsPolicy.bestSetText(from: sets, emptyText: emptyText)
    }

    func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        WorkoutMetricsPolicy.estimatedOneRepMax(weight: weight, reps: reps)
    }

    func bestEstimatedOneRepMax(
        for catalogExerciseUUID: String,
        before date: Date? = nil,
        excludingSessionID: UUID? = nil
    ) throws -> Double? {
        let entries = try metricsSnapshot().exerciseHistoryByUUID[catalogExerciseUUID] ?? []
        var best: Double?

        for entry in entries {
            if let excludingSessionID, entry.sessionID == excludingSessionID {
                continue
            }
            if let date, entry.completedAt >= date {
                continue
            }
            guard let weightedOneRepMaxInKilograms = entry.weightedOneRepMaxInKilograms else { continue }
            best = max(best ?? 0, weightedOneRepMaxInKilograms)
        }

        return best
    }

    func countPRHits(sessionID: UUID) throws -> Int {
        try sessionSetPRAchievements(sessionID: sessionID).count
    }

    func sessionPRAchievements(sessionID: UUID) throws -> [SessionPRAchievement] {
        guard let session = try session(id: sessionID) else { return [] }

        var achievements: [SessionPRAchievement] = []
        achievements.reserveCapacity(orderedSessionExercises(session).count)

        for exercise in orderedSessionExercises(session) {
            var runningBest = try bestEstimatedOneRepMax(
                for: exercise.catalogExerciseUUID,
                before: session.startedAt,
                excludingSessionID: session.id
            ) ?? 0
            var bestMetric: WeightedWorkingSetMetric?

            for metric in completedWeightedWorkingSetMetrics(for: exercise) {
                let oneRM = estimatedOneRepMax(weight: metric.weight, reps: metric.reps)
                let comparisonOneRM = normalizedLoadForComparison(oneRM, unit: metric.unit)
                guard comparisonOneRM > runningBest else { continue }

                runningBest = comparisonOneRM
                if let currentBest = bestMetric {
                    if WorkoutMetricsPolicy.isBetterWeightedMetric(metric, than: currentBest) {
                        bestMetric = metric
                    }
                } else {
                    bestMetric = metric
                }
            }

            if let bestMetric {
                achievements.append(
                    SessionPRAchievement(
                        id: "\(session.id.uuidString.lowercased())_\(exercise.catalogExerciseUUID.lowercased())",
                        catalogExerciseUUID: exercise.catalogExerciseUUID,
                        exerciseName: exercise.exerciseNameSnapshot,
                        estimatedOneRepMax: estimatedOneRepMax(weight: bestMetric.weight, reps: bestMetric.reps),
                        weight: bestMetric.weight,
                        reps: bestMetric.reps,
                        loadUnit: bestMetric.unit
                    )
                )
            }
        }

        return achievements
    }

    func sessionSetPRAchievements(sessionID: UUID) throws -> [SessionSetPRAchievement] {
        guard let session = try session(id: sessionID) else { return [] }

        var achievements: [SessionSetPRAchievement] = []

        for exercise in orderedSessionExercises(session) {
            var runningBest = try priorSetMetricPeaks(
                for: exercise.catalogExerciseUUID,
                before: session.startedAt,
                excludingSessionID: session.id
            )

            for metric in completedWorkingSetMetrics(for: exercise) {
                var kinds: [WorkoutPersonalRecordKind] = []
                var estimatedOneRepMaxValue: Double?
                var weight: Double?
                var volume: Double?

                switch metric {
                case let .weighted(weightedMetric):
                    let oneRepMax = estimatedOneRepMax(weight: weightedMetric.weight, reps: weightedMetric.reps)
                    let comparisonOneRepMax = normalizedLoadForComparison(oneRepMax, unit: weightedMetric.unit)
                    let normalizedWeight = normalizedLoadForComparison(weightedMetric.weight, unit: weightedMetric.unit)
                    let normalizedVolume = normalizedWeight * Double(weightedMetric.reps)

                    if comparisonOneRepMax > runningBest.strength {
                        runningBest.strength = comparisonOneRepMax
                        kinds.append(.strength)
                    }

                    if normalizedWeight > runningBest.weight {
                        runningBest.weight = normalizedWeight
                        kinds.append(.weight)
                    }

                    if normalizedVolume > runningBest.volume {
                        runningBest.volume = normalizedVolume
                        kinds.append(.volume)
                    }

                    estimatedOneRepMaxValue = oneRepMax
                    weight = weightedMetric.weight
                    volume = normalizedVolume

                case .bodyweight:
                    break
                }

                if metric.reps > runningBest.reps {
                    runningBest.reps = metric.reps
                    kinds.append(.reps)
                }

                guard !kinds.isEmpty else { continue }

                achievements.append(
                    SessionSetPRAchievement(
                        id: "\(session.id.uuidString.lowercased())_\(metric.setID.uuidString.lowercased())",
                        sessionExerciseID: exercise.id,
                        setID: metric.setID,
                        catalogExerciseUUID: exercise.catalogExerciseUUID,
                        exerciseName: exercise.exerciseNameSnapshot,
                        kinds: kinds.sorted(),
                        estimatedOneRepMax: estimatedOneRepMaxValue,
                        weight: weight,
                        reps: metric.reps,
                        volume: volume,
                        loadUnit: metric.loadUnit
                    )
                )
            }
        }

        return achievements
    }

    func totalVolume(sessionID: UUID) throws -> Double {
        guard let session = try session(id: sessionID) else { return 0 }
        return totalWeightedVolume(for: session)
    }

    func sessionSummary(sessionID: UUID) throws -> WorkoutSessionSummaryMetrics {
        guard let session = try session(id: sessionID) else {
            return WorkoutSessionSummaryMetrics(totalVolume: 0, prHitsCount: 0)
        }

        return WorkoutSessionSummaryMetrics(
            totalVolume: totalWeightedVolume(for: session),
            prHitsCount: try sessionSetPRAchievements(sessionID: sessionID).count
        )
    }

    func personalRecords(limit: Int = 8) throws -> [WorkoutPRRecord] {
        try profileDashboardSnapshot(prLimit: limit, weeks: 1).personalRecords
    }

    func weeklyWorkoutProgress(weeks: Int = 8) throws -> [WeeklyWorkoutProgressPoint] {
        try profileDashboardSnapshot(prLimit: 1, weeks: weeks).weeklyProgress
    }

    func exerciseHistoryOptions() throws -> [ExerciseHistoryOption] {
        let exerciseHistoryByUUID = try metricsSnapshot().exerciseHistoryByUUID
        var latestByExercise: [String: ExerciseHistoryOption] = [:]

        for (catalogExerciseUUID, entries) in exerciseHistoryByUUID {
            guard let latestEntry = entries.first(where: { $0.weightedOneRepMaxInKilograms != nil || $0.totalWeightedVolumeInKilograms != nil }) else {
                continue
            }

            latestByExercise[catalogExerciseUUID] = ExerciseHistoryOption(
                catalogExerciseUUID: catalogExerciseUUID,
                exerciseName: latestEntry.exerciseName,
                lastPerformedAt: latestEntry.completedAt
            )
        }

        return latestByExercise.values.sorted { lhs, rhs in
            if lhs.lastPerformedAt != rhs.lastPerformedAt {
                return lhs.lastPerformedAt > rhs.lastPerformedAt
            }
            return lhs.exerciseName.localizedStandardCompare(rhs.exerciseName) == .orderedAscending
        }
    }

    func exerciseOneRepMaxTrend(
        for catalogExerciseUUID: String,
        preferredExerciseName: String? = nil,
        limit: Int = 8
    ) throws -> ExerciseMetricSeries {
        let safeLimit = max(1, limit)
        var recentPoints: [CollectedExerciseMetricPoint] = []
        var exerciseName = preferredExerciseName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if exerciseName?.isEmpty == true {
            exerciseName = nil
        }

        let entries = try metricsSnapshot().exerciseHistoryByUUID[catalogExerciseUUID] ?? []
        for entry in entries {
            guard let bestOneRepMaxInKilograms = entry.weightedOneRepMaxInKilograms else { continue }
            if exerciseName == nil {
                exerciseName = entry.exerciseName
            }
            recentPoints.append(
                CollectedExerciseMetricPoint(
                    completedAt: entry.completedAt,
                    normalizedValue: bestOneRepMaxInKilograms,
                    sourceUnit: entry.weightedOneRepMaxUnit
                )
            )

            if recentPoints.count == safeLimit {
                break
            }
        }

        return buildExerciseMetricSeries(
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseName: exerciseName ?? "Exercise",
            points: recentPoints
        )
    }

    func exerciseVolumeTrend(
        for catalogExerciseUUID: String,
        preferredExerciseName: String? = nil,
        limit: Int = 8
    ) throws -> ExerciseMetricSeries {
        let safeLimit = max(1, limit)
        var recentPoints: [CollectedExerciseMetricPoint] = []
        var exerciseName = preferredExerciseName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if exerciseName?.isEmpty == true {
            exerciseName = nil
        }

        let entries = try metricsSnapshot().exerciseHistoryByUUID[catalogExerciseUUID] ?? []
        for entry in entries {
            guard let totalVolumeInKilograms = entry.totalWeightedVolumeInKilograms else { continue }
            if exerciseName == nil {
                exerciseName = entry.exerciseName
            }
            recentPoints.append(
                CollectedExerciseMetricPoint(
                    completedAt: entry.completedAt,
                    normalizedValue: totalVolumeInKilograms,
                    sourceUnit: entry.weightedVolumeUnit
                )
            )

            if recentPoints.count == safeLimit {
                break
            }
        }

        return buildExerciseMetricSeries(
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseName: exerciseName ?? "Exercise",
            points: recentPoints
        )
    }

    func profileDashboardSnapshot(prLimit: Int = 8, weeks: Int = 8) throws -> ProfileDashboardSnapshot {
        let safePRLimit = max(1, prLimit)
        let safeWeeks = max(1, weeks)
        let profileGoal = try currentGoal()
        let snapshot = try metricsSnapshot()
        let nowWeek = weekStart(for: Date())
        var weeksToInclude: [Date] = []
        weeksToInclude.reserveCapacity(safeWeeks)
        for offset in (0..<safeWeeks).reversed() {
            if let week = calendar.date(byAdding: .weekOfYear, value: -offset, to: nowWeek) {
                weeksToInclude.append(week)
            }
        }
        let personalRecords = snapshot.bestPRByExercise.values
            .sorted { lhs, rhs in
                let lhsValue = normalizedLoadForComparison(lhs.estimatedOneRepMax, unit: lhs.loadUnit)
                let rhsValue = normalizedLoadForComparison(rhs.estimatedOneRepMax, unit: rhs.loadUnit)
                if lhsValue != rhsValue {
                    return lhsValue > rhsValue
                }
                return lhs.exerciseName.localizedStandardCompare(rhs.exerciseName) == .orderedAscending
            }
            .prefix(safePRLimit)
            .map { $0 }
        let weeklyProgress = weeksToInclude.map { week in
            WeeklyWorkoutProgressPoint(
                id: week.formatted(date: .numeric, time: .omitted),
                weekStart: week,
                completedWorkouts: snapshot.countsByWeek[week, default: 0],
                goal: profileGoal
            )
        }
        let overviewStats = buildOverviewStats(
            completedWorkoutCount: snapshot.completedSessions.count,
            totalPRHits: snapshot.totalPRHits,
            totalDurationSeconds: snapshot.totalDurationSeconds,
            workoutCountsByDay: snapshot.countsByDay,
            firstWorkoutDate: snapshot.firstWorkoutDate
        )
        let topExercises = snapshot.exerciseFrequencyByUUID.map { entry in
            ProfileTopExerciseStat(
                catalogExerciseUUID: entry.key,
                exerciseName: entry.value.exerciseName,
                sessionCount: entry.value.sessionCount,
                lastPerformedAt: entry.value.lastPerformedAt
            )
        }
        .sorted { lhs, rhs in
            if lhs.sessionCount != rhs.sessionCount {
                return lhs.sessionCount > rhs.sessionCount
            }
            if lhs.lastPerformedAt != rhs.lastPerformedAt {
                return lhs.lastPerformedAt > rhs.lastPerformedAt
            }
            return lhs.exerciseName.localizedStandardCompare(rhs.exerciseName) == .orderedAscending
        }
        let activityDays = buildActivityDays(from: snapshot.countsByDay)

        return ProfileDashboardSnapshot(
            personalRecords: personalRecords,
            weeklyProgress: weeklyProgress,
            weeklyGoal: profileGoal,
            overviewStats: overviewStats,
            topExercises: topExercises,
            activityDays: activityDays
        )
    }

    private func completedSessions() throws -> [WorkoutSession] {
        try metricsSnapshot().completedSessions
    }

    private func metricsSnapshot() throws -> MetricsSnapshotCache {
        if let cachedMetricsSnapshot {
            return cachedMetricsSnapshot
        }

        let snapshot = try WGJPerformance.measure("metrics.snapshot") {
            let sessions = try repository.completedSessions()
            var bestPRByExercise: [String: WorkoutPRRecord] = [:]
            var countsByWeek: [Date: Int] = [:]
            var countsByDay: [Date: Int] = [:]
            var exerciseFrequencyByUUID: [String: CollectedExerciseFrequency] = [:]
            var exerciseHistoryByUUID: [String: [CompletedExerciseHistoryEntry]] = [:]
            var totalDurationSeconds = 0
            var totalPRHits = 0
            var firstWorkoutDate: Date?

            for session in sessions {
                let completedAt = session.endedAt ?? session.startedAt
                let week = weekStart(for: completedAt)
                let day = calendar.startOfDay(for: completedAt)
                countsByWeek[week, default: 0] += 1
                countsByDay[day, default: 0] += 1
                totalDurationSeconds += max(0, session.durationSeconds)
                totalPRHits += max(0, session.prHitsCount)

                if let existingFirstWorkoutDate = firstWorkoutDate {
                    if completedAt < existingFirstWorkoutDate {
                        firstWorkoutDate = completedAt
                    }
                } else {
                    firstWorkoutDate = completedAt
                }

                var countedExerciseUUIDs: Set<String> = []
                var perSessionHistory: [String: WorkingExerciseHistoryEntry] = [:]

                for exercise in orderedSessionExercises(session) {
                    if countedExerciseUUIDs.insert(exercise.catalogExerciseUUID).inserted {
                        if let existing = exerciseFrequencyByUUID[exercise.catalogExerciseUUID] {
                            exerciseFrequencyByUUID[exercise.catalogExerciseUUID] = CollectedExerciseFrequency(
                                exerciseName: completedAt >= existing.lastPerformedAt ? exercise.exerciseNameSnapshot : existing.exerciseName,
                                sessionCount: existing.sessionCount + 1,
                                lastPerformedAt: max(existing.lastPerformedAt, completedAt)
                            )
                        } else {
                            exerciseFrequencyByUUID[exercise.catalogExerciseUUID] = CollectedExerciseFrequency(
                                exerciseName: exercise.exerciseNameSnapshot,
                                sessionCount: 1,
                                lastPerformedAt: completedAt
                            )
                        }
                    }

                    var historyEntry = perSessionHistory[exercise.catalogExerciseUUID]
                        ?? WorkingExerciseHistoryEntry(exerciseName: exercise.exerciseNameSnapshot)
                    historyEntry.exerciseName = exercise.exerciseNameSnapshot

                    for weightedMetric in completedWeightedWorkingSetMetrics(for: exercise) {
                        let weightedOneRepMaxInKilograms = normalizedLoadForComparison(
                            estimatedOneRepMax(weight: weightedMetric.weight, reps: weightedMetric.reps),
                            unit: weightedMetric.unit
                        )
                        historyEntry.comparisonOneRepMax = max(
                            historyEntry.comparisonOneRepMax ?? 0,
                            weightedOneRepMaxInKilograms
                        )

                        let record = WorkoutPRRecord(
                            id: exercise.catalogExerciseUUID,
                            catalogExerciseUUID: exercise.catalogExerciseUUID,
                            exerciseName: exercise.exerciseNameSnapshot,
                            estimatedOneRepMax: estimatedOneRepMax(weight: weightedMetric.weight, reps: weightedMetric.reps),
                            weight: weightedMetric.weight,
                            reps: weightedMetric.reps,
                            loadUnit: weightedMetric.unit,
                            achievedAt: completedAt
                        )

                        if let existing = bestPRByExercise[exercise.catalogExerciseUUID] {
                            if isBetterPRRecord(record, than: existing) {
                                bestPRByExercise[exercise.catalogExerciseUUID] = record
                            }
                        } else {
                            bestPRByExercise[exercise.catalogExerciseUUID] = record
                        }

                        if let currentBest = historyEntry.weightedOneRepMaxInKilograms {
                            if weightedOneRepMaxInKilograms > currentBest {
                                historyEntry.weightedOneRepMaxInKilograms = weightedOneRepMaxInKilograms
                                historyEntry.weightedOneRepMaxUnit = weightedMetric.unit
                            }
                        } else {
                            historyEntry.weightedOneRepMaxInKilograms = weightedOneRepMaxInKilograms
                            historyEntry.weightedOneRepMaxUnit = weightedMetric.unit
                        }

                        historyEntry.totalWeightedVolumeInKilograms += normalizedLoadForComparison(
                            weightedMetric.weight,
                            unit: weightedMetric.unit
                        ) * Double(weightedMetric.reps)
                        historyEntry.weightedVolumeUnit = weightedMetric.unit
                        historyEntry.hasWeightedMetrics = true
                    }

                    perSessionHistory[exercise.catalogExerciseUUID] = historyEntry
                }

                for (catalogExerciseUUID, historyEntry) in perSessionHistory
                    where historyEntry.comparisonOneRepMax != nil || historyEntry.hasWeightedMetrics
                {
                    exerciseHistoryByUUID[catalogExerciseUUID, default: []].append(
                        CompletedExerciseHistoryEntry(
                            sessionID: session.id,
                            completedAt: completedAt,
                            exerciseName: historyEntry.exerciseName,
                            comparisonOneRepMax: historyEntry.comparisonOneRepMax,
                            weightedOneRepMaxInKilograms: historyEntry.weightedOneRepMaxInKilograms,
                            weightedOneRepMaxUnit: historyEntry.weightedOneRepMaxUnit ?? .kg,
                            totalWeightedVolumeInKilograms: historyEntry.hasWeightedMetrics
                                ? historyEntry.totalWeightedVolumeInKilograms
                                : nil,
                            weightedVolumeUnit: historyEntry.weightedVolumeUnit ?? .kg
                        )
                    )
                }
            }

            return MetricsSnapshotCache(
                completedSessions: sessions,
                bestPRByExercise: bestPRByExercise,
                countsByWeek: countsByWeek,
                countsByDay: countsByDay,
                exerciseFrequencyByUUID: exerciseFrequencyByUUID,
                exerciseHistoryByUUID: exerciseHistoryByUUID,
                totalDurationSeconds: totalDurationSeconds,
                totalPRHits: totalPRHits,
                firstWorkoutDate: firstWorkoutDate
            )
        }

        cachedMetricsSnapshot = snapshot
        return snapshot
    }

    private func session(id: UUID) throws -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.id == id
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func orderedSessionExercises(_ session: WorkoutSession) -> [WorkoutSessionExercise] {
        (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private func orderedSessionSets(_ exercise: WorkoutSessionExercise) -> [WorkoutSessionSet] {
        (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private func completedWorkingSetMetrics(for exercise: WorkoutSessionExercise) -> [CompletedWorkingSetMetric] {
        WorkoutMetricsPolicy.completedWorkingMetrics(from: orderedSessionSets(exercise))
    }

    private func completedWeightedWorkingSetMetrics(for exercise: WorkoutSessionExercise) -> [WeightedWorkingSetMetric] {
        WorkoutMetricsPolicy.completedWeightedWorkingMetrics(from: orderedSessionSets(exercise))
    }

    private func totalWeightedVolume(for session: WorkoutSession) -> Double {
        orderedSessionExercises(session).reduce(into: 0.0) { total, exercise in
            for metric in completedWeightedWorkingSetMetrics(for: exercise) {
                total += normalizedLoadForComparison(metric.weight, unit: metric.unit) * Double(metric.reps)
            }
        }
    }

    private func currentGoal() throws -> Int {
        if let cachedGoal {
            return cachedGoal
        }

        let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        let profile = try modelContext.fetch(descriptor).first
        let resolvedGoal = max(1, min(14, profile?.weeklyWorkoutGoal ?? 4))
        cachedGoal = resolvedGoal
        return resolvedGoal
    }

    private func priorSetMetricPeaks(
        for catalogExerciseUUID: String,
        before date: Date? = nil,
        excludingSessionID: UUID? = nil
    ) throws -> PriorSetMetricPeaks {
        let sessions = try completedSessions()
        var peaks = PriorSetMetricPeaks()

        for session in sessions {
            if let excludingSessionID, session.id == excludingSessionID {
                continue
            }

            let completedAt = session.endedAt ?? session.startedAt
            if let date, completedAt >= date {
                continue
            }

            for exercise in orderedSessionExercises(session) where exercise.catalogExerciseUUID == catalogExerciseUUID {
                for metric in completedWorkingSetMetrics(for: exercise) {
                    if case let .weighted(weightedMetric) = metric {
                        peaks.strength = max(
                            peaks.strength,
                            comparisonOneRepMax(weight: weightedMetric.weight, reps: weightedMetric.reps, unit: weightedMetric.unit)
                        )
                        peaks.weight = max(
                            peaks.weight,
                            normalizedLoadForComparison(weightedMetric.weight, unit: weightedMetric.unit)
                        )
                        peaks.volume = max(
                            peaks.volume,
                            normalizedLoadForComparison(weightedMetric.weight, unit: weightedMetric.unit) * Double(weightedMetric.reps)
                        )
                    }

                    peaks.reps = max(peaks.reps, metric.reps)
                }
            }
        }

        return peaks
    }

    private func weekStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    private func buildOverviewStats(
        completedWorkoutCount: Int,
        totalPRHits: Int,
        totalDurationSeconds: Int,
        workoutCountsByDay: [Date: Int],
        firstWorkoutDate: Date?
    ) -> ProfileOverviewStats {
        let distinctWorkoutDays = workoutCountsByDay.keys.sorted()
        let streaks = streakSummary(for: distinctWorkoutDays)
        let activeDaysThisMonth = distinctWorkoutDays.filter { isInCurrentMonth($0) }.count

        return ProfileOverviewStats(
            totalWorkouts: completedWorkoutCount,
            totalPRHits: totalPRHits,
            totalDurationSeconds: totalDurationSeconds,
            currentStreakDays: streaks.current,
            longestStreakDays: streaks.longest,
            activeDaysThisMonth: activeDaysThisMonth,
            firstWorkoutDate: firstWorkoutDate
        )
    }

    private func buildActivityDays(from workoutCountsByDay: [Date: Int], window: Int = 42) -> [ProfileActivityDay] {
        let safeWindow = max(1, window)
        let today = calendar.startOfDay(for: Date())

        return (0..<safeWindow).compactMap { offset in
            let daysBack = safeWindow - 1 - offset
            guard let date = calendar.date(byAdding: .day, value: -daysBack, to: today) else {
                return nil
            }

            let day = calendar.startOfDay(for: date)
            return ProfileActivityDay(
                date: day,
                workoutCount: workoutCountsByDay[day, default: 0]
            )
        }
    }

    private func streakSummary(for workoutDays: [Date]) -> (current: Int, longest: Int) {
        guard !workoutDays.isEmpty else { return (0, 0) }

        var longest = 1
        var running = 1

        if workoutDays.count >= 2 {
            for index in 1..<workoutDays.count {
                if isConsecutiveDay(previous: workoutDays[index - 1], next: workoutDays[index]) {
                    running += 1
                } else {
                    running = 1
                }

                longest = max(longest, running)
            }
        }

        guard let latestWorkoutDay = workoutDays.last else {
            return (0, longest)
        }

        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        guard calendar.isDate(latestWorkoutDay, inSameDayAs: today)
            || calendar.isDate(latestWorkoutDay, inSameDayAs: yesterday)
        else {
            return (0, longest)
        }

        var current = 1
        var index = workoutDays.count - 1

        while index > 0 {
            if isConsecutiveDay(previous: workoutDays[index - 1], next: workoutDays[index]) {
                current += 1
                index -= 1
            } else {
                break
            }
        }

        return (current, longest)
    }

    private func isConsecutiveDay(previous: Date, next: Date) -> Bool {
        guard let expectedNextDay = calendar.date(byAdding: .day, value: 1, to: previous) else {
            return false
        }

        return calendar.isDate(expectedNextDay, inSameDayAs: next)
    }

    private func isInCurrentMonth(_ date: Date) -> Bool {
        let currentComponents = calendar.dateComponents([.year, .month], from: Date())
        let dateComponents = calendar.dateComponents([.year, .month], from: date)
        return currentComponents.year == dateComponents.year && currentComponents.month == dateComponents.month
    }

    private func comparisonOneRepMax(weight: Double, reps: Int, unit: TemplateLoadUnit) -> Double {
        normalizedLoadForComparison(estimatedOneRepMax(weight: weight, reps: reps), unit: unit)
    }

    private func normalizedLoadForComparison(_ value: Double, unit: TemplateLoadUnit) -> Double {
        WorkoutMetricsPolicy.normalizedLoad(value, unit: unit)
    }

    private func displayValue(_ valueInKilograms: Double, unit: TemplateLoadUnit) -> Double {
        switch unit {
        case .kg:
            return valueInKilograms
        case .lb:
            return valueInKilograms / 0.45359237
        case .bodyweight:
            return valueInKilograms
        }
    }

    private func buildExerciseMetricSeries(
        catalogExerciseUUID: String,
        exerciseName: String,
        points: [CollectedExerciseMetricPoint]
    ) -> ExerciseMetricSeries {
        let displayUnit = points.first?.sourceUnit ?? .kg
        let orderedPoints = points.reversed().map { point in
            ExerciseMetricPoint(
                id: "\(catalogExerciseUUID.lowercased())_\(point.completedAt.timeIntervalSinceReferenceDate)",
                completedAt: point.completedAt,
                value: displayValue(point.normalizedValue, unit: displayUnit)
            )
        }

        return ExerciseMetricSeries(
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseName: exerciseName,
            loadUnit: displayUnit,
            points: orderedPoints
        )
    }

    private func isBetterPRRecord(_ candidate: WorkoutPRRecord, than existing: WorkoutPRRecord) -> Bool {
        let candidateValue = normalizedLoadForComparison(candidate.estimatedOneRepMax, unit: candidate.loadUnit)
        let existingValue = normalizedLoadForComparison(existing.estimatedOneRepMax, unit: existing.loadUnit)

        if candidateValue != existingValue {
            return candidateValue > existingValue
        }

        return candidate.achievedAt > existing.achievedAt
    }
}

private struct CollectedExerciseMetricPoint {
    let completedAt: Date
    let normalizedValue: Double
    let sourceUnit: TemplateLoadUnit
}

private struct PriorSetMetricPeaks {
    var strength: Double = 0
    var weight: Double = 0
    var reps: Int = 0
    var volume: Double = 0
}

private struct MetricsSnapshotCache {
    let completedSessions: [WorkoutSession]
    let bestPRByExercise: [String: WorkoutPRRecord]
    let countsByWeek: [Date: Int]
    let countsByDay: [Date: Int]
    let exerciseFrequencyByUUID: [String: CollectedExerciseFrequency]
    let exerciseHistoryByUUID: [String: [CompletedExerciseHistoryEntry]]
    let totalDurationSeconds: Int
    let totalPRHits: Int
    let firstWorkoutDate: Date?
}

private struct CompletedExerciseHistoryEntry {
    let sessionID: UUID
    let completedAt: Date
    let exerciseName: String
    let comparisonOneRepMax: Double?
    let weightedOneRepMaxInKilograms: Double?
    let weightedOneRepMaxUnit: TemplateLoadUnit
    let totalWeightedVolumeInKilograms: Double?
    let weightedVolumeUnit: TemplateLoadUnit
}

private struct WorkingExerciseHistoryEntry {
    var exerciseName: String
    var comparisonOneRepMax: Double?
    var weightedOneRepMaxInKilograms: Double?
    var weightedOneRepMaxUnit: TemplateLoadUnit?
    var totalWeightedVolumeInKilograms: Double = 0
    var weightedVolumeUnit: TemplateLoadUnit?
    var hasWeightedMetrics = false
}

private struct CollectedExerciseFrequency {
    let exerciseName: String
    let sessionCount: Int
    let lastPerformedAt: Date
}
