#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData

/// Fictional capture data. Only reached by an explicit launch argument in an in-memory simulator store.
nonisolated enum MarketingShowcaseSeed {
    static func seed(container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try DemoSeedService(modelContext: context).seedDemoDataIfEmpty()
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.displayName = "hortlund"
        profile.athleteType = .legDaySurvivor
        // Capture-only input, copied into the simulator's Documents directory before launch.
        // Keep the supplied artwork outside the shipping app bundle.
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let avatarURL = documents.appendingPathComponent("marketing-avatar.png")
            if FileManager.default.fileExists(atPath: avatarURL.path) {
                profile.avatarImageData = try Data(contentsOf: avatarURL)
            }
        }
        profile.dateOfBirth = Calendar.current.date(from: DateComponents(year: 1996, month: 3, day: 18))
        profile.weeklyWorkoutGoal = 4
        let catalog = try context.fetch(FetchDescriptor<ExerciseCatalogItem>())
        let items = Dictionary(catalog.map { ($0.remoteUUID, $0) }, uniquingKeysWith: { first, _ in first })
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let loads: [String: Double] = ["seed-bench-press": 75, "seed-overhead-press": 40,
            "seed-incline-dumbbell-press": 24, "seed-dips": 10, "seed-deadlift": 130,
            "seed-bent-over-row": 60, "seed-pull-up": 10, "seed-lat-pulldown": 55,
            "seed-back-squat": 90, "seed-leg-press": 160, "seed-dumbbell-lunge": 20,
            "seed-hanging-leg-raise": 0]
        for template in templates {
            for exercise in template.exercises ?? [] {
                let weight = loads[exercise.catalogExerciseUUID] ?? 20
                exercise.targetRepMin = 8
                exercise.targetRepMax = 10
                for old in exercise.prescribedSets ?? [] { context.delete(old) }
                exercise.prescribedSets = (0..<4).map { i in
                    let set = TemplateExerciseSet(templateExerciseID: exercise.id, sortOrder: i,
                        targetReps: i == 0 ? 12 : 8, targetWeight: i == 0 ? weight * 0.5 : weight,
                        isWarmup: i == 0, templateExercise: exercise)
                    context.insert(set)
                    return set
                }
            }
        }
        let now = Date()
        let calendar = Calendar.current
        let routines: [(String, [String])] = [
            ("Push A", ["seed-bench-press", "seed-overhead-press", "seed-incline-dumbbell-press"]),
            ("Pull A", ["seed-deadlift", "seed-bent-over-row", "seed-lat-pulldown"]),
            ("Legs A", ["seed-back-squat", "seed-leg-press", "seed-dumbbell-lunge"])]
        for week in 0..<24 {
            for (day, routine) in routines.enumerated() {
                let daysAgo = week * 7 + day + 2
                let end = calendar.date(bySettingHour: 18, minute: 30, second: 0,
                    of: calendar.date(byAdding: .day, value: -daysAgo, to: now)!)!
                let start = end.addingTimeInterval(-3_600 - Double(day * 300))
                let session = WorkoutSession(templateID: templates.first { $0.name == routine.0 }?.id,
                    name: routine.0, status: .completed, startedAt: start, endedAt: end,
                    durationSeconds: Int(end.timeIntervalSince(start)), estimatedActiveCalories: 420 + day * 35,
                    calorieEstimateVersion: WorkoutCalorieEstimator.currentVersion,
                    notes: "Controlled reps. Strong finish.", createdAt: start, updatedAt: end)
                context.insert(session)
                session.exercises = routine.1.enumerated().compactMap { index, key in
                    guard let item = items[key] else { return nil }
                    let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: key,
                        exerciseNameSnapshot: item.displayName, categorySnapshot: item.categoryName,
                        muscleSummarySnapshot: item.primaryMuscleNames, targetRepMin: 8, targetRepMax: 10,
                        totalSetCount: 4, completedSetCount: 4, sortOrder: index,
                        createdAt: start, updatedAt: end, session: session)
                    context.insert(exercise)
                    let weight = max(10, (loads[key] ?? 40) - Double(week / 3) * 2.5)
                    exercise.sets = (0..<4).map { i in
                        let value = i == 0 ? weight * 0.5 : weight
                        let set = WorkoutSessionSet(sessionExerciseID: exercise.id, sortOrder: i,
                            isWarmup: i == 0, restSeconds: 120, targetReps: i == 0 ? 12 : 8,
                            targetWeight: value, actualReps: i == 0 ? 12 : 8, actualWeight: value,
                            isCompleted: true, isLocked: true, createdAt: start, updatedAt: end,
                            sessionExercise: exercise)
                        context.insert(set)
                        return set
                    }
                    return exercise
                }
            }
            let end = calendar.date(byAdding: .day, value: -(week * 7 + 5), to: now)!
            let seconds = 1_680 + week * 12
            let session = WorkoutSession(name: "Morning 5K", status: .completed,
                startedAt: end.addingTimeInterval(-Double(seconds)), endedAt: end,
                durationSeconds: seconds, estimatedActiveCalories: 365,
                calorieEstimateVersion: WorkoutCalorieEstimator.currentVersion,
                notes: "Easy pace, fresh air.", createdAt: end, updatedAt: end)
            context.insert(session)
            let cardio = WorkoutSessionCardioBlock(sessionID: session.id, phase: .preWorkout, role: .main,
                catalogExerciseUUID: "seed-outdoor-run", exerciseNameSnapshot: "Outdoor Run",
                categorySnapshot: "Cardio", muscleSummarySnapshot: "Legs", trackingProfile: .walkRun,
                goalKind: .open, targetDurationSeconds: 0, actualDurationSeconds: seconds,
                actualDistanceMeters: 5_000, preferredDistanceUnit: .kilometers,
                isCompleted: true, createdAt: end, updatedAt: end, session: session)
            context.insert(cardio)
            session.cardioBlocks = [cardio]
        }
        // Present a useful mix without empty exercise-selection widgets.
        let widgets = try ProfileWidgetRepository(modelContext: context,
            boundaryEffects: .init(scheduleBackup: { _, _ in })).configurations()
        let order: [ProfileWidgetKind] = [.weeklyGoals, .weeklyMuscleHeatmap, .prs,
            .consistencyCalendar, .streaks, .topExercises, .coachBrief]
        for widget in widgets {
            widget.isEnabled = order.contains(widget.kind)
            widget.sortOrder = order.firstIndex(of: widget.kind) ?? 20
        }
        try context.saveWithRecoveryProtection()
        let metrics = WorkoutMetricsService(modelContext: context)
        let projections = HistoryProjectionRepository(modelContext: context)
        for session in try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt)])) {
            let facts = HistoryProjectionSnapshotBuilder.projectedFacts(from: session)
            let summary = try metrics.sessionSummary(session: session, projectedFacts: facts)
            session.totalVolume = summary.totalVolume
            session.prHitsCount = summary.prHitsCount
            session.summaryMetricsVersion = WorkoutMetricsService.currentSummaryMetricsVersion
            _ = try projections.rebuildFacts(forSessionID: session.id, persistChanges: false)
        }
        try context.saveWithRecoveryProtection()
        HistoryAnalyticsCache.shared.invalidate(container: container)
    }
}
#endif
