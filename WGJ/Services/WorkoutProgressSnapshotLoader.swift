import Foundation
import SwiftData

nonisolated enum WorkoutProgressDirection: Equatable, Sendable {
    case up
    case down
    case flat

    static func compare(_ current: Double, _ previous: Double, tolerance: Double = 0.0001) -> WorkoutProgressDirection {
        let delta = current - previous
        if delta > tolerance {
            return .up
        }
        if delta < -tolerance {
            return .down
        }
        return .flat
    }
}

nonisolated enum WorkoutProgressComparisonMode: Equatable, Sendable {
    case sameTemplate
    case general
    case manual
}

nonisolated enum WorkoutProgressMetricKind: String, Equatable, Sendable {
    case volume
    case duration
    case prs
    case sets
    case exercises
}

nonisolated enum WorkoutProgressSelectionSlot: Equatable, Sendable {
    case previous
    case current
}

nonisolated struct WorkoutProgressSetInput: Equatable, Sendable {
    let id: UUID
    let sortOrder: Int
    let isWarmup: Bool
    let reps: Int?
    let weight: Double?
    let loadUnit: TemplateLoadUnit
    let isCompleted: Bool
}

nonisolated struct WorkoutProgressExerciseInput: Equatable, Sendable {
    let id: UUID
    let catalogExerciseUUID: String
    let exerciseName: String
    let sortOrder: Int
    let sets: [WorkoutProgressSetInput]
}

nonisolated struct WorkoutProgressSessionInput: Identifiable, Equatable, Sendable {
    let id: UUID
    let templateID: UUID?
    let name: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int
    let prHitsCount: Int
    let archivedAt: Date?
    let exercises: [WorkoutProgressExerciseInput]

    var completedAt: Date {
        endedAt ?? startedAt
    }

    var isArchived: Bool {
        archivedAt != nil
    }
}

nonisolated struct WorkoutProgressWorkoutOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let templateID: UUID?
    let name: String
    let completedAt: Date
    let detailText: String

    init(session: WorkoutProgressSessionInput) {
        id = session.id
        sessionID = session.id
        templateID = session.templateID
        name = session.name
        completedAt = session.completedAt
        detailText = session.completedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

nonisolated struct WorkoutProgressWorkoutSummary: Equatable, Sendable {
    let sessionID: UUID
    let templateID: UUID?
    let name: String
    let completedAt: Date
    let dateText: String
    let durationSeconds: Int
    let durationText: String
    let totalVolumeKg: Double
    let totalVolumeText: String
    let prHitsCount: Int
    let completedSetCount: Int
    let completedExerciseCount: Int
}

nonisolated struct WorkoutProgressMetricDelta: Identifiable, Equatable, Sendable {
    let id: WorkoutProgressMetricKind
    let kind: WorkoutProgressMetricKind
    let title: String
    let systemImage: String
    let currentText: String
    let previousText: String
    let deltaText: String
    let direction: WorkoutProgressDirection
}

nonisolated struct WorkoutProgressExerciseComparison: Identifiable, Equatable, Sendable {
    let id: String
    let catalogExerciseUUID: String
    let exerciseName: String
    let previousBestSetText: String
    let currentBestSetText: String
    let previousVolumeText: String
    let currentVolumeText: String
    let deltaText: String
    let direction: WorkoutProgressDirection
}

nonisolated struct WorkoutProgressHighlightCard: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let direction: WorkoutProgressDirection
}

nonisolated struct WorkoutProgressComparison: Equatable, Sendable {
    let mode: WorkoutProgressComparisonMode
    let previousWorkout: WorkoutProgressWorkoutSummary
    let currentWorkout: WorkoutProgressWorkoutSummary
    let metricDeltas: [WorkoutProgressMetricDelta]
    let exerciseComparisons: [WorkoutProgressExerciseComparison]
    let highlightCards: [WorkoutProgressHighlightCard]
}

nonisolated enum WorkoutProgressDashboardState: Equatable, Sendable {
    case insufficientHistory(availableWorkoutCount: Int)
    case selectionUnavailable
    case ready(WorkoutProgressComparison)
}

