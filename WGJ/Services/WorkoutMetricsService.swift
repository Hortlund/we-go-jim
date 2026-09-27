import Foundation
import SwiftData

nonisolated struct WorkoutPRRecord: Identifiable, Equatable, Sendable {
    let id: String
    let catalogExerciseUUID: String
    let exerciseName: String
    let estimatedOneRepMax: Double?
    let weight: Double
    let reps: Int
    let loadUnit: TemplateLoadUnit
    let achievedAt: Date
    var usesAddedWeight: Bool = false
    var usesAssistance: Bool = false
}

nonisolated struct SessionPRAchievement: Identifiable, Equatable, Sendable {
    let id: String
    let catalogExerciseUUID: String
    let exerciseName: String
    let estimatedOneRepMax: Double
    let weight: Double
    let reps: Int
    let loadUnit: TemplateLoadUnit
}

nonisolated struct WorkoutSessionSummaryMetrics: Equatable, Sendable {
    let totalVolume: Double
    let prHitsCount: Int
}

nonisolated enum WorkoutPersonalRecordKind: String, Identifiable, CaseIterable, Equatable, Hashable, Comparable, Sendable {
    case strength
    case weight
    case reps
    case volume
    case assistance
    case assistedReps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assistance: return "Least Assistance"
        case .assistedReps: return "Reps at Same Assistance"
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
        case .assistance: return "arrow.down.circle.fill"
        case .assistedReps: return "repeat"
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
        case .assistance: return 4
        case .assistedReps: return 5
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

nonisolated struct SessionSetPRAchievement: Identifiable, Equatable, Sendable {
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
    var usesAddedWeight: Bool = false
    var usesAssistance: Bool = false
}

nonisolated struct WeeklyWorkoutProgressPoint: Identifiable, Equatable, Sendable {
    let id: String
    let weekStart: Date
    let completedWorkouts: Int
    let goal: Int
}

nonisolated struct ExerciseHistoryOption: Identifiable, Equatable, Sendable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let lastPerformedAt: Date
    let trendMetric: ProfileExerciseTrendMetric
    let availableTrendMetrics: Set<ProfileExerciseTrendMetric>

    var id: String { catalogExerciseUUID }

    func selectingMetric(_ requested: ProfileExerciseTrendMetric) -> Self {
        Self(catalogExerciseUUID: catalogExerciseUUID, exerciseName: exerciseName,
             lastPerformedAt: lastPerformedAt,
             trendMetric: availableTrendMetrics.contains(requested) ? requested : .maxReps,
             availableTrendMetrics: availableTrendMetrics)
    }
}

nonisolated struct ExerciseMetricPoint: Identifiable, Equatable, Sendable {
    let id: String
    let completedAt: Date
    let value: Double
    var context: String? = nil
    var performance: ExerciseSetPerformance? = nil
}

nonisolated struct ExerciseMetricSeries: Equatable, Sendable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let loadUnit: TemplateLoadUnit
    let points: [ExerciseMetricPoint]
    var usesAddedWeight: Bool = false
    var usesAssistance: Bool = false
}

nonisolated struct ExerciseDetailBestPerformance: Equatable, Sendable {
    nonisolated enum Kind: String, Equatable {
        case weighted
        case bodyweight
    }

    let kind: Kind
    let reps: Int
    let weight: Double?
    let loadUnit: TemplateLoadUnit
    let estimatedOneRepMax: Double?
    let achievedAt: Date
}

nonisolated struct ExerciseDetailStatsSnapshot: Equatable, Sendable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let sessionCount: Int
    let lastPerformedAt: Date
    let bestPerformance: ExerciseDetailBestPerformance?
    let oneRepMaxTrend: ExerciseMetricSeries?
    let volumeTrend: ExerciseMetricSeries?
}

nonisolated struct ProfileOverviewStats: Equatable, Sendable {
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

nonisolated struct ProfileTopExerciseStat: Identifiable, Equatable, Sendable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let sessionCount: Int
    let lastPerformedAt: Date

    var id: String { catalogExerciseUUID }
}

nonisolated struct ProfileActivityDay: Identifiable, Equatable, Sendable {
    let date: Date
    let workoutCount: Int

    var id: String { date.formatted(date: .numeric, time: .omitted) }
}

nonisolated struct ProfileDashboardSnapshot: Equatable, Sendable {
    let personalRecords: [WorkoutPRRecord]
    let weeklyProgress: [WeeklyWorkoutProgressPoint]
    let weeklyMuscleHeatmap: ProfileWeeklyMuscleHeatmapSnapshot
    let weeklyGoal: Int
    let overviewStats: ProfileOverviewStats
    let topExercises: [ProfileTopExerciseStat]
    let activityDays: [ProfileActivityDay]
    var bodyweightPersonalRecords: [BodyweightExerciseBestRecord] = []
}

nonisolated struct ProfileWeeklyMuscleHeatmapSnapshot: Equatable, Sendable {
    let weekStart: Date
    let entries: [ProfileWeeklyMuscleHeatmapEntry]
    let topRegionNames: [String]

    static let empty = ProfileWeeklyMuscleHeatmapSnapshot(
        weekStart: Date(timeIntervalSince1970: 0),
        entries: [],
        topRegionNames: []
    )
}

typealias ProfileWeeklyMuscleHeatmapEntry = WorkoutMuscleHeatmapEntry

nonisolated private struct WeightedWorkingSetMetric: Equatable {
    let setID: UUID
    let sortOrder: Int
    let weight: Double
    let reps: Int
    let unit: TemplateLoadUnit
}

nonisolated private struct BodyweightWorkingSetMetric: Equatable {
    let setID: UUID
    let sortOrder: Int
    let reps: Int
}

