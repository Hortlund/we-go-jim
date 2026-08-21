#if DEBUG
import Foundation
import SwiftData

nonisolated final class DemoSeedService {
    private let modelContext: ModelContext
    private let profileRepository: ProfileRepository
    private let templateRepository: TemplateRepository
    private let catalogRepository: ExerciseCatalogRepository

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.profileRepository = ProfileRepository(modelContext: modelContext)
        self.templateRepository = TemplateRepository(
            modelContext: modelContext,
            autoSaveChanges: false,
            boundaryEffects: TemplateSaveBoundaryEffects(
                postLibraryChange: {},
                scheduleBackup: { _, _ in }
            )
        )
        self.catalogRepository = ExerciseCatalogRepository(modelContext: modelContext)
    }

    func seedDemoDataIfEmpty() throws {
        try catalogRepository.ensureSeedImportedIfNeeded()

        let profile = try profileRepository.loadOrCreateProfile()
        if profile.displayName == "Athlete" {
            profile.displayName = "Demo Lifter"
            profile.athleteType = .hybridAthlete
            profile.calorieEstimateSex = .male
            profile.dateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: .now)
            profile.heightCentimeters = 180
            profile.bodyWeightKilograms = 82
            profile.weeklyWorkoutGoal = 4
            profile.updatedAt = .now
        }

        let existingFolders = try templateRepository.folders()
        let hasAnyTemplates = existingFolders.contains { !($0.templates ?? []).isEmpty }

        let catalogItems = try modelContext.fetch(
            FetchDescriptor<ExerciseCatalogItem>(
                sortBy: [SortDescriptor(\.displayName, order: .forward)]
            )
        )
        let itemsByUUID = Dictionary(
            catalogItems.map { ($0.remoteUUID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        if !hasAnyTemplates {
            for folderName in DemoSeedCatalog.folderNames where !existingFolders.contains(where: { $0.name.caseInsensitiveCompare(folderName) == .orderedSame }) {
                try templateRepository.createFolder(name: folderName)
            }

            try modelContext.save()

            let refreshedFolders = try templateRepository.folders()
            let foldersByName = Dictionary(
                refreshedFolders.map { ($0.name.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            )

            for seedTemplate in DemoSeedCatalog.templates {
                guard let folder = foldersByName[seedTemplate.folderName.lowercased()] else {
                    continue
                }

                let template = try templateRepository.createTemplate(
                    folderID: folder.id,
                    name: seedTemplate.name,
                    notes: seedTemplate.notes
                )

                var drafts: [TemplateExerciseDraft] = []
                for reference in seedTemplate.exercises {
                    if let matchByUUID = itemsByUUID[reference.uuid] {
                        drafts.append(TemplateExerciseDraft(catalogItem: matchByUUID))
                        continue
                    }

                    if let fallback = catalogItems.first(where: {
                        $0.displayName.caseInsensitiveCompare(reference.fallbackName) == .orderedSame
                    }) {
                        drafts.append(TemplateExerciseDraft(catalogItem: fallback))
                    }
                }

                try templateRepository.setExercises(templateID: template.id, drafts: drafts)
            }
        }

        try modelContext.save()
        try seedWorkoutHistoryIfEmpty(itemsByUUID: itemsByUUID)
        TemplateLibraryChangeBroadcaster.post()
        WorkoutHistoryChangeBroadcaster.post()
    }

    func resetLocalDevelopmentData() async throws {
        try await AppDataDeletionService(modelContext: modelContext).deleteLocalDeviceData()
        TemplateLibraryChangeBroadcaster.post()
        WorkoutHistoryChangeBroadcaster.post()
    }

    private func seedWorkoutHistoryIfEmpty(
        itemsByUUID: [String: ExerciseCatalogItem],
        now: Date = .now
    ) throws {
        let existingSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        guard !existingSessions.contains(where: { $0.status == .completed }) else { return }

        let calendar = Calendar.current
        var seededSessions: [WorkoutSession] = []

        for definition in DemoSeedCatalog.workouts {
            guard let completedAt = calendar.date(byAdding: .day, value: -definition.daysAgo, to: now) else {
                continue
            }
            let startedAt = completedAt.addingTimeInterval(-TimeInterval(definition.durationMinutes * 60))
            let session = WorkoutSession(
                name: definition.name,
                status: .completed,
                startedAt: startedAt,
                endedAt: completedAt,
                durationSeconds: definition.durationMinutes * 60,
                estimatedActiveCalories: definition.activeCalories,
                calorieEstimateVersion: WorkoutCalorieEstimator.currentVersion,
                notes: definition.note,
                createdAt: startedAt,
                updatedAt: completedAt
            )
            modelContext.insert(session)

            var sessionExercises: [WorkoutSessionExercise] = []
            for (exerciseIndex, exerciseDefinition) in definition.exercises.enumerated() {
                guard let catalogItem = itemsByUUID[exerciseDefinition.catalogUUID] else { continue }

                let exercise = WorkoutSessionExercise(
                    sessionID: session.id,
                    catalogExerciseUUID: catalogItem.remoteUUID,
                    exerciseNameSnapshot: catalogItem.displayName,
                    categorySnapshot: catalogItem.categoryName,
                    muscleSummarySnapshot: catalogItem.primaryMuscleNames,
                    targetRepMin: exerciseDefinition.sets.map(\.reps).min(),
                    targetRepMax: exerciseDefinition.sets.map(\.reps).max(),
                    totalSetCount: exerciseDefinition.sets.count,
                    completedSetCount: exerciseDefinition.sets.count,
                    sortOrder: exerciseIndex,
                    createdAt: startedAt,
                    updatedAt: completedAt,
                    session: session
                )
                modelContext.insert(exercise)

                let sets = exerciseDefinition.sets.enumerated().map { setIndex, definition in
                    let set = WorkoutSessionSet(
                        sessionExerciseID: exercise.id,
                        sortOrder: setIndex,
                        isWarmup: definition.isWarmup,
                        restSeconds: exerciseDefinition.restSeconds,
                        targetReps: definition.reps,
                        targetWeight: definition.weight,
                        targetLoadUnit: .kg,
                        actualReps: definition.reps,
                        actualWeight: definition.weight,
                        actualLoadUnit: .kg,
                        isCompleted: true,
                        isLocked: true,
                        createdAt: startedAt,
                        updatedAt: completedAt,
                        sessionExercise: exercise
                    )
                    modelContext.insert(set)
                    return set
                }
                exercise.sets = sets
                sessionExercises.append(exercise)
            }
            session.exercises = sessionExercises

            if definition.includesCardio, let bike = itemsByUUID["seed-bike"] {
                let cardio = WorkoutSessionCardioBlock(
                    sessionID: session.id,
                    phase: .postWorkout,
                    role: .finisher,
                    catalogExerciseUUID: bike.remoteUUID,
                    exerciseNameSnapshot: bike.displayName,
                    categorySnapshot: bike.categoryName,
                    muscleSummarySnapshot: bike.primaryMuscleNames,
                    trackingProfile: bike.cardioTrackingProfile,
                    goalKind: .time,
                    targetDurationSeconds: 600,
                    actualDurationSeconds: 600,
                    actualDistanceMeters: 4_200,
                    preferredDistanceUnit: .kilometers,
                    resistanceLevel: 7,
                    cardioNotes: "Strong finish.",
                    isCompleted: true,
                    createdAt: startedAt,
                    updatedAt: completedAt,
                    session: session
                )
                modelContext.insert(cardio)
                session.cardioBlocks = [cardio]
            }

            guard !sessionExercises.isEmpty else {
                modelContext.delete(session)
                continue
            }
            seededSessions.append(session)
        }

        try modelContext.save()

        let metricsService = WorkoutMetricsService(modelContext: modelContext)
        let projectionRepository = HistoryProjectionRepository(modelContext: modelContext)
        for session in seededSessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let projectedFacts = HistoryProjectionSnapshotBuilder.projectedFacts(from: session)
            let summary = try metricsService.sessionSummary(
                session: session,
                projectedFacts: projectedFacts
            )
            session.totalVolume = summary.totalVolume
            session.prHitsCount = summary.prHitsCount
            session.summaryMetricsVersion = WorkoutMetricsService.currentSummaryMetricsVersion
            _ = try projectionRepository.rebuildFacts(
                forSessionID: session.id,
                persistChanges: false
            )
            try modelContext.save()
        }

        HistoryAnalyticsCache.shared.invalidate(container: modelContext.container)
    }
}

nonisolated private struct DemoSeedExerciseReference {
    let uuid: String
    let fallbackName: String
}

nonisolated private struct DemoSeedTemplateDefinition {
    let folderName: String
    let name: String
    let notes: String
    let exercises: [DemoSeedExerciseReference]
}

nonisolated private struct DemoSeedSetDefinition {
    let weight: Double
    let reps: Int
    var isWarmup = false
}

nonisolated private struct DemoSeedWorkoutExerciseDefinition {
    let catalogUUID: String
    let restSeconds: Int
    let sets: [DemoSeedSetDefinition]
}

nonisolated private struct DemoSeedWorkoutDefinition {
    let daysAgo: Int
    let name: String
    let durationMinutes: Int
    let activeCalories: Int
    let note: String
    let includesCardio: Bool
    let exercises: [DemoSeedWorkoutExerciseDefinition]
}

nonisolated private enum DemoSeedCatalog {
    static let folderNames = ["Push", "Pull", "Legs"]

    static let templates: [DemoSeedTemplateDefinition] = [
        DemoSeedTemplateDefinition(
            folderName: "Push",
            name: "Push A",
            notes: "Chest, shoulders and triceps focus.",
            exercises: [
                .init(uuid: "seed-bench-press", fallbackName: "Barbell Bench Press"),
                .init(uuid: "seed-overhead-press", fallbackName: "Barbell Overhead Press"),
                .init(uuid: "seed-incline-dumbbell-press", fallbackName: "Incline Dumbbell Press"),
                .init(uuid: "seed-dips", fallbackName: "Parallel Bar Dips"),
            ]
        ),
        DemoSeedTemplateDefinition(
            folderName: "Pull",
            name: "Pull A",
            notes: "Back width and thickness.",
            exercises: [
                .init(uuid: "seed-deadlift", fallbackName: "Conventional Deadlift"),
                .init(uuid: "seed-bent-over-row", fallbackName: "Barbell Bent Over Row"),
                .init(uuid: "seed-pull-up", fallbackName: "Pull Up"),
                .init(uuid: "seed-lat-pulldown", fallbackName: "Lat Pulldown"),
            ]
        ),
        DemoSeedTemplateDefinition(
            folderName: "Legs",
            name: "Legs A",
            notes: "Lower body strength day.",
            exercises: [
                .init(uuid: "seed-back-squat", fallbackName: "Barbell Back Squat"),
                .init(uuid: "seed-leg-press", fallbackName: "Leg Press"),
                .init(uuid: "seed-dumbbell-lunge", fallbackName: "Dumbbell Walking Lunge"),
                .init(uuid: "seed-hanging-leg-raise", fallbackName: "Hanging Leg Raise"),
            ]
        ),
    ]

    static let workouts: [DemoSeedWorkoutDefinition] = [
        workout(daysAgo: 20, name: "Push Foundation", duration: 58, calories: 390, lifts: [
            ("seed-bench-press", [50, 55, 55], 10),
            ("seed-overhead-press", [30, 32.5, 32.5], 8),
            ("seed-incline-dumbbell-press", [20, 22, 22], 10),
        ]),
        workout(daysAgo: 16, name: "Pull Foundation", duration: 64, calories: 430, lifts: [
            ("seed-deadlift", [90, 100, 105], 5),
            ("seed-bent-over-row", [45, 50, 50], 8),
            ("seed-lat-pulldown", [45, 50, 50], 10),
        ]),
        workout(daysAgo: 12, name: "Leg Day", duration: 70, calories: 510, lifts: [
            ("seed-back-squat", [60, 65, 70], 8),
            ("seed-leg-press", [120, 140, 150], 10),
            ("seed-dumbbell-lunge", [16, 18, 18], 10),
        ]),
        workout(daysAgo: 8, name: "Push Power", duration: 61, calories: 420, lifts: [
            ("seed-bench-press", [60, 65, 70], 6),
            ("seed-overhead-press", [35, 37.5, 40], 6),
            ("seed-incline-dumbbell-press", [22, 24, 24], 8),
        ]),
        workout(daysAgo: 4, name: "Pull Strength", duration: 67, calories: 460, lifts: [
            ("seed-deadlift", [110, 120, 125], 4),
            ("seed-bent-over-row", [50, 55, 60], 6),
            ("seed-lat-pulldown", [50, 55, 60], 8),
        ]),
        workout(daysAgo: 1, name: "Full Body PR Day", duration: 76, calories: 560, includesCardio: true, lifts: [
            ("seed-back-squat", [70, 80, 85], 5),
            ("seed-bench-press", [70, 75, 80], 5),
            ("seed-deadlift", [120, 130, 140], 3),
        ]),
    ]

    private static func workout(
        daysAgo: Int,
        name: String,
        duration: Int,
        calories: Int,
        includesCardio: Bool = false,
        lifts: [(String, [Double], Int)]
    ) -> DemoSeedWorkoutDefinition {
        DemoSeedWorkoutDefinition(
            daysAgo: daysAgo,
            name: name,
            durationMinutes: duration,
            activeCalories: calories,
            note: "Simulator demo workout.",
            includesCardio: includesCardio,
            exercises: lifts.map { catalogUUID, weights, reps in
                DemoSeedWorkoutExerciseDefinition(
                    catalogUUID: catalogUUID,
                    restSeconds: 120,
                    sets: weights.enumerated().map { index, weight in
                        DemoSeedSetDefinition(weight: weight, reps: reps, isWarmup: index == 0)
                    }
                )
            }
        )
    }
}
#endif
