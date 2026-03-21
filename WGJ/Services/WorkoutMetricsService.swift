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

@MainActor
final class WorkoutMetricsService {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        if reps == 1 { return weight }
        return weight * (1 + (Double(reps) / 30.0))
    }

    func bestEstimatedOneRepMax(
        for catalogExerciseUUID: String,
        before date: Date? = nil,
        excludingSessionID: UUID? = nil
    ) throws -> Double? {
        let sessions = try completedSessions()
        var best: Double?

        for session in sessions {
            if let excludingSessionID, session.id == excludingSessionID {
                continue
            }

            let referenceDate = session.endedAt ?? session.startedAt
            if let date, referenceDate >= date {
                continue
            }

            for exercise in orderedSessionExercises(session) where exercise.catalogExerciseUUID == catalogExerciseUUID {
                for set in orderedSessionSets(exercise) where set.isCompleted {
                    guard let value = metricInput(from: set) else { continue }
                    let oneRM = comparisonOneRepMax(weight: value.weight, reps: value.reps, unit: value.unit)
                    best = max(best ?? 0, oneRM)
                }
            }
        }

        return best
    }

    func countPRHits(sessionID: UUID) throws -> Int {
        guard let session = try session(id: sessionID) else { return 0 }

        var hits = 0
        for exercise in orderedSessionExercises(session) {
            var runningBest = try bestEstimatedOneRepMax(
                for: exercise.catalogExerciseUUID,
                before: session.startedAt,
                excludingSessionID: session.id
            ) ?? 0

            for set in orderedSessionSets(exercise) where set.isCompleted {
                guard let value = metricInput(from: set) else { continue }
                let oneRM = comparisonOneRepMax(weight: value.weight, reps: value.reps, unit: value.unit)
                if oneRM > runningBest {
                    hits += 1
                    runningBest = oneRM
                }
            }
        }

        return hits
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
            var bestAchievement: SessionPRAchievement?

            for set in orderedSessionSets(exercise) where set.isCompleted {
                guard let value = metricInput(from: set) else { continue }
                let oneRM = estimatedOneRepMax(weight: value.weight, reps: value.reps)
                let comparisonOneRM = normalizedLoadForComparison(oneRM, unit: value.unit)
                guard comparisonOneRM > runningBest else { continue }

                runningBest = comparisonOneRM
                let achievement = SessionPRAchievement(
                    id: "\(session.id.uuidString.lowercased())_\(exercise.catalogExerciseUUID.lowercased())",
                    catalogExerciseUUID: exercise.catalogExerciseUUID,
                    exerciseName: exercise.exerciseNameSnapshot,
                    estimatedOneRepMax: oneRM,
                    weight: value.weight,
                    reps: value.reps,
                    loadUnit: value.unit
                )

                if let currentBest = bestAchievement {
                    if achievement.estimatedOneRepMax > currentBest.estimatedOneRepMax {
                        bestAchievement = achievement
                    }
                } else {
                    bestAchievement = achievement
                }
            }

            if let bestAchievement {
                achievements.append(bestAchievement)
            }
        }

        return achievements
    }

    func totalVolume(sessionID: UUID) throws -> Double {
        guard let session = try session(id: sessionID) else { return 0 }

        var total = 0.0
        for exercise in orderedSessionExercises(session) {
            for set in orderedSessionSets(exercise) where set.isCompleted {
                if let actualWeight = set.actualWeight, let actualReps = set.actualReps {
                    total += actualWeight * Double(max(0, actualReps))
                    continue
                }

                if let targetWeight = set.targetWeight, let targetReps = set.targetReps {
                    total += targetWeight * Double(max(0, targetReps))
                }
            }
        }

        return total
    }

    func personalRecords(limit: Int = 8) throws -> [WorkoutPRRecord] {
        try profileDashboardSnapshot(prLimit: limit, weeks: 1).personalRecords
    }

    func weeklyWorkoutProgress(weeks: Int = 8) throws -> [WeeklyWorkoutProgressPoint] {
        try profileDashboardSnapshot(prLimit: 1, weeks: weeks).weeklyProgress
    }

    func exerciseHistoryOptions() throws -> [ExerciseHistoryOption] {
        let sessions = try completedSessions()
        var latestByExercise: [String: ExerciseHistoryOption] = [:]

        for session in sessions {
            let performedAt = session.endedAt ?? session.startedAt

            for exercise in orderedSessionExercises(session) {
                let hasWeightedHistory = orderedSessionSets(exercise).contains { set in
                    set.isCompleted && weightedMetricInput(from: set) != nil
                }
                guard hasWeightedHistory else { continue }

                let option = ExerciseHistoryOption(
                    catalogExerciseUUID: exercise.catalogExerciseUUID,
                    exerciseName: exercise.exerciseNameSnapshot,
                    lastPerformedAt: performedAt
                )

                if let existing = latestByExercise[exercise.catalogExerciseUUID] {
                    if option.lastPerformedAt > existing.lastPerformedAt {
                        latestByExercise[exercise.catalogExerciseUUID] = option
                    }
                } else {
                    latestByExercise[exercise.catalogExerciseUUID] = option
                }
            }
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
        let sessions = try completedSessions()
        var recentPoints: [CollectedExerciseMetricPoint] = []
        var exerciseName = preferredExerciseName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if exerciseName?.isEmpty == true {
            exerciseName = nil
        }

        for session in sessions {
            let performedAt = session.endedAt ?? session.startedAt
            var bestOneRepMaxInKilograms: Double?
            var sourceUnit: TemplateLoadUnit = .kg

            for exercise in orderedSessionExercises(session) where exercise.catalogExerciseUUID == catalogExerciseUUID {
                if exerciseName == nil {
                    exerciseName = exercise.exerciseNameSnapshot
                }

                for set in orderedSessionSets(exercise) where set.isCompleted {
                    guard let value = weightedMetricInput(from: set) else { continue }
                    let oneRepMaxInKilograms = normalizedLoadForComparison(
                        estimatedOneRepMax(weight: value.weight, reps: value.reps),
                        unit: value.unit
                    )

                    if let currentBest = bestOneRepMaxInKilograms {
                        if oneRepMaxInKilograms > currentBest {
                            bestOneRepMaxInKilograms = oneRepMaxInKilograms
                            sourceUnit = value.unit
                        }
                    } else {
                        bestOneRepMaxInKilograms = oneRepMaxInKilograms
                        sourceUnit = value.unit
                    }
                }
            }

            guard let bestOneRepMaxInKilograms else { continue }
            recentPoints.append(
                CollectedExerciseMetricPoint(
                    completedAt: performedAt,
                    normalizedValue: bestOneRepMaxInKilograms,
                    sourceUnit: sourceUnit
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
        let sessions = try completedSessions()
        var recentPoints: [CollectedExerciseMetricPoint] = []
        var exerciseName = preferredExerciseName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if exerciseName?.isEmpty == true {
            exerciseName = nil
        }

        for session in sessions {
            let performedAt = session.endedAt ?? session.startedAt
            var totalVolumeInKilograms = 0.0
            var sourceUnit: TemplateLoadUnit = .kg
            var hasData = false

            for exercise in orderedSessionExercises(session) where exercise.catalogExerciseUUID == catalogExerciseUUID {
                if exerciseName == nil {
                    exerciseName = exercise.exerciseNameSnapshot
                }

                for set in orderedSessionSets(exercise) where set.isCompleted {
                    guard let value = weightedMetricInput(from: set) else { continue }
                    totalVolumeInKilograms += normalizedLoadForComparison(value.weight, unit: value.unit) * Double(value.reps)
                    sourceUnit = value.unit
                    hasData = true
                }
            }

            guard hasData else { continue }
            recentPoints.append(
                CollectedExerciseMetricPoint(
                    completedAt: performedAt,
                    normalizedValue: totalVolumeInKilograms,
                    sourceUnit: sourceUnit
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
        let sessions = try completedSessions()
        var bestByExercise: [String: WorkoutPRRecord] = [:]
        let nowWeek = weekStart(for: Date())
        var weeksToInclude: [Date] = []
        weeksToInclude.reserveCapacity(safeWeeks)
        for offset in (0..<safeWeeks).reversed() {
            if let week = calendar.date(byAdding: .weekOfYear, value: -offset, to: nowWeek) {
                weeksToInclude.append(week)
            }
        }
        var countsByWeek: [Date: Int] = [:]
        var countsByDay: [Date: Int] = [:]
        var exerciseFrequencyByUUID: [String: CollectedExerciseFrequency] = [:]
        var totalDurationSeconds = 0
        var totalPRHits = 0
        var firstWorkoutDate: Date?

        for session in sessions {
            let achievedAt = session.endedAt ?? session.startedAt
            let week = weekStart(for: achievedAt)
            let day = calendar.startOfDay(for: achievedAt)
            countsByWeek[week, default: 0] += 1
            countsByDay[day, default: 0] += 1
            totalDurationSeconds += max(0, session.durationSeconds)
            totalPRHits += max(0, session.prHitsCount)

            if let existingFirstWorkoutDate = firstWorkoutDate {
                if achievedAt < existingFirstWorkoutDate {
                    firstWorkoutDate = achievedAt
                }
            } else {
                firstWorkoutDate = achievedAt
            }

            var countedExerciseUUIDs: Set<String> = []

            for exercise in orderedSessionExercises(session) {
                if countedExerciseUUIDs.insert(exercise.catalogExerciseUUID).inserted {
                    if let existing = exerciseFrequencyByUUID[exercise.catalogExerciseUUID] {
                        exerciseFrequencyByUUID[exercise.catalogExerciseUUID] = CollectedExerciseFrequency(
                            exerciseName: achievedAt >= existing.lastPerformedAt ? exercise.exerciseNameSnapshot : existing.exerciseName,
                            sessionCount: existing.sessionCount + 1,
                            lastPerformedAt: max(existing.lastPerformedAt, achievedAt)
                        )
                    } else {
                        exerciseFrequencyByUUID[exercise.catalogExerciseUUID] = CollectedExerciseFrequency(
                            exerciseName: exercise.exerciseNameSnapshot,
                            sessionCount: 1,
                            lastPerformedAt: achievedAt
                        )
                    }
                }

                for set in orderedSessionSets(exercise) where set.isCompleted {
                    guard let value = metricInput(from: set) else { continue }
                    let oneRM = estimatedOneRepMax(weight: value.weight, reps: value.reps)
                    let record = WorkoutPRRecord(
                        id: exercise.catalogExerciseUUID,
                        catalogExerciseUUID: exercise.catalogExerciseUUID,
                        exerciseName: exercise.exerciseNameSnapshot,
                        estimatedOneRepMax: oneRM,
                        weight: value.weight,
                        reps: value.reps,
                        loadUnit: value.unit,
                        achievedAt: achievedAt
                    )

                    if let existing = bestByExercise[exercise.catalogExerciseUUID] {
                        if isBetterPRRecord(record, than: existing) {
                            bestByExercise[exercise.catalogExerciseUUID] = record
                        }
                    } else {
                        bestByExercise[exercise.catalogExerciseUUID] = record
                    }
                }
            }
        }

        let personalRecords = bestByExercise.values
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
                completedWorkouts: countsByWeek[week, default: 0],
                goal: profileGoal
            )
        }
        let overviewStats = buildOverviewStats(
            completedWorkoutCount: sessions.count,
            totalPRHits: totalPRHits,
            totalDurationSeconds: totalDurationSeconds,
            workoutCountsByDay: countsByDay,
            firstWorkoutDate: firstWorkoutDate
        )
        let topExercises = exerciseFrequencyByUUID.map { entry in
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
        let activityDays = buildActivityDays(from: countsByDay)

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
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).filter { $0.status == .completed }
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

    private func metricInput(from set: WorkoutSessionSet) -> (weight: Double, reps: Int, unit: TemplateLoadUnit)? {
        if let actualWeight = set.actualWeight, let actualReps = set.actualReps, actualWeight > 0, actualReps > 0 {
            return (actualWeight, actualReps, set.actualLoadUnit)
        }

        if let targetWeight = set.targetWeight, let targetReps = set.targetReps, targetWeight > 0, targetReps > 0 {
            return (targetWeight, targetReps, set.targetLoadUnit)
        }

        return nil
    }

    private func weightedMetricInput(from set: WorkoutSessionSet) -> (weight: Double, reps: Int, unit: TemplateLoadUnit)? {
        guard let value = metricInput(from: set), value.unit != .bodyweight else {
            return nil
        }

        return value
    }

    private func currentGoal() throws -> Int {
        let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        let profile = try modelContext.fetch(descriptor).first
        return max(1, min(14, profile?.weeklyWorkoutGoal ?? 4))
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
        switch unit {
        case .kg:
            return value
        case .lb:
            return value * 0.45359237
        case .bodyweight:
            return value
        }
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

private struct CollectedExerciseFrequency {
    let exerciseName: String
    let sessionCount: Int
    let lastPerformedAt: Date
}