nonisolated private enum CompletedWorkingSetMetric: Equatable {
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

nonisolated private struct BestSetPresentation: Equatable {
    let displayText: String
}

nonisolated private enum WorkoutMetricsPolicy {
    // Bump when session summary math or projected history facts change semantics.
    nonisolated static let summaryMetricsVersion = 7

    nonisolated static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        WorkoutPerformanceMath.estimatedOneRepMax(weight: weight, reps: reps)
    }

    nonisolated static func normalizedLoad(_ value: Double, unit: TemplateLoadUnit) -> Double {
        WorkoutPerformanceMath.normalizedLoadInKilograms(value, unit: unit)
    }

    nonisolated static func completedWorkingMetric(from set: WorkoutSessionSet) -> CompletedWorkingSetMetric? {
        guard set.isCompleted, !set.isWarmup else {
            return nil
        }

        guard let actualReps = set.actualReps, actualReps > 0 else {
            return nil
        }

        let normalizedActualLoad = WorkoutLoggedLoadNormalization.resolved(
            actualWeight: set.actualWeight,
            actualLoadUnit: set.actualLoadUnit,
            targetLoadUnit: set.targetLoadUnit
        )

        switch normalizedActualLoad.unit {
        case .kg, .lb:
            guard let actualWeight = normalizedActualLoad.weight, actualWeight > 0 else {
                return nil
            }

            return .weighted(
                WeightedWorkingSetMetric(
                    setID: set.id,
                    sortOrder: set.sortOrder,
                    weight: actualWeight,
                    reps: actualReps,
                    unit: normalizedActualLoad.unit
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

    nonisolated static func bestSetWeightText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    nonisolated static func bestSetUnitText(_ unit: TemplateLoadUnit) -> String {
        switch unit {
        case .kg:
            return "kg"
        case .lb:
            return "lb"
        case .bodyweight:
            return "BW"
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
                displayText: "\(bestSetWeightText(bestWeightedMetric.weight)) \(bestSetUnitText(bestWeightedMetric.unit)) x \(bestWeightedMetric.reps)"
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

        let repsOnlySets = sets
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter { set in
                guard set.isCompleted, !set.isWarmup, let reps = set.actualReps, reps > 0 else {
                    return false
                }
                return (set.actualWeight ?? 0) <= 0
            }

        if let bestRepsOnlySet = repsOnlySets.max(by: { lhs, rhs in
            let lhsReps = lhs.actualReps ?? 0
            let rhsReps = rhs.actualReps ?? 0
            if lhsReps != rhsReps {
                return lhsReps < rhsReps
            }
            return lhs.sortOrder > rhs.sortOrder
        }), let reps = bestRepsOnlySet.actualReps {
            return BestSetPresentation(displayText: "\(reps) reps")
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
        WorkoutPerformanceMath.weightedVolumeInKilograms(
            weight: metric.weight,
            reps: metric.reps,
            unit: metric.unit
        )
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

nonisolated final class WorkoutMetricsService {
    static let currentSummaryMetricsVersion = WorkoutMetricsPolicy.summaryMetricsVersion

    private let modelContext: ModelContext
    private let calendar: Calendar
    private let repository: WorkoutSessionRepository
    private let historyProjectionRepository: HistoryProjectionRepository
    private var cachedGoal: Int?
    private var cachedMetricsSnapshot: MetricsSnapshotCache?
    private var cachedMetricsSnapshotRevision: HistoryRevision?

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.repository = WorkoutSessionRepository(modelContext: modelContext)
        self.historyProjectionRepository = HistoryProjectionRepository(modelContext: modelContext)
    }

    static func bestSetText(for sets: [WorkoutSessionSet], emptyText: String = "-", usesAddedWeight: Bool = false, usesAssistance: Bool = false) -> String {
        guard usesAddedWeight || usesAssistance else { return WorkoutMetricsPolicy.bestSetText(from: sets, emptyText: emptyText) }
        let performances = sets.compactMap { set -> (ExerciseSetPerformance, TemplateLoadUnit)? in
            guard set.isCompleted, !set.isWarmup, let reps = set.actualReps, reps > 0,
                  !usesAssistance || set.actualWeight != nil || set.actualLoadUnit == .bodyweight else { return nil }
            let load = WorkoutLoggedLoadNormalization.resolved(actualWeight: set.actualWeight,
                actualLoadUnit: set.actualLoadUnit, targetLoadUnit: set.targetLoadUnit)
            let kilograms = load.unit == .bodyweight ? 0 : WorkoutPerformanceMath.normalizedLoadInKilograms(load.weight ?? 0, unit: load.unit)
            return (.init(reps: reps, kilograms: kilograms), load.unit)
        }
        guard let best = performances.max(by: {
            $0.0.kilograms == $1.0.kilograms ? $0.0.reps < $1.0.reps : (usesAssistance ? $0.0.kilograms > $1.0.kilograms : $0.0.kilograms < $1.0.kilograms)
        }) else { return usesAssistance && sets.contains(where: { $0.isCompleted && !$0.isWarmup }) ? "Assistance not recorded" : emptyText }
        return best.0.label(unit: best.1, addedWeight: usesAddedWeight, assistance: usesAssistance)
    }

    func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        WorkoutMetricsPolicy.estimatedOneRepMax(weight: weight, reps: reps)
    }

    func bestEstimatedOneRepMax(
        for catalogExerciseUUID: String,
        before date: Date? = nil,
        excludingSessionID: UUID? = nil
    ) throws -> Double? {
        guard try !addedWeightExerciseIDs([catalogExerciseUUID]).contains(catalogExerciseUUID),
              try !assistanceExerciseIDs([catalogExerciseUUID]).contains(catalogExerciseUUID) else { return nil }
        let entries = try ExerciseHistoryRepository(context: modelContext).entries(for: catalogExerciseUUID)
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

        let sessionFacts = resolvedFacts(for: session)
        return try sessionPRAchievements(session: session, sessionFacts: sessionFacts)
    }

    func sessionSetPRAchievements(sessionID: UUID) throws -> [SessionSetPRAchievement] {
        guard let session = try session(id: sessionID) else { return [] }

        let sessionFacts = resolvedFacts(for: session)
        return try sessionSetPRAchievements(session: session, sessionFacts: sessionFacts)
    }

    private func sessionPRAchievements(
        session: WorkoutSession,
        sessionFacts: [CompletedSetFact]
    ) throws -> [SessionPRAchievement] {
        var achievements: [SessionPRAchievement] = []
        let exerciseFactsByCatalogUUID = Dictionary(
            grouping: sessionFacts.filter { !$0.isWarmup && $0.parentSetID == nil && $0.isWeightedMetric },
            by: \.catalogExerciseUUID
        )

        let addedWeightIDs = try addedWeightExerciseIDs(Set(exerciseFactsByCatalogUUID.keys))
        let assistanceIDs = try assistanceExerciseIDs(Set(exerciseFactsByCatalogUUID.keys))
        for catalogExerciseUUID in exerciseFactsByCatalogUUID.keys.sorted() where !addedWeightIDs.contains(catalogExerciseUUID) && !assistanceIDs.contains(catalogExerciseUUID) {
            var runningBest = try bestEstimatedOneRepMax(
                for: catalogExerciseUUID,
                before: session.startedAt,
                excludingSessionID: session.id
            ) ?? 0
            var bestFact: CompletedSetFact?

            let exerciseFacts = (exerciseFactsByCatalogUUID[catalogExerciseUUID] ?? [])
                .sorted { lhs, rhs in
                    if lhs.sessionExerciseID != rhs.sessionExerciseID {
                        return lhs.sessionExerciseID.uuidString < rhs.sessionExerciseID.uuidString
                    }
                    if lhs.setIndex != rhs.setIndex {
                        return lhs.setIndex < rhs.setIndex
                    }
                    return lhs.sessionSetID.uuidString < rhs.sessionSetID.uuidString
                }

            for fact in exerciseFacts {
                guard let comparisonOneRM = fact.estimatedOneRepMaxKg else { continue }
                guard comparisonOneRM > runningBest else { continue }

                runningBest = comparisonOneRM
                if let currentBest = bestFact {
                    if isBetterProjectedWeightedFact(fact, than: currentBest) {
                        bestFact = fact
                    }
                } else {
                    bestFact = fact
                }
            }

            if let bestFact, let weight = bestFact.weight {
                achievements.append(
                    SessionPRAchievement(
                        id: "\(session.id.uuidString.lowercased())_\(catalogExerciseUUID.lowercased())",
                        catalogExerciseUUID: catalogExerciseUUID,
                        exerciseName: bestFact.exerciseNameSnapshot,
                        estimatedOneRepMax: estimatedOneRepMax(weight: weight, reps: bestFact.reps),
                        weight: weight,
                        reps: bestFact.reps,
                        loadUnit: bestFact.loadUnit
                    )
                )
            }
        }

        return achievements
    }

    private func sessionSetPRAchievements(
        session: WorkoutSession,
        sessionFacts: [CompletedSetFact]
    ) throws -> [SessionSetPRAchievement] {
        var achievements: [SessionSetPRAchievement] = []
        let addedWeightIDs = try addedWeightExerciseIDs(Set(sessionFacts.map(\.catalogExerciseUUID)))
        let assistanceIDs = try assistanceExerciseIDs(Set(sessionFacts.map(\.catalogExerciseUUID)))
        let exerciseIDs = Set(sessionFacts.map(\.sessionExerciseID))
        let exercises = try repository.sessionExercises(
            sessionID: session.id,
            exerciseIDs: exerciseIDs
        )
        let exerciseMetadataByID = Dictionary(
            uniqueKeysWithValues: exercises.map { ($0.id, $0) }
        )
        let factsByExerciseID = Dictionary(grouping: sessionFacts, by: \.sessionExerciseID)
        var priorPeaksByExerciseUUID = try priorSetMetricPeaksByExerciseUUID(
            for: Set(sessionFacts.map(\.catalogExerciseUUID)),
            before: session.startedAt,
            excludingSessionID: session.id
        )

        let orderedExerciseIDs = exerciseIDs.sorted { lhs, rhs in
            let lhsSortOrder = exerciseMetadataByID[lhs]?.sortOrder ?? Int.max
            let rhsSortOrder = exerciseMetadataByID[rhs]?.sortOrder ?? Int.max
            if lhsSortOrder != rhsSortOrder {
                return lhsSortOrder < rhsSortOrder
            }
            return lhs.uuidString < rhs.uuidString
        }

        for exerciseID in orderedExerciseIDs {
            guard let firstFact = factsByExerciseID[exerciseID]?.first else { continue }

            let metadata = exerciseMetadataByID[exerciseID]
            let catalogExerciseUUID = metadata?.catalogExerciseUUID ?? firstFact.catalogExerciseUUID
            let exerciseName = metadata?.exerciseNameSnapshot ?? firstFact.exerciseNameSnapshot
            var runningBest = priorPeaksByExerciseUUID[catalogExerciseUUID] ?? PriorSetMetricPeaks()

            let exerciseFacts = (factsByExerciseID[exerciseID] ?? [])
                .filter { !$0.isWarmup && $0.parentSetID == nil }
                .sorted { lhs, rhs in
                    if lhs.setIndex != rhs.setIndex {
                        return lhs.setIndex < rhs.setIndex
                    }
                    return lhs.sessionSetID.uuidString < rhs.sessionSetID.uuidString
                }

            for fact in exerciseFacts {
                var kinds: [WorkoutPersonalRecordKind] = []
                var estimatedOneRepMaxValue: Double?
                var weight: Double?
                var volume: Double?

                if assistanceIDs.contains(catalogExerciseUUID) {
                    guard let loggedWeight = fact.weight else { continue }
                    kinds = runningBest.assistance.consume(kilograms: fact.normalizedWeightKg ?? 0, reps: fact.reps)
                    weight = loggedWeight
                } else if fact.isWeightedMetric,
                   let loggedWeight = fact.weight,
                   let comparisonOneRepMax = fact.estimatedOneRepMaxKg,
                   let normalizedWeight = fact.normalizedWeightKg,
                   let normalizedVolume = fact.volumeKg
                {
                    let oneRepMax = estimatedOneRepMax(weight: loggedWeight, reps: fact.reps)

                    if !addedWeightIDs.contains(catalogExerciseUUID), comparisonOneRepMax > runningBest.strength {
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

                    estimatedOneRepMaxValue = addedWeightIDs.contains(catalogExerciseUUID) ? nil : oneRepMax
                    weight = loggedWeight
                    volume = normalizedVolume
                }

                if !assistanceIDs.contains(catalogExerciseUUID), fact.reps > runningBest.reps {
                    runningBest.reps = fact.reps
                    kinds.append(.reps)
                }

                guard !kinds.isEmpty else { continue }

                achievements.append(
                    SessionSetPRAchievement(
                        id: "\(session.id.uuidString.lowercased())_\(fact.sessionSetID.uuidString.lowercased())",
                        sessionExerciseID: exerciseID,
                        setID: fact.sessionSetID,
                        catalogExerciseUUID: catalogExerciseUUID,
                        exerciseName: exerciseName,
                        kinds: kinds.sorted(),
                        estimatedOneRepMax: estimatedOneRepMaxValue,
                        weight: weight,
                        reps: fact.reps,
                        volume: volume,
                        loadUnit: fact.loadUnit,
                        usesAddedWeight: addedWeightIDs.contains(catalogExerciseUUID),
                        usesAssistance: assistanceIDs.contains(catalogExerciseUUID)
                    )
                )
            }

            priorPeaksByExerciseUUID[catalogExerciseUUID] = runningBest
        }

        return achievements
    }

    func totalVolume(sessionID: UUID) throws -> Double {
        guard let session = try session(id: sessionID) else { return 0 }
        return try totalWeightedVolume(from: resolvedFacts(for: session))
    }

    func sessionSummary(sessionID: UUID) throws -> WorkoutSessionSummaryMetrics {
        guard let session = try session(id: sessionID) else {
            return WorkoutSessionSummaryMetrics(totalVolume: 0, prHitsCount: 0)
        }
        let sessionFacts = resolvedFacts(for: session)

        return WorkoutSessionSummaryMetrics(
            totalVolume: try totalWeightedVolume(from: sessionFacts),
            prHitsCount: try sessionSetPRAchievements(
                session: session,
                sessionFacts: sessionFacts
            ).count
        )
    }

    func sessionSummary(
        session: WorkoutSession,
        projectedFacts: [CompletedSetFactDraft]
    ) throws -> WorkoutSessionSummaryMetrics {
        let sessionFacts = projectedFacts.map { $0.makeModel() }
        return WorkoutSessionSummaryMetrics(
            totalVolume: try totalWeightedVolume(from: sessionFacts),
            prHitsCount: try sessionSetPRAchievements(
                session: session,
                sessionFacts: sessionFacts
            ).count
        )
    }

    func personalRecords(limit: Int = 8) throws -> [WorkoutPRRecord] {
        try profileDashboardSnapshot(prLimit: limit, weeks: 1).personalRecords
    }

    func weeklyWorkoutProgress(weeks: Int = 8) throws -> [WeeklyWorkoutProgressPoint] {
        try profileDashboardSnapshot(prLimit: 1, weeks: weeks).weeklyProgress
    }

    func exerciseHistoryOptions(metric: ProfileExerciseTrendMetric? = nil) throws -> [ExerciseHistoryOption] {
        let exerciseHistoryByUUID = try metricsSnapshot().exerciseHistoryByUUID
        let addedWeightIDs = try addedWeightExerciseIDs(Set(exerciseHistoryByUUID.keys))
        let assistanceIDs = try assistanceExerciseIDs(Set(exerciseHistoryByUUID.keys))
        var latestByExercise: [String: ExerciseHistoryOption] = [:]

        for (catalogExerciseUUID, entries) in exerciseHistoryByUUID {
            guard let latestEntry = entries.first(where: { $0.maxReps != nil }) else {
                continue
            }

            let availableMetrics = Set(ProfileExerciseTrendMetric.allCases.filter { metric in
                !(addedWeightIDs.contains(catalogExerciseUUID) && metric == .oneRepMax)
                    && !(assistanceIDs.contains(catalogExerciseUUID) && metric != .maxReps)
                    && entries.contains { assistanceIDs.contains(catalogExerciseUUID)
                        ? $0.loadContext?.bestAssistedRepsSet != nil : $0.supportsExerciseTrendMetric(metric) }
            })
            guard !availableMetrics.isEmpty else { continue }
            latestByExercise[catalogExerciseUUID] = ExerciseHistoryOption(
                catalogExerciseUUID: catalogExerciseUUID,
                exerciseName: latestEntry.exerciseName,
                lastPerformedAt: latestEntry.completedAt,
                trendMetric: metric.flatMap { availableMetrics.contains($0) ? $0 : nil } ?? .maxReps,
                availableTrendMetrics: availableMetrics
            )
        }

        return latestByExercise.values.sorted { lhs, rhs in
            if lhs.lastPerformedAt != rhs.lastPerformedAt {
                return lhs.lastPerformedAt > rhs.lastPerformedAt
            }
            return lhs.exerciseName.localizedStandardCompare(rhs.exerciseName) == .orderedAscending
        }
    }

    func exerciseOneRepMaxTrend(for catalogExerciseUUID: String, preferredExerciseName: String? = nil, limit: Int = 8) throws -> ExerciseMetricSeries {
        try exerciseMetricTrend(for: catalogExerciseUUID, metric: .oneRepMax, preferredExerciseName: preferredExerciseName, limit: limit)
    }

    func exerciseVolumeTrend(for catalogExerciseUUID: String, preferredExerciseName: String? = nil, limit: Int = 8) throws -> ExerciseMetricSeries {
        try exerciseMetricTrend(for: catalogExerciseUUID, metric: .volume, preferredExerciseName: preferredExerciseName, limit: limit)
    }

    func exerciseMaxWeightTrend(for catalogExerciseUUID: String, preferredExerciseName: String? = nil, limit: Int = 8) throws -> ExerciseMetricSeries {
        try exerciseMetricTrend(for: catalogExerciseUUID, metric: .maxWeight, preferredExerciseName: preferredExerciseName, limit: limit)
    }

    func exerciseMaxRepsTrend(for catalogExerciseUUID: String, preferredExerciseName: String? = nil, limit: Int = 8) throws -> ExerciseMetricSeries {
        try exerciseMetricTrend(for: catalogExerciseUUID, metric: .maxReps, preferredExerciseName: preferredExerciseName, limit: limit)
    }

    func exerciseMetricTrend(for catalogExerciseUUID: String, metric: ProfileExerciseTrendMetric,
                             preferredExerciseName: String? = nil, limit: Int = 8) throws -> ExerciseMetricSeries {
        let request = ExerciseTrendRequest(catalogExerciseUUID: catalogExerciseUUID, metric: metric)
        let result = try exerciseMetricTrends(requests: [request], limit: limit)[request]!
        return result.withPreferredName(preferredExerciseName)
    }

    func exerciseMetricTrends(requests: Set<ExerciseTrendRequest>, limit: Int = 8) throws -> [ExerciseTrendRequest: ExerciseMetricSeries] {
        let addedWeightIDs = try addedWeightExerciseIDs(Set(requests.map(\.catalogExerciseUUID)))
        let assistanceIDs = try assistanceExerciseIDs(Set(requests.map(\.catalogExerciseUUID)))
        let histories = try ExerciseHistoryRepository(context: modelContext).trendEntries(requests: requests, limit: limit, assistanceIDs: assistanceIDs)
        return Dictionary(uniqueKeysWithValues: requests.map { request in
            let entries = histories[request, default: []]
            let addedWeight = addedWeightIDs.contains(request.catalogExerciseUUID)
            let assistance = assistanceIDs.contains(request.catalogExerciseUUID)
            let points = entries.compactMap { entry -> CollectedExerciseMetricPoint? in
                guard !(addedWeight && request.metric == .oneRepMax), !(assistance && request.metric != .maxReps) else { return nil }
                let value: Double?
                let unit: TemplateLoadUnit
                switch request.metric {
                case .oneRepMax: value = entry.weightedOneRepMaxInKilograms; unit = entry.weightedOneRepMaxUnit
                case .volume: value = entry.totalWeightedVolumeInKilograms; unit = entry.weightedVolumeUnit
                case .maxWeight: value = entry.maxWeightInKilograms; unit = entry.maxWeightUnit
                case .maxReps: value = entry.maxReps.map(Double.init); unit = .bodyweight
                }
                let metric: ExerciseProgressMetric = switch request.metric {
                case .oneRepMax: .estimatedOneRepMax
                case .maxWeight: .heaviestWeight
                case .maxReps: .bestSetReps
                case .volume: .sessionVolume
                }
                let performance = assistance ? entry.loadContext?.bestAssistedRepsSet : entry.loadContext?.set(for: metric)
                let contextUnit = request.metric == .maxReps ? entry.maxWeightUnit : unit
                let context = performance?.label(unit: contextUnit, addedWeight: addedWeight, assistance: assistance)
                    ?? (assistance ? "Assistance not recorded" : entry.loadContext?.rangeLabel(unit: contextUnit, addedWeight: addedWeight))
                return (assistance ? performance.map { Double($0.reps) } : value).map { CollectedExerciseMetricPoint(completedAt: entry.completedAt, normalizedValue: $0,
                    sourceUnit: unit, context: context, performance: performance) }
            }
            return (request, buildExerciseMetricSeries(catalogExerciseUUID: request.catalogExerciseUUID,
                exerciseName: entries.first?.exerciseName ?? "Exercise", points: points, usesAddedWeight: addedWeight, usesAssistance: assistance))
        })
    }

    func exerciseDetailStats(
        for catalogExerciseUUID: String,
        preferredExerciseName: String? = nil,
        limit: Int = 8
    ) throws -> ExerciseDetailStatsSnapshot? {
        let normalizedUUID = catalogExerciseUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUUID.isEmpty else {
            return nil
        }

        let snapshot = try metricsSnapshot()
        guard let frequency = snapshot.exerciseFrequencyByUUID[normalizedUUID] else {
            return nil
        }

        let weightedBest = snapshot.bestPRByExercise[normalizedUUID].map { record in
            ExerciseDetailBestPerformance(
                kind: .weighted,
                reps: record.reps,
                weight: record.weight,
                loadUnit: record.loadUnit,
                estimatedOneRepMax: record.usesAddedWeight ? nil : record.estimatedOneRepMax,
                achievedAt: record.achievedAt
            )
        }
        let bodyweightBest = snapshot.bestBodyweightByExercise[normalizedUUID].map { record in
            ExerciseDetailBestPerformance(
                kind: .bodyweight,
                reps: record.reps,
                weight: nil,
                loadUnit: .bodyweight,
                estimatedOneRepMax: nil,
                achievedAt: record.achievedAt
            )
        }
        let resolvedName = preferredExerciseName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
            ?? weightedBest.map { _ in frequency.exerciseName }
            ?? bodyweightBest.map { _ in frequency.exerciseName }
            ?? frequency.exerciseName
        let oneRepMaxTrend = try weightedTrendSeriesIfAvailable(
            for: normalizedUUID,
            preferredExerciseName: resolvedName,
            limit: limit,
            kind: .oneRepMax
        )
        let volumeTrend = try weightedTrendSeriesIfAvailable(
            for: normalizedUUID,
            preferredExerciseName: resolvedName,
            limit: limit,
            kind: .volume
        )

        return ExerciseDetailStatsSnapshot(
            catalogExerciseUUID: normalizedUUID,
            exerciseName: resolvedName,
            sessionCount: frequency.sessionCount,
            lastPerformedAt: frequency.lastPerformedAt,
            bestPerformance: weightedBest ?? bodyweightBest,
            oneRepMaxTrend: oneRepMaxTrend,
            volumeTrend: volumeTrend
        )
    }

    private func assistanceExerciseIDs(_ ids: Set<String>) throws -> Set<String> {
        try ExerciseLoadContextRepository.assistanceIDs(for: ids, in: modelContext)
    }

    private func addedWeightExerciseIDs(_ ids: Set<String>) throws -> Set<String> {
        try ExerciseLoadContextRepository.addedWeightIDs(for: ids, in: modelContext)
    }

    func exerciseProgressDataset(
        for catalogExerciseUUID: String,
        preferredExerciseName: String? = nil
    ) throws -> ExerciseProgressDataset? {
        let normalizedUUID = catalogExerciseUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUUID.isEmpty else { return nil }

        let history = try ExerciseHistoryRepository(context: modelContext).entries(for: normalizedUUID)
        guard !history.isEmpty else {
            return nil
        }

        let resolvedName = preferredExerciseName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
            ?? history.first?.exerciseName
            ?? normalizedUUID
        let preferredUnit = history.compactMap { entry -> TemplateLoadUnit? in
            if entry.weightedOneRepMaxInKilograms != nil { return entry.weightedOneRepMaxUnit }
            if entry.maxWeightInKilograms != nil { return entry.maxWeightUnit }
            if entry.totalWeightedVolumeInKilograms != nil { return entry.weightedVolumeUnit }
            return nil
        }.first ?? (history.contains { $0.maxReps != nil } ? .bodyweight : .kg)

        return ExerciseProgressDataset(
            exerciseUUID: normalizedUUID,
            exerciseName: resolvedName,
            sessions: history.map { entry in
                ExerciseProgressSession(
                    sessionID: entry.sessionID,
                    completedAt: entry.completedAt,
                    estimatedOneRepMaxKilograms: entry.weightedOneRepMaxInKilograms,
                    heaviestWeightKilograms: entry.maxWeightInKilograms,
                    sessionVolumeKilograms: entry.totalWeightedVolumeInKilograms,
                    bestSetReps: entry.maxReps,
                    totalReps: entry.totalReps,
                    completedSetCount: entry.completedSetCount,
                    displayUnit: entry.weightedOneRepMaxInKilograms != nil
                        ? entry.weightedOneRepMaxUnit
                        : entry.maxWeightInKilograms != nil
                            ? entry.maxWeightUnit
                            : entry.totalWeightedVolumeInKilograms != nil
                                ? entry.weightedVolumeUnit
                                : .bodyweight,
                    durationSeconds: entry.durationSeconds,
                    distanceMeters: entry.distanceMeters,
                    loadContext: entry.loadContext
                )
            },
            preferredLoadUnit: preferredUnit,
            usesAddedWeight: try addedWeightExerciseIDs([normalizedUUID]).contains(normalizedUUID),
            usesAssistance: try assistanceExerciseIDs([normalizedUUID]).contains(normalizedUUID)
        )
    }

    func profileDashboardSnapshot(prLimit: Int = 8, weeks: Int = 8, enabledWidgets: Set<ProfileWidgetKind>? = nil) throws -> ProfileDashboardSnapshot {
        let safePRLimit = max(1, prLimit)
        let safeWeeks = max(1, weeks)
        let profileGoal = try currentGoal()
        let request = DashboardMetricsRequest.profile(widgets: enabledWidgets ?? Set(ProfileWidgetKind.allCases), calendar: calendar)
        let snapshot = try HistoryAnalyticsCache.shared.cachedMetricsSnapshot(for: modelContext.container, request: request) {
            try DashboardMetricsRepository(context: modelContext, calendar: calendar).snapshot(request: request)
        }
        let nowWeek = weekStart(for: Date())
        var weeksToInclude: [Date] = []
        weeksToInclude.reserveCapacity(safeWeeks)
        for offset in (0..<safeWeeks).reversed() {
            if let week = calendar.date(byAdding: .weekOfYear, value: -offset, to: nowWeek) {
                weeksToInclude.append(week)
            }
        }
        let addedWeightIDs = try addedWeightExerciseIDs(Set(snapshot.bestPRByExercise.keys))
        let personalRecords = snapshot.bestPRByExercise.values
            .sorted { lhs, rhs in
                let lhsValue = normalizedLoadForComparison(lhs.estimatedOneRepMax ?? lhs.weight, unit: lhs.loadUnit)
                let rhsValue = normalizedLoadForComparison(rhs.estimatedOneRepMax ?? rhs.weight, unit: rhs.loadUnit)
                if lhsValue != rhsValue {
                    return lhsValue > rhsValue
                }
                return lhs.exerciseName.localizedStandardCompare(rhs.exerciseName) == .orderedAscending
            }
            .prefix(safePRLimit)
            .map { record in
                var record = record
                record.usesAddedWeight = addedWeightIDs.contains(record.catalogExerciseUUID)
                return record
            }
        let weeklyProgress = weeksToInclude.map { week in
            WeeklyWorkoutProgressPoint(
                id: week.formatted(date: .numeric, time: .omitted),
                weekStart: week,
                completedWorkouts: snapshot.countsByWeek[week, default: 0],
                goal: profileGoal
            )
        }
        let overviewStats = buildOverviewStats(
            completedWorkoutCount: snapshot.completedSessionCount,
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
        let weeklyMuscleHeatmap = buildWeeklyMuscleHeatmap(
            weekStart: nowWeek,
            scores: snapshot.muscleScoresByWeek[nowWeek, default: [:]]
        )

        return ProfileDashboardSnapshot(
            personalRecords: personalRecords,
            weeklyProgress: weeklyProgress,
            weeklyMuscleHeatmap: weeklyMuscleHeatmap,
            weeklyGoal: profileGoal,
            overviewStats: overviewStats,
            topExercises: topExercises,
            activityDays: activityDays,
            bodyweightPersonalRecords: Array(snapshot.bestBodyweightByExercise.values.filter {
                // Each exercise gets one record; prefer its weighted 1RM when available.
                snapshot.bestPRByExercise[$0.catalogExerciseUUID] == nil
            }.sorted {
                if $0.reps != $1.reps { return $0.reps > $1.reps }
                return $0.exerciseName.localizedStandardCompare($1.exerciseName) == .orderedAscending
            }.prefix(max(0, safePRLimit - personalRecords.count)))
        )
    }

    private func visibleCompletedSessionIDs() throws -> Set<UUID> {
        Set(try repository.completedSessions().map(\.id))
    }

    private func metricsSnapshot() throws -> MetricsSnapshotCache {
        let revisionAtStart = HistoryAnalyticsCache.shared.token(for: modelContext.container)
        if let cachedMetricsSnapshot, cachedMetricsSnapshotRevision == revisionAtStart {
            return cachedMetricsSnapshot
        }

        let snapshot = try HistoryAnalyticsCache.shared.cachedMetricsSnapshot(
            for: modelContext.container, request: .full(calendar: calendar)
        ) {
            try WGJPerformance.measure("metrics.snapshot") {
                try buildMetricsSnapshot()
            }
        }

        let revisionAtEnd = HistoryAnalyticsCache.shared.token(for: modelContext.container)
        if revisionAtEnd == revisionAtStart {
            cachedMetricsSnapshot = snapshot
            cachedMetricsSnapshotRevision = revisionAtEnd
        } else {
            cachedMetricsSnapshot = nil
            cachedMetricsSnapshotRevision = nil
        }
        return snapshot
    }

    private func buildMetricsSnapshot() throws -> MetricsSnapshotCache {
        try DashboardMetricsRepository(context: modelContext, calendar: calendar).snapshot()
    }

    private func resolvedFacts(
        for session: WorkoutSession,
        existingFacts: [CompletedSetFact]? = nil,
        source: HistoryProjectionSnapshotBuilder.Source? = nil
    ) -> [CompletedSetFact] {
        let source = source ?? (try? HistoryProjectionSnapshotBuilder.loadSource(for: session, repository: repository))
        let persistedFacts = existingFacts ?? (try? historyProjectionRepository.facts(forSessionID: session.id)) ?? []
        guard !persistedFacts.isEmpty else {
            return source?.projectedFacts().map { $0.makeModel() } ?? projectedFacts(from: session)
        }

        let hasStaleProjectionVersion = session.summaryMetricsVersion < Self.currentSummaryMetricsVersion
        let sourceUpdatedAt = source?.updatedAt ?? HistoryProjectionSnapshotBuilder.sourceSessionUpdatedAt(for: session)
        let completedAt = session.endedAt ?? session.startedAt
        let hasStaleProjectionSource = persistedFacts.contains { fact in
            fact.sourceSessionUpdatedAt != sourceUpdatedAt || fact.completedAt != completedAt
        }
        // Older projections omitted reps-only sets logged with kg/lb. Recover
        // these from local source data without saving during a history read.
        let persistedSetIDs = Set(persistedFacts.map(\.sessionSetID))
        let hasMissingRepsOnlySets = source?.exercises.contains { row in
            row.sets.contains { set in
                set.isCompleted && (set.actualReps ?? 0) > 0
                    && (set.actualWeight == nil || set.actualWeight == 0)
                    && !persistedSetIDs.contains(set.id)
            }
        } ?? false
        guard hasStaleProjectionVersion || hasStaleProjectionSource || hasMissingRepsOnlySets else {
            return persistedFacts
        }

        return source?.projectedFacts().map { $0.makeModel() } ?? projectedFacts(from: session)
    }

    private func projectedFacts(from session: WorkoutSession) -> [CompletedSetFact] {
        ((try? HistoryProjectionSnapshotBuilder.projectedFacts(
            from: session,
            repository: repository
        )) ?? HistoryProjectionSnapshotBuilder.projectedFacts(from: session))
            .map { $0.makeModel() }
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

    private func totalWeightedVolume(from facts: [CompletedSetFact]) throws -> Double {
        let assistanceIDs = try assistanceExerciseIDs(Set(facts.map(\.catalogExerciseUUID)))
        return facts.reduce(into: 0.0) { total, fact in
            guard !fact.isWarmup, !assistanceIDs.contains(fact.catalogExerciseUUID), let volumeKg = fact.volumeKg else { return }
            total += volumeKg
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

    /// PR comparisons must also work while older derived history is awaiting backfill.
    /// Rebuild only dirty sessions in memory; a read never commits source data.
    private func resolvedHistoryFacts(for exerciseIDs: Set<String>) throws -> [CompletedSetFact] {
        let persisted = try historyProjectionRepository.facts(forExercises: exerciseIDs)
        let dirty = try ExerciseHistoryRepository(context: modelContext).dirtySessions()
        guard !dirty.isEmpty else { return persisted }
        let dirtyIDs = Set(dirty.map(\.id))
        let allExercises = try repository.sessionExercises(sessionIDs: dirtyIDs)
        let canonicalSessionIDs = Set(allExercises.map(\.sessionID))
        let requested = allExercises.filter { exerciseIDs.contains($0.catalogExerciseUUID) }
        let sets = try repository.sessionSets(sessionExerciseIDs: Set(requested.map(\.id)))
        let stages = try repository.sessionDropStages(setIDs: Set(sets.map(\.id)))
        let bySession = Dictionary(grouping: requested, by: \.sessionID)
        let byExercise = Dictionary(grouping: sets, by: \.sessionExerciseID)
        let bySet = Dictionary(grouping: stages, by: \.sessionSetID)
        var result = persisted.filter { !canonicalSessionIDs.contains($0.sessionID) }
        for session in dirty where canonicalSessionIDs.contains(session.id) {
            let source = HistoryProjectionSnapshotBuilder.Source(session: session,
                exercises: bySession[session.id, default: []].map { ($0, byExercise[$0.id, default: []]) },
                dropStagesBySetID: bySet)
            result.append(contentsOf: source.projectedFacts().map { $0.makeModel() })
        }
        return result
    }

    private func priorSetMetricPeaksByExerciseUUID(
        for catalogExerciseUUIDs: Set<String>,
        before date: Date? = nil,
        excludingSessionID: UUID? = nil
    ) throws -> [String: PriorSetMetricPeaks] {
        guard !catalogExerciseUUIDs.isEmpty else { return [:] }

        let facts = try resolvedHistoryFacts(for: catalogExerciseUUIDs)
        let visibleSessionIDs = try visibleCompletedSessionIDs()
        var peaksByExerciseUUID: [String: PriorSetMetricPeaks] = [:]

        for fact in facts where !fact.isWarmup && fact.parentSetID == nil && catalogExerciseUUIDs.contains(fact.catalogExerciseUUID) {
            guard visibleSessionIDs.contains(fact.sessionID) else { continue }
            if let excludingSessionID, fact.sessionID == excludingSessionID {
                continue
            }

            if let date, fact.completedAt >= date {
                continue
            }

            var peaks = peaksByExerciseUUID[fact.catalogExerciseUUID] ?? PriorSetMetricPeaks()
            if fact.weight != nil { _ = peaks.assistance.consume(kilograms: fact.normalizedWeightKg ?? 0, reps: fact.reps) }
            if fact.isWeightedMetric,
               let weightedOneRepMax = fact.estimatedOneRepMaxKg,
               let normalizedWeight = fact.normalizedWeightKg,
               let normalizedVolume = fact.volumeKg
            {
                peaks.strength = max(peaks.strength, weightedOneRepMax)
                peaks.weight = max(peaks.weight, normalizedWeight)
                peaks.volume = max(peaks.volume, normalizedVolume)
            }

            peaks.reps = max(peaks.reps, fact.reps)
            peaksByExerciseUUID[fact.catalogExerciseUUID] = peaks
        }

        return peaksByExerciseUUID
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

    private func buildWeeklyMuscleHeatmap(
        weekStart: Date,
        scores: [ExerciseBodyMapRegion: Double]
    ) -> ProfileWeeklyMuscleHeatmapSnapshot {
        let heatmap = WorkoutMuscleHeatmapBuilder.snapshot(scores: scores)

        return ProfileWeeklyMuscleHeatmapSnapshot(
            weekStart: weekStart,
            entries: heatmap.entries,
            topRegionNames: heatmap.topRegionNames
        )
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
        points: [CollectedExerciseMetricPoint],
        usesAddedWeight: Bool = false, usesAssistance: Bool = false
    ) -> ExerciseMetricSeries {
        let displayUnit = points.first?.sourceUnit ?? .kg
        let orderedPoints = points.reversed().map { point in
            ExerciseMetricPoint(
                id: "\(catalogExerciseUUID.lowercased())_\(point.completedAt.timeIntervalSinceReferenceDate)",
                completedAt: point.completedAt,
                value: displayValue(point.normalizedValue, unit: displayUnit),
                context: point.context, performance: point.performance
            )
        }

        return ExerciseMetricSeries(
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseName: exerciseName,
            loadUnit: displayUnit,
            points: orderedPoints,
            usesAddedWeight: usesAddedWeight, usesAssistance: usesAssistance
        )
    }

    private func isBetterPRRecord(_ candidate: WorkoutPRRecord, than existing: WorkoutPRRecord) -> Bool {
        let candidateValue = normalizedLoadForComparison(candidate.estimatedOneRepMax ?? candidate.weight, unit: candidate.loadUnit)
        let existingValue = normalizedLoadForComparison(existing.estimatedOneRepMax ?? existing.weight, unit: existing.loadUnit)

        if candidateValue != existingValue {
            return candidateValue > existingValue
        }

        return candidate.achievedAt > existing.achievedAt
    }

    private func isBetterBodyweightRecord(
        _ candidate: BodyweightExerciseBestRecord,
        than existing: BodyweightExerciseBestRecord
    ) -> Bool {
        if candidate.reps != existing.reps {
            return candidate.reps > existing.reps
        }

        return candidate.achievedAt > existing.achievedAt
    }

    private enum WeightedTrendKind {
        case oneRepMax
        case volume
    }

    private func weightedTrendSeriesIfAvailable(
        for catalogExerciseUUID: String,
        preferredExerciseName: String,
        limit: Int,
        kind: WeightedTrendKind
    ) throws -> ExerciseMetricSeries? {
        let entries = try ExerciseHistoryRepository(context: modelContext).entries(for: catalogExerciseUUID)
        let hasPoints: Bool
        switch kind {
        case .oneRepMax:
            hasPoints = entries.contains(where: { $0.weightedOneRepMaxInKilograms != nil })
        case .volume:
            hasPoints = entries.contains(where: { $0.totalWeightedVolumeInKilograms != nil })
        }

        guard hasPoints else {
            return nil
        }

        switch kind {
        case .oneRepMax:
            return try exerciseOneRepMaxTrend(
                for: catalogExerciseUUID,
                preferredExerciseName: preferredExerciseName,
                limit: limit
            )
        case .volume:
            return try exerciseVolumeTrend(
                for: catalogExerciseUUID,
                preferredExerciseName: preferredExerciseName,
                limit: limit
            )
        }
    }

    private func isBetterProjectedWeightedFact(_ candidate: CompletedSetFact, than existing: CompletedSetFact) -> Bool {
        guard
            let candidateOneRepMax = candidate.estimatedOneRepMaxKg,
            let existingOneRepMax = existing.estimatedOneRepMaxKg
        else {
            return false
        }

        if candidateOneRepMax != existingOneRepMax {
            return candidateOneRepMax > existingOneRepMax
        }

        let candidateWeight = candidate.normalizedWeightKg ?? 0
        let existingWeight = existing.normalizedWeightKg ?? 0
        if candidateWeight != existingWeight {
            return candidateWeight > existingWeight
        }

        if candidate.reps != existing.reps {
            return candidate.reps > existing.reps
        }

        return candidate.setIndex < existing.setIndex
    }
}

nonisolated private struct CollectedExerciseMetricPoint {
    let completedAt: Date
    let normalizedValue: Double
    let sourceUnit: TemplateLoadUnit
    var context: String? = nil
    var performance: ExerciseSetPerformance? = nil
}

nonisolated private struct PriorSetMetricPeaks {
    var assistance = AssistanceRecordTracker()
    var strength: Double = 0
    var weight: Double = 0
    var reps: Int = 0
    var volume: Double = 0
}

nonisolated struct MetricsSnapshotCache: Sendable {
    let completedSessionCount: Int
    let bestPRByExercise: [String: WorkoutPRRecord]
    let bestBodyweightByExercise: [String: BodyweightExerciseBestRecord]
    let countsByWeek: [Date: Int]
    let countsByDay: [Date: Int]
    let muscleScoresByWeek: [Date: [ExerciseBodyMapRegion: Double]]
    let exerciseFrequencyByUUID: [String: CollectedExerciseFrequency]
    let exerciseHistoryByUUID: [String: [CompletedExerciseHistoryEntry]]
    let totalDurationSeconds: Int
    let totalPRHits: Int
    let firstWorkoutDate: Date?
}

nonisolated struct CompletedExerciseHistoryEntry: Codable, Sendable {
    let sessionID: UUID
    let completedAt: Date
    let exerciseName: String
    let comparisonOneRepMax: Double?
    let weightedOneRepMaxInKilograms: Double?
    let weightedOneRepMaxUnit: TemplateLoadUnit
    let totalWeightedVolumeInKilograms: Double?
    let weightedVolumeUnit: TemplateLoadUnit
    let maxWeightInKilograms: Double?
    let maxWeightUnit: TemplateLoadUnit
    let maxReps: Int?
    let totalReps: Int
    let completedSetCount: Int
    var durationSeconds: Double? = nil
    var distanceMeters: Double? = nil
    var bestWeight: Double? = nil
    var bestReps: Int? = nil
    var bestBodyweightReps: Int? = nil
    var muscleSummary: String? = nil
    var loadContext: ExerciseLoadContext? = nil
}

private extension CompletedExerciseHistoryEntry {
    nonisolated func supportsExerciseTrendMetric(_ metric: ProfileExerciseTrendMetric?) -> Bool {
        guard let metric else {
            return weightedOneRepMaxInKilograms != nil || totalWeightedVolumeInKilograms != nil
        }

        switch metric {
        case .oneRepMax:
            return weightedOneRepMaxInKilograms != nil
        case .maxWeight:
            return maxWeightInKilograms != nil
        case .volume:
            return totalWeightedVolumeInKilograms != nil
        case .maxReps:
            return maxReps != nil
        }
    }
}

nonisolated private struct WorkingExerciseHistoryEntry {
    var exerciseName: String
    var completedAt: Date
    var comparisonOneRepMax: Double?
    var weightedOneRepMaxInKilograms: Double?
    var weightedOneRepMaxUnit: TemplateLoadUnit?
    var totalWeightedVolumeInKilograms: Double = 0
    var weightedVolumeUnit: TemplateLoadUnit?
    var maxWeightInKilograms: Double?
    var maxWeightUnit: TemplateLoadUnit?
    var maxReps: Int?
    var totalReps = 0
    var completedSetCount = 0
    var hasWeightedMetrics = false
}

nonisolated struct CollectedExerciseFrequency: Sendable {
    let exerciseName: String
    let sessionCount: Int
    let lastPerformedAt: Date
}

nonisolated struct BodyweightExerciseBestRecord: Equatable, Sendable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let reps: Int
    let achievedAt: Date
}

nonisolated private struct SessionExerciseHistoryKey: Hashable, Sendable {
    let sessionID: UUID
    let catalogExerciseUUID: String
}

extension CompletedSetFact {
    var isWeightedMetric: Bool {
        weight != nil
            && normalizedWeightKg != nil
            && estimatedOneRepMaxKg != nil
            && volumeKg != nil
            && loadUnit != .bodyweight
    }
}

private extension String {
    nonisolated var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

extension ExerciseMetricSeries {
    nonisolated func withPreferredName(_ preferredName: String?) -> ExerciseMetricSeries {
        let trimmed = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return self }

        return ExerciseMetricSeries(
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseName: trimmed,
            loadUnit: loadUnit,
            points: points,
            usesAddedWeight: usesAddedWeight, usesAssistance: usesAssistance
        )
    }
}


extension ExerciseMetricSeries {
    func comparisonText(for metric: ProfileExerciseTrendMetric) -> String? {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        if metric == .maxReps {
            guard let firstSet = first.performance, let lastSet = last.performance else {
                return "Compare reps alongside the load used."
            }
            if !firstSet.hasSameLoad(as: lastSet) {
                return usesAssistance ? "Assistance changed. Compare reps at the same assistance on the same machine." : "Load changed. Fewer reps at a heavier load can still be progress."
            }
        }
        let delta = last.value - first.value
        let suffix = metric == .maxReps ? " at the same logged load" : ""
        guard abs(delta) >= 0.1 else {
            return "Unchanged across the last \(points.count) logged workouts\(suffix)."
        }
        let direction = delta > 0 ? "up" : "down"
        return "\(metric.formattedTrendValue(abs(delta), loadUnit: loadUnit)) \(direction) across your last \(points.count) logged workouts\(suffix)."
    }
}


extension SessionSetPRAchievement {
    nonisolated var performanceText: String {
        if usesAddedWeight || usesAssistance {
            let kilograms = loadUnit == .bodyweight ? 0 : WorkoutPerformanceMath.normalizedLoadInKilograms(weight ?? 0, unit: loadUnit)
            return ExerciseSetPerformance(reps: reps, kilograms: kilograms).label(unit: loadUnit, addedWeight: usesAddedWeight, assistance: usesAssistance)
        }
        if let weight, loadUnit != .bodyweight {
            return "\(WGJFormatters.decimalString(weight)) \(loadUnit.shortLabel) x \(reps)"
        }
        return "\(reps) reps"
    }

    nonisolated var detailText: String {
        let titles = kinds.map { kind in
            usesAddedWeight && kind == .weight ? "Added Weight" : kind.title
        }.joined(separator: " + ") + " PR"
        if !usesAddedWeight, kinds.contains(.strength), let estimatedOneRepMax {
            return "\(titles) · \(WGJFormatters.oneDecimalString(estimatedOneRepMax)) \(loadUnit.shortLabel) e1RM"
        }
        if kinds.contains(.volume), let volume {
            return "\(titles) · \(WGJFormatters.integerString(volume)) kg \(usesAddedWeight ? "added-weight volume" : "volume")"
        }
        return titles
    }
}