nonisolated struct WorkoutProgressDashboardSnapshot: Equatable, Sendable {
    let workoutOptions: [WorkoutProgressWorkoutOption]
    let selectedPreviousSessionID: UUID?
    let selectedCurrentSessionID: UUID?
    let state: WorkoutProgressDashboardState

    static let empty = WorkoutProgressDashboardSnapshot(
        workoutOptions: [],
        selectedPreviousSessionID: nil,
        selectedCurrentSessionID: nil,
        state: .insufficientHistory(availableWorkoutCount: 0)
    )

    func compatibleWorkoutOptions(for slot: WorkoutProgressSelectionSlot) -> [WorkoutProgressWorkoutOption] {
        workoutOptions
    }
}

nonisolated enum WorkoutProgressSnapshotBuilder {
    static func build(
        sessions: [WorkoutProgressSessionInput],
        selectedPreviousSessionID: UUID?,
        selectedCurrentSessionID: UUID?
    ) -> WorkoutProgressDashboardSnapshot {
        let visibleSessions = sessions
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.completedAt != rhs.completedAt {
                    return lhs.completedAt > rhs.completedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let options = visibleSessions.map(WorkoutProgressWorkoutOption.init(session:))
        guard visibleSessions.count >= 2 else {
            return WorkoutProgressDashboardSnapshot(
                workoutOptions: options,
                selectedPreviousSessionID: nil,
                selectedCurrentSessionID: nil,
                state: .insufficientHistory(availableWorkoutCount: visibleSessions.count)
            )
        }

        guard let selection = selection(
            from: visibleSessions,
            selectedPreviousSessionID: selectedPreviousSessionID,
            selectedCurrentSessionID: selectedCurrentSessionID
        ) else {
            return WorkoutProgressDashboardSnapshot(
                workoutOptions: options,
                selectedPreviousSessionID: selectedPreviousSessionID,
                selectedCurrentSessionID: selectedCurrentSessionID,
                state: .selectionUnavailable
            )
        }

        let comparison = comparison(
            previous: selection.previous,
            current: selection.current,
            mode: selection.mode
        )
        return WorkoutProgressDashboardSnapshot(
            workoutOptions: options,
            selectedPreviousSessionID: selection.previous.id,
            selectedCurrentSessionID: selection.current.id,
            state: .ready(comparison)
        )
    }

    private static func selection(
        from sessions: [WorkoutProgressSessionInput],
        selectedPreviousSessionID: UUID?,
        selectedCurrentSessionID: UUID?
    ) -> (previous: WorkoutProgressSessionInput, current: WorkoutProgressSessionInput, mode: WorkoutProgressComparisonMode)? {
        if let selectedPreviousSessionID,
           let selectedCurrentSessionID,
           selectedPreviousSessionID != selectedCurrentSessionID,
           let previous = sessions.first(where: { $0.id == selectedPreviousSessionID }),
           let current = sessions.first(where: { $0.id == selectedCurrentSessionID })
        {
            return orderedSelection(previous, current, mode: .manual)
        }

        if let sameTemplateSelection = latestSameTemplateSelection(from: sessions) {
            return sameTemplateSelection
        }

        return orderedSelection(sessions[0], sessions[1], mode: .general)
    }

    private static func latestSameTemplateSelection(
        from sessions: [WorkoutProgressSessionInput]
    ) -> (previous: WorkoutProgressSessionInput, current: WorkoutProgressSessionInput, mode: WorkoutProgressComparisonMode)? {
        for current in sessions {
            guard let templateID = current.templateID else { continue }
            guard let previous = sessions.first(where: { candidate in
                candidate.id != current.id
                    && candidate.templateID == templateID
                    && candidate.completedAt < current.completedAt
            }) else {
                continue
            }
            return orderedSelection(current, previous, mode: .sameTemplate)
        }

        return nil
    }

    private static func orderedSelection(
        _ first: WorkoutProgressSessionInput,
        _ second: WorkoutProgressSessionInput,
        mode: WorkoutProgressComparisonMode
    ) -> (previous: WorkoutProgressSessionInput, current: WorkoutProgressSessionInput, mode: WorkoutProgressComparisonMode) {
        if first.completedAt >= second.completedAt {
            return (previous: second, current: first, mode: mode)
        }
        return (previous: first, current: second, mode: mode)
    }

    private static func comparison(
        previous: WorkoutProgressSessionInput,
        current: WorkoutProgressSessionInput,
        mode: WorkoutProgressComparisonMode
    ) -> WorkoutProgressComparison {
        let previousMetrics = SessionMetrics(session: previous)
        let currentMetrics = SessionMetrics(session: current)
        let exerciseComparisons = exerciseComparisons(previous: previousMetrics, current: currentMetrics)

        return WorkoutProgressComparison(
            mode: mode,
            previousWorkout: workoutSummary(session: previous, metrics: previousMetrics),
            currentWorkout: workoutSummary(session: current, metrics: currentMetrics),
            metricDeltas: metricDeltas(previous: previousMetrics, current: currentMetrics),
            exerciseComparisons: exerciseComparisons,
            highlightCards: highlightCards(
                previous: previousMetrics,
                current: currentMetrics,
                exerciseComparisons: exerciseComparisons
            )
        )
    }

    private static func workoutSummary(
        session: WorkoutProgressSessionInput,
        metrics: SessionMetrics
    ) -> WorkoutProgressWorkoutSummary {
        WorkoutProgressWorkoutSummary(
            sessionID: session.id,
            templateID: session.templateID,
            name: session.name,
            completedAt: session.completedAt,
            dateText: session.completedAt.formatted(date: .abbreviated, time: .shortened),
            durationSeconds: session.durationSeconds,
            durationText: formattedDuration(session.durationSeconds),
            totalVolumeKg: metrics.totalVolumeKg,
            totalVolumeText: formattedVolume(metrics.totalVolumeKg),
            prHitsCount: session.prHitsCount,
            completedSetCount: metrics.completedSetCount,
            completedExerciseCount: metrics.completedExerciseCount
        )
    }

    private static func metricDeltas(
        previous: SessionMetrics,
        current: SessionMetrics
    ) -> [WorkoutProgressMetricDelta] {
        [
            metricDelta(
                kind: .volume,
                title: "Volume",
                systemImage: "scalemass.fill",
                previousValue: previous.totalVolumeKg,
                currentValue: current.totalVolumeKg,
                previousText: formattedVolume(previous.totalVolumeKg),
                currentText: formattedVolume(current.totalVolumeKg),
                deltaText: signedVolume(current.totalVolumeKg - previous.totalVolumeKg)
            ),
            metricDelta(
                kind: .duration,
                title: "Duration",
                systemImage: "clock.fill",
                previousValue: Double(previous.durationSeconds),
                currentValue: Double(current.durationSeconds),
                previousText: formattedDuration(previous.durationSeconds),
                currentText: formattedDuration(current.durationSeconds),
                deltaText: signedDuration(current.durationSeconds - previous.durationSeconds)
            ),
            metricDelta(
                kind: .prs,
                title: "PRs",
                systemImage: "trophy.fill",
                previousValue: Double(previous.prHitsCount),
                currentValue: Double(current.prHitsCount),
                previousText: "\(previous.prHitsCount)",
                currentText: "\(current.prHitsCount)",
                deltaText: signedInteger(current.prHitsCount - previous.prHitsCount)
            ),
            metricDelta(
                kind: .sets,
                title: "Sets",
                systemImage: "checklist",
                previousValue: Double(previous.completedSetCount),
                currentValue: Double(current.completedSetCount),
                previousText: "\(previous.completedSetCount)",
                currentText: "\(current.completedSetCount)",
                deltaText: signedInteger(current.completedSetCount - previous.completedSetCount)
            ),
            metricDelta(
                kind: .exercises,
                title: "Exercises",
                systemImage: "dumbbell.fill",
                previousValue: Double(previous.completedExerciseCount),
                currentValue: Double(current.completedExerciseCount),
                previousText: "\(previous.completedExerciseCount)",
                currentText: "\(current.completedExerciseCount)",
                deltaText: signedInteger(current.completedExerciseCount - previous.completedExerciseCount)
            ),
        ]
    }

    private static func metricDelta(
        kind: WorkoutProgressMetricKind,
        title: String,
        systemImage: String,
        previousValue: Double,
        currentValue: Double,
        previousText: String,
        currentText: String,
        deltaText: String
    ) -> WorkoutProgressMetricDelta {
        WorkoutProgressMetricDelta(
            id: kind,
            kind: kind,
            title: title,
            systemImage: systemImage,
            currentText: currentText,
            previousText: previousText,
            deltaText: deltaText,
            direction: .compare(currentValue, previousValue)
        )
    }

    private static func exerciseComparisons(
        previous: SessionMetrics,
        current: SessionMetrics
    ) -> [WorkoutProgressExerciseComparison] {
        let sharedIDs = Set(previous.exercisesByCatalogUUID.keys)
            .intersection(current.exercisesByCatalogUUID.keys)

        return sharedIDs.compactMap { catalogExerciseUUID in
            guard let previousExercise = previous.exercisesByCatalogUUID[catalogExerciseUUID],
                  let currentExercise = current.exercisesByCatalogUUID[catalogExerciseUUID]
            else {
                return nil
            }

            let direction = WorkoutProgressDirection.compare(
                currentExercise.comparisonScore,
                previousExercise.comparisonScore
            )
            return WorkoutProgressExerciseComparison(
                id: catalogExerciseUUID,
                catalogExerciseUUID: catalogExerciseUUID,
                exerciseName: currentExercise.exerciseName,
                previousBestSetText: previousExercise.bestSetText,
                currentBestSetText: currentExercise.bestSetText,
                previousVolumeText: formattedVolume(previousExercise.totalVolumeKg),
                currentVolumeText: formattedVolume(currentExercise.totalVolumeKg),
                deltaText: exerciseDeltaText(previous: previousExercise, current: currentExercise),
                direction: direction
            )
        }
        .sorted { lhs, rhs in
            let lhsMagnitude = abs(deltaMagnitude(for: lhs.deltaText))
            let rhsMagnitude = abs(deltaMagnitude(for: rhs.deltaText))
            if lhsMagnitude != rhsMagnitude {
                return lhsMagnitude > rhsMagnitude
            }
            return lhs.exerciseName.localizedStandardCompare(rhs.exerciseName) == .orderedAscending
        }
    }

    private static func highlightCards(
        previous: SessionMetrics,
        current: SessionMetrics,
        exerciseComparisons: [WorkoutProgressExerciseComparison]
    ) -> [WorkoutProgressHighlightCard] {
        guard !exerciseComparisons.isEmpty else {
            return [
                WorkoutProgressHighlightCard(
                    id: "no-overlap",
                    title: "No shared exercises",
                    value: "Fresh lineup",
                    detail: "These two workouts do not repeat any completed exercises.",
                    systemImage: "arrow.triangle.branch",
                    direction: .flat
                ),
            ]
        }

        let improvedCount = exerciseComparisons.filter { $0.direction == .up }.count
        let repeatedCount = exerciseComparisons.count
        let biggestMover = exerciseComparisons.first
        let volumeDelta = current.totalVolumeKg - previous.totalVolumeKg
        let prDelta = current.prHitsCount - previous.prHitsCount

        return [
            WorkoutProgressHighlightCard(
                id: "shared",
                title: "Repeated exercises",
                value: "\(repeatedCount)",
                detail: "\(improvedCount) moved up since the earlier workout.",
                systemImage: "repeat",
                direction: improvedCount > 0 ? .up : .flat
            ),
            WorkoutProgressHighlightCard(
                id: "biggest-mover",
                title: "Biggest mover",
                value: biggestMover?.exerciseName ?? "None",
                detail: biggestMover?.deltaText ?? "No movement yet.",
                systemImage: "bolt.fill",
                direction: biggestMover?.direction ?? .flat
            ),
            WorkoutProgressHighlightCard(
                id: "workload",
                title: "Workload signal",
                value: volumeDelta >= 0 ? "More work" : "Less work",
                detail: signedVolume(volumeDelta),
                systemImage: "chart.line.uptrend.xyaxis",
                direction: .compare(current.totalVolumeKg, previous.totalVolumeKg)
            ),
            WorkoutProgressHighlightCard(
                id: "prs",
                title: "PR signal",
                value: prDelta > 0 ? "New hits" : "Steady",
                detail: signedInteger(prDelta),
                systemImage: "trophy.fill",
                direction: .compare(Double(current.prHitsCount), Double(previous.prHitsCount))
            ),
        ]
    }

    private static func exerciseDeltaText(
        previous: ExerciseMetrics,
        current: ExerciseMetrics
    ) -> String {
        if previous.bestWeightedOneRepMaxKg != nil || current.bestWeightedOneRepMaxKg != nil {
            return signedVolume(current.totalVolumeKg - previous.totalVolumeKg)
        }

        return signedInteger(current.maxReps - previous.maxReps) + " reps"
    }

    private static func formattedDuration(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let hours = mins / 60
        let remMins = mins % 60
        if hours > 0 {
            return "\(hours)h \(remMins)m"
        }
        return "\(mins)m"
    }

    private static func formattedVolume(_ volume: Double) -> String {
        "\(WGJFormatters.integerString(volume)) kg"
    }

    private static func signedVolume(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(WGJFormatters.integerString(value)) kg"
    }

    private static func signedDuration(_ seconds: Int) -> String {
        guard abs(seconds) >= 60 else {
            return formattedDuration(0)
        }
        let prefix = seconds > 0 ? "+" : seconds < 0 ? "-" : ""
        return "\(prefix)\(formattedDuration(abs(seconds)))"
    }

    private static func signedInteger(_ value: Int) -> String {
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(value)"
    }

    private static func deltaMagnitude(for text: String) -> Double {
        Double(text.filter { $0 == "-" || $0 == "." || $0.isNumber }) ?? 0
    }
}

nonisolated private struct SessionMetrics: Equatable, Sendable {
    let durationSeconds: Int
    let prHitsCount: Int
    let totalVolumeKg: Double
    let completedSetCount: Int
    let completedExerciseCount: Int
    let exercisesByCatalogUUID: [String: ExerciseMetrics]

    init(session: WorkoutProgressSessionInput) {
        durationSeconds = session.durationSeconds
        prHitsCount = session.prHitsCount

        let exerciseMetrics = session.exercises
            .map(ExerciseMetrics.init(exercise:))
            .filter { $0.completedSetCount > 0 }

        totalVolumeKg = exerciseMetrics.reduce(0) { $0 + $1.totalVolumeKg }
        completedSetCount = exerciseMetrics.reduce(0) { $0 + $1.completedSetCount }
        completedExerciseCount = exerciseMetrics.count
        exercisesByCatalogUUID = Dictionary(
            exerciseMetrics.map { ($0.catalogExerciseUUID, $0) },
            uniquingKeysWith: { existing, candidate in
                candidate.comparisonScore > existing.comparisonScore ? candidate : existing
            }
        )
    }
}

nonisolated private struct ExerciseMetrics: Equatable, Sendable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let completedSetCount: Int
    let totalVolumeKg: Double
    let bestSetText: String
    let bestWeightedOneRepMaxKg: Double?
    let maxReps: Int

    var comparisonScore: Double {
        bestWeightedOneRepMaxKg ?? Double(maxReps)
    }

    init(exercise: WorkoutProgressExerciseInput) {
        catalogExerciseUUID = exercise.catalogExerciseUUID
        exerciseName = exercise.exerciseName

        let workingSets = exercise.sets
            .filter { set in
                guard set.isCompleted, !set.isWarmup, let reps = set.reps else { return false }
                return reps > 0
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        completedSetCount = workingSets.count
        totalVolumeKg = workingSets.reduce(0) { total, set in
            guard let reps = set.reps,
                  let weight = set.weight,
                  weight > 0,
                  set.loadUnit != .bodyweight
            else {
                return total
            }
            return total + normalizedLoad(weight, unit: set.loadUnit) * Double(reps)
        }
        maxReps = workingSets.compactMap(\.reps).max() ?? 0

        let bestWeightedSet = workingSets
            .filter { ($0.weight ?? 0) > 0 && $0.loadUnit != .bodyweight }
            .max { lhs, rhs in
                weightedScore(lhs) < weightedScore(rhs)
            }
        if let bestWeightedSet,
           let reps = bestWeightedSet.reps,
           let weight = bestWeightedSet.weight
        {
            bestWeightedOneRepMaxKg = normalizedLoad(estimatedOneRepMax(weight: weight, reps: reps), unit: bestWeightedSet.loadUnit)
            bestSetText = "\(WGJFormatters.decimalString(weight)) \(bestWeightedSet.loadUnit.shortLabel) x \(reps)"
        } else if let bestBodyweightSet = workingSets.max(by: { ($0.reps ?? 0) < ($1.reps ?? 0) }),
                  let reps = bestBodyweightSet.reps
        {
            bestWeightedOneRepMaxKg = nil
            bestSetText = "\(reps) reps"
        } else {
            bestWeightedOneRepMaxKg = nil
            bestSetText = "-"
        }
    }
}

nonisolated private func weightedScore(_ set: WorkoutProgressSetInput) -> Double {
    guard let weight = set.weight, let reps = set.reps else { return 0 }
    return normalizedLoad(estimatedOneRepMax(weight: weight, reps: reps), unit: set.loadUnit)
}

nonisolated private func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
    guard reps > 0 else { return weight }
    if reps == 1 { return weight }
    return weight * (1 + (Double(reps) / 30.0))
}

