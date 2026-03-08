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

struct ProfileDashboardSnapshot: Equatable {
    let personalRecords: [WorkoutPRRecord]
    let weeklyProgress: [WeeklyWorkoutProgressPoint]
    let weeklyGoal: Int
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

        for session in sessions {
            let achievedAt = session.endedAt ?? session.startedAt
            let week = weekStart(for: achievedAt)
            countsByWeek[week, default: 0] += 1

            for exercise in orderedSessionExercises(session) {
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

        return ProfileDashboardSnapshot(
            personalRecords: personalRecords,
            weeklyProgress: weeklyProgress,
            weeklyGoal: profileGoal
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

    private func currentGoal() throws -> Int {
        let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        let profile = try modelContext.fetch(descriptor).first
        return max(1, min(14, profile?.weeklyWorkoutGoal ?? 4))
    }

    private func weekStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
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

    private func isBetterPRRecord(_ candidate: WorkoutPRRecord, than existing: WorkoutPRRecord) -> Bool {
        let candidateValue = normalizedLoadForComparison(candidate.estimatedOneRepMax, unit: candidate.loadUnit)
        let existingValue = normalizedLoadForComparison(existing.estimatedOneRepMax, unit: existing.loadUnit)

        if candidateValue != existingValue {
            return candidateValue > existingValue
        }

        return candidate.achievedAt > existing.achievedAt
    }
}
