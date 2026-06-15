import Foundation
import SwiftData

nonisolated final class WeeklyCoachInsightService {
    private static let baselineWindowCount = 6
    private static let maxSignalCount = 3

    private let calendar: Calendar
    private let historyProjectionRepository: HistoryProjectionRepository

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.calendar = calendar
        self.historyProjectionRepository = HistoryProjectionRepository(modelContext: modelContext)
    }

    func weeklyInsightSnapshot(asOf referenceDate: Date = .now) throws -> WeeklyCoachInsightSnapshot {
        let currentWeekStart = weekStart(for: referenceDate)
        let currentWeekEnd = calendar.date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart

        let facts = try projectedFacts()
        let buckets = try weeklyBuckets(
            from: facts,
            currentWeekStart: currentWeekStart,
            currentWeekEnd: currentWeekEnd
        )

        let baselineWeeks = recentBaselineWeeks(from: buckets.baselineBuckets)
        let baselineWeekCount = baselineWeeks.count
        let currentWorkoutCount = buckets.current.sessionIDs.count
        let currentVolume = buckets.current.totalVolume

        let fallbackSummary = fallbackSummary(
            baselineWeekCount: baselineWeekCount
        )
        let shouldFallback = !fallbackSummary.isEmpty
        let baselineAverageVolume = baselineWeeks.isEmpty ? 0 : baselineWeeks.map(\.totalVolume).reduce(0, +) / Double(baselineWeeks.count)
        let baselineAverageWorkouts = baselineWeeks.isEmpty ? 0 : baselineWeeks.map { Double($0.sessionIDs.count) }.reduce(0, +) / Double(baselineWeeks.count)
        let totalVolumeDelta = shouldFallback ? 0 : percentageChange(current: currentVolume, baseline: baselineAverageVolume)
        let consistencyDelta = shouldFallback ? 0 : consistencyChange(currentWorkoutCount: currentWorkoutCount, baselineAverageWorkouts: baselineAverageWorkouts)

        let signals = shouldFallback
            ? []
            : buildSignals(
                current: buckets.current,
                baselineWeeks: baselineWeeks
            )
        let topRisingSignals = Array(signals.filter { $0.deltaPercentage > 0 }.prefix(Self.maxSignalCount))
        let topWatchSignals = Array(
            signals
                .filter { $0.deltaPercentage < 0 }
                .sorted { lhs, rhs in
                    if lhs.deltaPercentage != rhs.deltaPercentage {
                        return lhs.deltaPercentage < rhs.deltaPercentage
                    }
                    if lhs.exerciseName != rhs.exerciseName {
                        return lhs.exerciseName.localizedStandardCompare(rhs.exerciseName) == .orderedAscending
                    }
                    return lhs.id < rhs.id
                }
                .prefix(Self.maxSignalCount)
        )
        let followUpKinds = followUpKinds(
            fallbackSummary: fallbackSummary,
            totalVolumeDelta: totalVolumeDelta,
            consistencyDelta: consistencyDelta,
            topRisingSignals: topRisingSignals,
            topWatchSignals: topWatchSignals
        )

        let snapshot = WeeklyCoachInsightSnapshot(
            weekStart: currentWeekStart,
            revisionKey: revisionKey(
                weekStart: currentWeekStart,
                baselineWeekCount: baselineWeekCount,
                completedWorkoutCount: currentWorkoutCount,
                totalVolumeDelta: totalVolumeDelta,
                consistencyDelta: consistencyDelta,
                topRisingSignals: topRisingSignals,
                topWatchSignals: topWatchSignals,
                fallbackSummary: fallbackSummary,
                followUpKinds: followUpKinds
            ),
            baselineWeekCount: baselineWeekCount,
            completedWorkoutCount: currentWorkoutCount,
            totalVolumeDelta: totalVolumeDelta,
            consistencyDelta: consistencyDelta,
            topRisingSignals: topRisingSignals,
            topWatchSignals: topWatchSignals,
            fallbackSummary: fallbackSummary,
            followUpKinds: followUpKinds
        )

        return snapshot
    }

    private func projectedFacts() throws -> [CompletedSetFact] {
        try historyProjectionRepository.allFacts()
    }

    private func weeklyBuckets(
        from facts: [CompletedSetFact],
        currentWeekStart: Date,
        currentWeekEnd: Date
    ) throws -> (current: WeeklyCoachWeekBucket, baselineBuckets: [Date: WeeklyCoachWeekBucket]) {
        var current = WeeklyCoachWeekBucket()
        var baselineBuckets: [Date: WeeklyCoachWeekBucket] = [:]

        for fact in facts where !fact.isWarmup {
            if fact.completedAt >= currentWeekStart && fact.completedAt < currentWeekEnd {
                current.ingest(fact)
                continue
            }

            guard fact.completedAt < currentWeekStart else { continue }
            let factWeekStart = weekStart(for: fact.completedAt)
            var bucket = baselineBuckets[factWeekStart] ?? WeeklyCoachWeekBucket()
            bucket.ingest(fact)
            baselineBuckets[factWeekStart] = bucket
        }

        return (current, baselineBuckets)
    }

    private func recentBaselineWeeks(from baselineBuckets: [Date: WeeklyCoachWeekBucket]) -> [WeeklyCoachWeekBucket] {
        baselineBuckets
            .sorted { lhs, rhs in
                if lhs.key != rhs.key {
                    return lhs.key > rhs.key
                }
                return lhs.value.sessionIDs.count > rhs.value.sessionIDs.count
            }
            .prefix(Self.baselineWindowCount)
            .map(\.value)
    }

    private func buildSignals(
        current: WeeklyCoachWeekBucket,
        baselineWeeks: [WeeklyCoachWeekBucket]
    ) -> [WeeklyCoachSignal] {
        let exerciseUUIDs = Set(current.effortByExercise.keys).union(
            baselineWeeks.flatMap { $0.effortByExercise.keys }
        )

        var signals: [WeeklyCoachSignal] = []
        signals.reserveCapacity(exerciseUUIDs.count)

        for catalogExerciseUUID in exerciseUUIDs.sorted() {
            let currentEffort = current.effortByExercise[catalogExerciseUUID, default: 0]
            let baselineEffort = baselineWeeks
                .map { $0.effortByExercise[catalogExerciseUUID, default: 0] }
                .reduce(0, +) / Double(Self.baselineWindowCount)

            let deltaPercentage = percentageChange(current: currentEffort, baseline: baselineEffort)
            guard deltaPercentage != 0 else { continue }

            let exerciseName = current.exerciseName(for: catalogExerciseUUID)
                ?? latestExerciseName(for: catalogExerciseUUID, in: baselineWeeks)
                ?? "Exercise"

            let direction = deltaPercentage > 0 ? "up" : "down"
            let summary = "\(exerciseName) is \(direction) \(WGJFormatters.oneDecimalString(abs(deltaPercentage)))% vs the six-week baseline."

            signals.append(
                WeeklyCoachSignal(
                    id: catalogExerciseUUID,
                    catalogExerciseUUID: catalogExerciseUUID,
                    exerciseName: exerciseName,
                    deltaPercentage: deltaPercentage,
                    summary: summary
                )
            )
        }

        return signals.sorted { lhs, rhs in
            if lhs.deltaPercentage != rhs.deltaPercentage {
                return lhs.deltaPercentage > rhs.deltaPercentage
            }
            if lhs.exerciseName != rhs.exerciseName {
                return lhs.exerciseName.localizedStandardCompare(rhs.exerciseName) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    private func latestExerciseName(for catalogExerciseUUID: String, in buckets: [WeeklyCoachWeekBucket]) -> String? {
        var latest: (date: Date, name: String)?

        for bucket in buckets {
            guard let name = bucket.exerciseName(for: catalogExerciseUUID),
                  let completedAt = bucket.exerciseCompletionDate(for: catalogExerciseUUID)
            else { continue }

            if let currentLatest = latest {
                if completedAt > currentLatest.date {
                    latest = (completedAt, name)
                }
            } else {
                latest = (completedAt, name)
            }
        }

        return latest?.name
    }

    private func fallbackSummary(
        baselineWeekCount: Int
    ) -> String {
        guard baselineWeekCount == Self.baselineWindowCount else {
            return "Not enough recent training history to build a stable weekly baseline."
        }
        return ""
    }

    private func followUpKinds(
        fallbackSummary: String,
        totalVolumeDelta: Double,
        consistencyDelta: Int,
        topRisingSignals: [WeeklyCoachSignal],
        topWatchSignals: [WeeklyCoachSignal]
    ) -> [CoachFollowUpKind] {
        guard fallbackSummary.isEmpty else {
            return [.whatChanged]
        }

        var kinds: [CoachFollowUpKind] = [.whatChanged]

        if totalVolumeDelta > 0 || !topRisingSignals.isEmpty {
            kinds.insert(.whatImproved, at: 0)
        }

        if totalVolumeDelta < 0 || consistencyDelta < 0 || !topWatchSignals.isEmpty {
            if !kinds.contains(.whyFlat) {
                kinds.append(.whyFlat)
            }
        }

        return kinds
    }

    private func revisionKey(
        weekStart: Date,
        baselineWeekCount: Int,
        completedWorkoutCount: Int,
        totalVolumeDelta: Double,
        consistencyDelta: Int,
        topRisingSignals: [WeeklyCoachSignal],
        topWatchSignals: [WeeklyCoachSignal],
        fallbackSummary: String,
        followUpKinds: [CoachFollowUpKind]
    ) -> String {
        let payload = WeeklyCoachInsightRevisionPayload(
            weekStartReferenceDate: weekStart.timeIntervalSinceReferenceDate,
            baselineWeekCount: baselineWeekCount,
            completedWorkoutCount: completedWorkoutCount,
            totalVolumeDelta: totalVolumeDelta,
            consistencyDelta: consistencyDelta,
            risingSignals: topRisingSignals.map { WeeklyCoachInsightRevisionSignalPayload(signal: $0) },
            watchSignals: topWatchSignals.map { WeeklyCoachInsightRevisionSignalPayload(signal: $0) },
            fallbackSummary: fallbackSummary,
            followUpKinds: followUpKinds.map(\.rawValue)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970

        guard let data = try? encoder.encode(payload),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return UUID().uuidString
        }

        return encoded
    }

    private func percentageChange(current: Double, baseline: Double) -> Double {
        guard baseline > 0 else {
            return current > 0 ? 100 : 0
        }

        return roundedPercentage(((current - baseline) / baseline) * 100)
    }

    private func consistencyChange(currentWorkoutCount: Int, baselineAverageWorkouts: Double) -> Int {
        Int((Double(currentWorkoutCount) - baselineAverageWorkouts).rounded())
    }

    private func roundedPercentage(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private func weekStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }
}

nonisolated struct WeeklyCoachInsightRevisionPayload: Codable, Equatable, Sendable {
    let weekStartReferenceDate: Double
    let baselineWeekCount: Int
    let completedWorkoutCount: Int
    let totalVolumeDelta: Double
    let consistencyDelta: Int
    let risingSignals: [WeeklyCoachInsightRevisionSignalPayload]
    let watchSignals: [WeeklyCoachInsightRevisionSignalPayload]
    let fallbackSummary: String
    let followUpKinds: [String]
}

nonisolated struct WeeklyCoachInsightRevisionSignalPayload: Codable, Equatable, Sendable {
    let id: String
    let catalogExerciseUUID: String
    let exerciseName: String
    let deltaPercentage: Double
    let summary: String

    init(signal: WeeklyCoachSignal) {
        self.id = signal.id
        self.catalogExerciseUUID = signal.catalogExerciseUUID
        self.exerciseName = signal.exerciseName
        self.deltaPercentage = signal.deltaPercentage
        self.summary = signal.summary
    }
}

private nonisolated struct WeeklyCoachWeekBucket: Equatable, Sendable {
    var sessionIDs: Set<UUID> = []
    var totalVolume: Double = 0
    var effortByExercise: [String: Double] = [:]
    var exerciseNamesByUUID: [String: String] = [:]
    var exerciseDatesByUUID: [String: Date] = [:]

    mutating func ingest(_ fact: CompletedSetFact) {
        sessionIDs.insert(fact.sessionID)

        if let volumeKg = fact.volumeKg {
            totalVolume += volumeKg
        }

        let effort = effort(for: fact)
        if effort > 0 {
            effortByExercise[fact.catalogExerciseUUID, default: 0] += effort
        }

        if let existingDate = exerciseDatesByUUID[fact.catalogExerciseUUID] {
            if fact.completedAt >= existingDate {
                exerciseDatesByUUID[fact.catalogExerciseUUID] = fact.completedAt
                exerciseNamesByUUID[fact.catalogExerciseUUID] = fact.exerciseNameSnapshot
            }
        } else {
            exerciseDatesByUUID[fact.catalogExerciseUUID] = fact.completedAt
            exerciseNamesByUUID[fact.catalogExerciseUUID] = fact.exerciseNameSnapshot
        }
    }

    func exerciseName(for catalogExerciseUUID: String) -> String? {
        exerciseNamesByUUID[catalogExerciseUUID]
    }

    func exerciseCompletionDate(for catalogExerciseUUID: String) -> Date? {
        exerciseDatesByUUID[catalogExerciseUUID]
    }

    private func effort(for fact: CompletedSetFact) -> Double {
        if let volumeKg = fact.volumeKg {
            return volumeKg
        }

        guard fact.loadUnit == .bodyweight, fact.reps > 0 else {
            return 0
        }

        return Double(fact.reps)
    }
}