nonisolated private func normalizedLoad(_ value: Double, unit: TemplateLoadUnit) -> Double {
    switch unit {
    case .kg:
        return value
    case .lb:
        return value * 0.45359237
    case .bodyweight:
        return value
    }
}

nonisolated enum WorkoutProgressSnapshotLoader {
    static func load(
        modelContext: ModelContext,
        selectedPreviousSessionID: UUID?,
        selectedCurrentSessionID: UUID?
    ) throws -> WorkoutProgressDashboardSnapshot {
        let repository = WorkoutSessionRepository(modelContext: modelContext)
        let sessions = try repository
            .completedSessions(includeArchived: false)
            .map { session in
                try WorkoutProgressSessionInput(session: session, repository: repository)
            }
        return WorkoutProgressSnapshotBuilder.build(
            sessions: sessions,
            selectedPreviousSessionID: selectedPreviousSessionID,
            selectedCurrentSessionID: selectedCurrentSessionID
        )
    }
}

extension WorkoutProgressSessionInput {
    nonisolated init(session: WorkoutSession, repository: WorkoutSessionRepository) throws {
        self.init(
            id: session.id,
            templateID: session.templateID,
            name: session.name,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            durationSeconds: session.durationSeconds,
            prHitsCount: session.prHitsCount,
            archivedAt: session.archivedAt,
            exercises: try repository.sessionExercises(sessionID: session.id)
                .map { exercise in
                    try WorkoutProgressExerciseInput(exercise: exercise, repository: repository)
                }
        )
    }

