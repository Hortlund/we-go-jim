import Foundation

nonisolated enum ExerciseProgressProjector {
    static func project(
        dataset: ExerciseProgressDataset,
        metric: ExerciseProgressMetric,
        range: ExerciseProgressRange,
        now: Date,
        calendar: Calendar,
        maximumChartPointCount: Int = 60
    ) -> ExerciseProgressProjection {
        let sessions = sessionsInRange(dataset.sessions, range: range, now: now, calendar: calendar)
        let points = points(
            from: sessions,
            metric: metric,
            displayUnit: dataset.preferredLoadUnit,
            now: now,
            calendar: calendar
        )
        let availability = availability(for: metric, points: points)
        let summary = summary(points: points, sessions: sessions)
        let milestones = milestones(points: points, metric: metric)
        let chartPoints = downsample(
            points: points,
            milestones: milestones,
            maximumCount: max(maximumChartPointCount, 2)
        )
        let accessibilitySummary = accessibilitySummary(
            exerciseName: dataset.exerciseName,
            metric: metric,
            range: range,
            summary: summary,
            availability: availability
        )

        return ExerciseProgressProjection(
            metric: metric,
            range: range,
            availability: availability,
            displayUnit: dataset.preferredLoadUnit,
            points: points,
            chartPoints: chartPoints,
            summary: summary,
            milestones: milestones,
            accessibilitySummary: accessibilitySummary
        )
    }

    private static func sessionsInRange(
        _ sessions: [ExerciseProgressSession],
        range: ExerciseProgressRange,
        now: Date,
        calendar: Calendar
    ) -> [ExerciseProgressSession] {
        let cutoff: Date?
        switch range {
        case .oneMonth: cutoff = calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths: cutoff = calendar.date(byAdding: .month, value: -3, to: now)
        case .sixMonths: cutoff = calendar.date(byAdding: .month, value: -6, to: now)
        case .oneYear: cutoff = calendar.date(byAdding: .year, value: -1, to: now)
        case .allTime: cutoff = nil
        }
        return sessions.filter { session in
            session.completedAt <= now && (cutoff.map { session.completedAt >= $0 } ?? true)
        }
    }

    private static func points(
        from sessions: [ExerciseProgressSession],
        metric: ExerciseProgressMetric,
        displayUnit: TemplateLoadUnit,
        now: Date,
        calendar: Calendar
    ) -> [ExerciseProgressPoint] {
        if metric == .workoutFrequency {
            return frequencyPoints(from: sessions, through: now, calendar: calendar)
        }

        return sessions.compactMap { session in
            let rawValue: Double?
            switch metric {
            case .estimatedOneRepMax: rawValue = session.estimatedOneRepMaxKilograms
            case .heaviestWeight: rawValue = session.heaviestWeightKilograms
            case .sessionVolume: rawValue = session.sessionVolumeKilograms
            case .bestSetReps: rawValue = session.bestSetReps.map(Double.init)
            case .totalReps: rawValue = Double(session.totalReps)
            case .workoutFrequency: rawValue = nil
            }
            guard let rawValue else { return nil }
            let value = metric.isWeighted ? convertedKilograms(rawValue, to: displayUnit) : rawValue
            return ExerciseProgressPoint(
                id: "\(session.sessionID.uuidString)-\(metric.rawValue)",
                date: session.completedAt,
                value: value
            )
        }
    }

    private static func frequencyPoints(
        from sessions: [ExerciseProgressSession],
        through now: Date,
        calendar: Calendar
    ) -> [ExerciseProgressPoint] {
        let grouped = Dictionary(grouping: sessions) { session in
            calendar.dateInterval(of: .weekOfYear, for: session.completedAt)?.start
                ?? calendar.startOfDay(for: session.completedAt)
        }
        guard let firstWeek = grouped.keys.min(),
              let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        else { return [] }

        var weeks: [Date] = []
        var week = firstWeek
        while week <= currentWeek {
            weeks.append(week)
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: week),
                  nextWeek > week
            else { break }
            week = nextWeek
        }

        return weeks.map { week in
            let count = Set(grouped[week, default: []].map(\.sessionID)).count
            return ExerciseProgressPoint(
                id: "frequency-\(week.timeIntervalSinceReferenceDate)",
                date: week,
                value: Double(count)
            )
        }
    }

    private static func convertedKilograms(_ value: Double, to unit: TemplateLoadUnit) -> Double {
        switch unit {
        case .lb: value * 2.204_622_621_8
        case .kg, .bodyweight: value
        }
    }

    private static func availability(
        for metric: ExerciseProgressMetric,
        points: [ExerciseProgressPoint]
    ) -> ExerciseProgressAvailability {
        guard !points.isEmpty else {
            let reason = metric.isWeighted
                ? "No weighted sets have been completed for this exercise."
                : "No compatible completed sets are available in this range."
            return ExerciseProgressAvailability(isAvailable: false, reason: reason)
        }
        return ExerciseProgressAvailability(isAvailable: true, reason: nil)
    }

    private static func summary(
        points: [ExerciseProgressPoint],
        sessions: [ExerciseProgressSession]
    ) -> ExerciseProgressSummary? {
        guard let first = points.first, let latest = points.last,
              let best = points.max(by: { lhs, rhs in
                  lhs.value == rhs.value ? lhs.date > rhs.date : lhs.value < rhs.value
              })
        else { return nil }
        let change = latest.value - first.value
        return ExerciseProgressSummary(
            first: first.value,
            latest: latest.value,
            best: best.value,
            absoluteChange: change,
            percentageChange: first.value == 0 ? nil : change / first.value * 100,
            sessionCount: Set(sessions.map(\.sessionID)).count,
            totalSets: sessions.reduce(0) { $0 + $1.completedSetCount },
            totalReps: sessions.reduce(0) { $0 + $1.totalReps }
        )
    }

    private static func milestones(
        points: [ExerciseProgressPoint],
        metric: ExerciseProgressMetric
    ) -> [ExerciseProgressMilestone] {
        guard let first = points.first else { return [] }
        var result = [milestone(first, kind: .firstPerformance)]
        var record = first.value
        var previous = first

        for point in points.dropFirst() {
            if point.value > record {
                result.append(milestone(point, kind: .personalRecord))
                record = point.value
            } else if isMaterialChange(from: previous.value, to: point.value, metric: metric) {
                result.append(milestone(point, kind: .materialChange))
            }
            previous = point
        }

        if let latest = points.last, result.last?.pointID != latest.id {
            result.append(milestone(latest, kind: .latestPerformance))
        }
        return cappedMilestones(result, maximumCount: 24)
    }

    private static func milestone(
        _ point: ExerciseProgressPoint,
        kind: ExerciseProgressMilestoneKind
    ) -> ExerciseProgressMilestone {
        ExerciseProgressMilestone(
            id: "\(point.id)-\(kind.rawValue)",
            pointID: point.id,
            date: point.date,
            value: point.value,
            kind: kind
        )
    }

    private static func isMaterialChange(
        from previous: Double,
        to current: Double,
        metric: ExerciseProgressMetric
    ) -> Bool {
        switch metric {
        case .bestSetReps, .totalReps:
            return abs(current - previous) >= 2
        case .workoutFrequency:
            return abs(current - previous) >= 1
        case .estimatedOneRepMax, .heaviestWeight, .sessionVolume:
            guard previous != 0 else { return current != 0 }
            return abs(current - previous) / abs(previous) >= 0.05
        }
    }

    private static func cappedMilestones(
        _ milestones: [ExerciseProgressMilestone],
        maximumCount: Int
    ) -> [ExerciseProgressMilestone] {
        guard milestones.count > maximumCount else { return milestones }
        guard let first = milestones.first, let last = milestones.last else { return [] }
        var selected = [first, last]
        for item in milestones.dropFirst().dropLast().reversed()
            where selected.count < maximumCount {
            selected.append(item)
        }
        return selected.sorted { $0.date < $1.date }
    }

    private static func downsample(
        points: [ExerciseProgressPoint],
        milestones: [ExerciseProgressMilestone],
        maximumCount: Int
    ) -> [ExerciseProgressPoint] {
        guard points.count > maximumCount else { return points }
        var mandatoryIDs = Set(milestones.map(\.pointID))
        if let first = points.first { mandatoryIDs.insert(first.id) }
        if let last = points.last { mandatoryIDs.insert(last.id) }
        if let minimum = points.min(by: { $0.value < $1.value }) { mandatoryIDs.insert(minimum.id) }
        if let maximum = points.max(by: { $0.value < $1.value }) { mandatoryIDs.insert(maximum.id) }

        var selected = points.filter { mandatoryIDs.contains($0.id) }
        if selected.count > maximumCount {
            let endpointIDs = Set([points.first?.id, points.last?.id].compactMap { $0 })
            let recentMandatory = selected.reversed().filter { !endpointIDs.contains($0.id) }
            selected = points.filter { endpointIDs.contains($0.id) }
            selected.append(contentsOf: recentMandatory.prefix(maximumCount - selected.count))
            return selected.sorted { $0.date < $1.date }
        }

        let remaining = points.filter { !mandatoryIDs.contains($0.id) }
        let slots = maximumCount - selected.count
        if slots > 0, !remaining.isEmpty {
            for slot in 0..<slots {
                let index = min(Int(Double(slot) * Double(remaining.count) / Double(slots)), remaining.count - 1)
                selected.append(remaining[index])
            }
        }
        return Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
            .values
            .sorted { $0.date < $1.date }
    }

    private static func accessibilitySummary(
        exerciseName: String,
        metric: ExerciseProgressMetric,
        range: ExerciseProgressRange,
        summary: ExerciseProgressSummary?,
        availability: ExerciseProgressAvailability
    ) -> String {
        guard let summary else {
            return availability.reason ?? "No progress data for \(exerciseName)."
        }
        return "\(exerciseName), \(metric.title), \(range.title), \(summary.sessionCount) sessions, latest \(summary.latest), best \(summary.best)."
    }
}