    nonisolated init(session: WorkoutSession) {
        self.init(
            id: session.id,
            templateID: session.templateID,
            name: session.name,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            durationSeconds: session.durationSeconds,
            prHitsCount: session.prHitsCount,
            archivedAt: session.archivedAt,
            exercises: (session.exercises ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(WorkoutProgressExerciseInput.init(exercise:))
        )
    }
}

extension WorkoutProgressExerciseInput {
    nonisolated init(exercise: WorkoutSessionExercise, repository: WorkoutSessionRepository) throws {
        self.init(
            id: exercise.id,
            catalogExerciseUUID: exercise.catalogExerciseUUID,
            exerciseName: exercise.exerciseNameSnapshot,
            sortOrder: exercise.sortOrder,
            sets: try repository.sessionSets(sessionExerciseID: exercise.id)
                .map(WorkoutProgressSetInput.init(set:))
        )
    }

    nonisolated init(exercise: WorkoutSessionExercise) {
        self.init(
            id: exercise.id,
            catalogExerciseUUID: exercise.catalogExerciseUUID,
            exerciseName: exercise.exerciseNameSnapshot,
            sortOrder: exercise.sortOrder,
            sets: (exercise.sets ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(WorkoutProgressSetInput.init(set:))
        )
    }
}

extension WorkoutProgressSetInput {
    nonisolated init(set: WorkoutSessionSet) {
        let normalizedActualLoad = WorkoutLoggedLoadNormalization.resolved(
            actualWeight: set.actualWeight,
            actualLoadUnit: set.actualLoadUnit,
            targetLoadUnit: set.targetLoadUnit
        )
        self.init(
            id: set.id,
            sortOrder: set.sortOrder,
            isWarmup: set.isWarmup,
            reps: set.actualReps,
            weight: normalizedActualLoad.weight,
            loadUnit: normalizedActualLoad.unit,
            isCompleted: set.isCompleted
        )
    }
}
