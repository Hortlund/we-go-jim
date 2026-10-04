import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class ExerciseDetailProgressServiceTests: XCTestCase {
    func testCardioProgressReadsDistancePreferenceWithoutCreatingProfileOrWriting() throws {
        let context = try makeContext()
        let session = WorkoutSession(name: "Run", status: .completed, endedAt: .now)
        context.insert(session)
        context.insert(WorkoutSessionCardioBlock(sessionID: session.id, phase: .postWorkout,
            catalogExerciseUUID: "seed-outdoor-run", exerciseNameSnapshot: "Outdoor Run", categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs", targetDurationSeconds: 0, actualDurationSeconds: 600,
            actualDistanceMeters: 1609.344, isCompleted: true, session: session))
        let profile = UserProfile(displayName: "Athlete")
        profile.preferredDistanceUnit = .miles
        context.insert(profile)
        try context.saveWithRecoveryProtection()
        let service = WorkoutMetricsService(modelContext: context)
        let miles = try XCTUnwrap(service.exerciseProgressDataset(for: "seed-outdoor-run"))
        XCTAssertEqual(miles.preferredDistanceUnit, .miles)
        XCTAssertEqual(miles.sessions.first?.distanceMeters, 1609.344)
        XCTAssertFalse(context.hasChanges)
        context.delete(profile)
        try context.saveWithRecoveryProtection()
        let fallback = try XCTUnwrap(service.exerciseProgressDataset(for: "seed-outdoor-run"))
        XCTAssertEqual(fallback.preferredDistanceUnit, .regionalDefault(locale: .current))
        XCTAssertNil(try ProfileRepository(modelContext: context).currentProfile())
        XCTAssertFalse(context.hasChanges)
    }

    func testDatasetIncludesCompleteWorkingSetTotalsAndNormalizedLoads() throws {
        let context = try makeContext()
        let completedAt = Date(timeIntervalSince1970: 10_000)
        let sessionID = UUID()
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Upper",
            status: .completed,
            startedAt: completedAt.addingTimeInterval(-3_600),
            endedAt: completedAt,
            durationSeconds: 3_600,
            totalVolume: 1_250,
            prHitsCount: 0,
            summaryMetricsVersion: WorkoutMetricsService.currentSummaryMetricsVersion,
            createdAt: completedAt,
            updatedAt: completedAt
        ))
        context.insert(fact(sessionID: sessionID, completedAt: completedAt, index: 0, reps: 8, weight: 100, volume: 800))
        context.insert(fact(sessionID: sessionID, completedAt: completedAt, index: 1, reps: 5, weight: 90, volume: 450))
        context.insert(fact(sessionID: sessionID, completedAt: completedAt, index: 2, reps: 10, weight: 40, volume: 400, isWarmup: true))
        try context.save()
        HistoryAnalyticsCache.shared.invalidate(container: context.container)

        let dataset = try XCTUnwrap(
            WorkoutMetricsService(modelContext: context).exerciseProgressDataset(
                for: "bench-press",
                preferredExerciseName: "Bench Press"
            )
        )
        let result = try XCTUnwrap(dataset.sessions.first)

        XCTAssertEqual(result.completedSetCount, 2)
        XCTAssertEqual(result.totalReps, 13)
        XCTAssertEqual(try XCTUnwrap(result.heaviestWeightKilograms), 100, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.sessionVolumeKilograms), 1_250, accuracy: 0.001)
        XCTAssertFalse(context.hasChanges)
    }

    func testUnknownExerciseReturnsNilWithoutMutatingContext() throws {
        let context = try makeContext()
        XCTAssertNil(try WorkoutMetricsService(modelContext: context).exerciseProgressDataset(
            for: "missing",
            preferredExerciseName: "Missing"
        ))
        XCTAssertFalse(context.hasChanges)
    }

    func testRepsOnlyHistoryWorksForEveryLoadUnitAndLaterAddedWeight() throws {
        for unit in [TemplateLoadUnit.kg, .lb, .bodyweight] {
            let context = try makeContext()
            let bodyweight = insertSession(in: context, day: 1, unit: unit, weights: [nil, 0], reps: [8, 6])
            try context.save()
            let service = WorkoutMetricsService(modelContext: context)
            let initial = try XCTUnwrap(service.exerciseProgressDataset(for: "pull-up"))
            XCTAssertEqual(initial.sessions.count, 1)
            XCTAssertEqual(initial.sessions.first?.totalReps, 14)
            XCTAssertEqual(initial.sessions.first?.completedSetCount, 2)
            XCTAssertNil(initial.sessions.first?.estimatedOneRepMaxKilograms)
            XCTAssertNil(initial.sessions.first?.sessionVolumeKilograms)
            let initialProjection = project(initial, metric: .bestSetReps)
            XCTAssertEqual(initialProjection.points.map(\.value), [8])
            XCTAssertEqual(initialProjection.milestones.count, 1)
            XCTAssertFalse(context.hasChanges)

            let addedUnit: TemplateLoadUnit = unit == .lb ? .lb : .kg
            let weighted = insertSession(in: context, day: 2, unit: addedUnit, weights: [10], reps: [5])
            // A bodyweight prescription may later be performed with added weight.
            weighted.exercises?.first?.sets?.first?.targetLoadUnit = .bodyweight
            try context.save()
            HistoryAnalyticsCache.shared.invalidate(container: context.container)
            let combined = try XCTUnwrap(service.exerciseProgressDataset(for: "pull-up"))
            XCTAssertEqual(combined.sessions.map(\.sessionID), [bodyweight.id, weighted.id])
            XCTAssertEqual(project(combined, metric: .totalReps).points.map(\.value), [14, 5])
            XCTAssertEqual(project(combined, metric: .bestSetReps).points.map(\.value), [8, 5])
            XCTAssertEqual(project(combined, metric: .totalReps).summary?.totalSets, 3)
            let kilograms = WorkoutPerformanceMath.normalizedLoadInKilograms(10, unit: addedUnit)
            XCTAssertEqual(try XCTUnwrap(combined.sessions.last?.heaviestWeightKilograms), kilograms, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(combined.sessions.last?.sessionVolumeKilograms), kilograms * 5, accuracy: 0.001)
            XCTAssertEqual(project(combined, metric: .heaviestWeight).points.count, 1)
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testExistingPartialHistoryRecoversRepsWithoutWritingAndBackfillIsIdempotent() throws {
        let context = try makeContext()
        let session = insertSession(in: context, day: 1, unit: .kg, weights: [nil, 0, 10], reps: [8, 6, 5])
        // Simulate the previous projection: current version/timestamps, but only weighted facts.
        let drafts = HistoryProjectionSnapshotBuilder.projectedFacts(from: session)
        for draft in drafts where draft.normalizedWeightKg != nil {
            context.insert(draft.makeModel())
        }
        try context.save()
        let repository = HistoryProjectionRepository(modelContext: context)
        XCTAssertEqual(try repository.facts(forSessionID: session.id).count, 1)
        let dataset = try XCTUnwrap(WorkoutMetricsService(modelContext: context).exerciseProgressDataset(for: "pull-up"))
        XCTAssertEqual(dataset.sessions.first?.completedSetCount, 3)
        XCTAssertEqual(dataset.sessions.first?.totalReps, 19)
        XCTAssertEqual(dataset.sessions.first?.sessionVolumeKilograms, 50)
        XCTAssertEqual(try repository.facts(forSessionID: session.id).count, 1)
        XCTAssertFalse(context.hasChanges)

        XCTAssertEqual(try repository.backfillIfNeeded(), 1)
        XCTAssertEqual(try repository.facts(forSessionID: session.id).count, 3)
        XCTAssertEqual(try repository.backfillIfNeeded(), 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testVersionThreeSummariesMigrateRepsPRsAndRemainStableOnSecondPass() throws {
        let context = try makeContext()
        let first = insertSession(in: context, day: 1, unit: .kg, weights: [nil, 0], reps: [8, 6])
        let later = insertSession(in: context, day: 2, unit: .bodyweight, weights: [nil], reps: [7])
        // Version 3 omitted the first workout's reps and treated the later set as a PR.
        first.summaryMetricsVersion = 3
        first.prHitsCount = 0
        later.summaryMetricsVersion = 3
        later.prHitsCount = 1
        for draft in HistoryProjectionSnapshotBuilder.projectedFacts(from: later) {
            context.insert(draft.makeModel())
        }
        try context.save()

        let repository = WorkoutSessionRepository(modelContext: context)
        XCTAssertTrue(try repository.hasStaleCompletedSessionSummaries())
        XCTAssertEqual(try repository.backfillCompletedSessionSummariesIfNeeded(), 2)
        XCTAssertEqual(first.prHitsCount, 1)
        XCTAssertEqual(later.prHitsCount, 0)
        XCTAssertEqual(first.summaryMetricsVersion, WorkoutMetricsService.currentSummaryMetricsVersion)
        XCTAssertEqual(later.summaryMetricsVersion, WorkoutMetricsService.currentSummaryMetricsVersion)
        XCTAssertEqual(first.totalVolume, 0)
        XCTAssertEqual(later.totalVolume, 0)
        XCTAssertFalse(context.hasChanges)

        XCTAssertFalse(try repository.hasStaleCompletedSessionSummaries())
        XCTAssertEqual(try repository.backfillCompletedSessionSummariesIfNeeded(), 0)
        XCTAssertEqual(first.prHitsCount, 1)
        XCTAssertEqual(later.prHitsCount, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testRepsOnlyHistoryExcludesUnfinishedZeroRepAndWarmupSets() throws {
        let context = try makeContext()
        let session = insertSession(in: context, day: 1, unit: .kg, weights: [nil, nil, 0, nil], reps: [8, 20, 0, 30])
        let sets = try XCTUnwrap(session.exercises?.first?.sets).sorted { $0.sortOrder < $1.sortOrder }
        sets[1].isCompleted = false
        sets[3].isWarmup = true
        try context.save()
        let dataset = try XCTUnwrap(WorkoutMetricsService(modelContext: context).exerciseProgressDataset(for: "pull-up"))
        XCTAssertEqual(dataset.sessions.first?.completedSetCount, 1)
        XCTAssertEqual(dataset.sessions.first?.totalReps, 8)
        XCTAssertFalse(context.hasChanges)
    }

    func testRepContextUsesTheActualHighestRepSetAndNormalizesLoads() throws {
        let context = try makeContext()
        insertSession(in: context, day: 1, unit: .lb, weights: [nil, 20, 40], reps: [12, 12, 6])
        insertSession(in: context, day: 2, unit: .kg, weights: [30], reps: [5])
        try context.save()
        let service = WorkoutMetricsService(modelContext: context)
        let dataset = try XCTUnwrap(service.exerciseProgressDataset(for: "pull-up"))
        let first = try XCTUnwrap(dataset.sessions.first?.loadContext)
        XCTAssertEqual(first.bestRepsSet.reps, 12)
        XCTAssertEqual(first.bestRepsSet.kilograms, 20 * 0.45359237, accuracy: 0.001)
        XCTAssertEqual(first.heaviestSet.reps, 6)
        XCTAssertEqual(first.heaviestSet.kilograms, 40 * 0.45359237, accuracy: 0.001)
        XCTAssertEqual(first.minimumKilograms, 0)
        let projection = project(dataset, metric: .bestSetReps)
        XCTAssertEqual(projection.points.map(\.value), [12, 5])
        XCTAssertNotNil(projection.comparisonNote)
        XCTAssertEqual(projection.points.first?.performance, first.bestRepsSet)
        XCTAssertEqual(projection.milestones.first?.context, projection.points.first?.context)
        let trend = try service.exerciseMetricTrend(for: "pull-up", metric: .maxReps)
        XCTAssertEqual(trend.points.first?.performance, first.bestRepsSet)
        XCTAssertEqual(trend.comparisonText(for: .maxReps), projection.comparisonNote)
        XCTAssertFalse(context.hasChanges)
    }

    func testAddedWeightHistorySuppressesMisleadingTotalLoadEstimateAndKeepsOneHistory() throws {
        let context = try makeContext()
        context.insert(ExerciseCatalogItem(remoteUUID: "pull-up", displayName: "Pull Up", equipmentSummary: "Pull-up bar"))
        let first = insertSession(in: context, day: 1, unit: .bodyweight, weights: [nil], reps: [10])
        let second = insertSession(in: context, day: 2, unit: .kg, weights: [10], reps: [6])
        try context.save()
        let service = WorkoutMetricsService(modelContext: context)
        for projected in [false, true] {
            if projected {
                let repository = HistoryProjectionRepository(modelContext: context)
                for session in [first, second] { _ = try repository.rebuildFacts(forSessionID: session.id) }
            }
            let dataset = try XCTUnwrap(service.exerciseProgressDataset(for: "pull-up"))
            XCTAssertTrue(dataset.usesAddedWeight)
            XCTAssertEqual(dataset.preferredMetric, .bestSetReps)
            XCTAssertEqual(dataset.sessions.count, 2)
            let reps = project(dataset, metric: .bestSetReps)
            XCTAssertEqual(reps.points.map(\.context), ["10 reps", "10 kg × 6 reps"])
            XCTAssertNotNil(reps.comparisonNote)
            XCTAssertFalse(project(dataset, metric: .estimatedOneRepMax).availability.isAvailable)
            XCTAssertTrue(project(dataset, metric: .estimatedOneRepMax).points.isEmpty)
            let trend = try service.exerciseMetricTrend(for: "pull-up", metric: .maxReps)
            XCTAssertTrue(trend.usesAddedWeight)
            XCTAssertEqual(trend.points.map(\.context), reps.points.map(\.context))
            XCTAssertTrue(try service.exerciseMetricTrend(for: "pull-up", metric: .oneRepMax).points.isEmpty)
            let option = try XCTUnwrap(service.exerciseHistoryOptions(metric: .oneRepMax).first)
            XCTAssertEqual(option.trendMetric, .maxReps)
            XCTAssertFalse(option.availableTrendMetrics.contains(.oneRepMax))
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testVersionFiveSummaryRebuildsSetContextWithoutChangingLoggedData() throws {
        let context = try makeContext()
        let session = insertSession(in: context, day: 1, unit: .kg, weights: [nil, 10], reps: [12, 6])
        try context.save()
        let repository = HistoryProjectionRepository(modelContext: context)
        _ = try repository.rebuildFacts(forSessionID: session.id)
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<ExerciseSessionSummary>()).first)
        var oldEntry = try JSONDecoder().decode(CompletedExerciseHistoryEntry.self, from: row.payload)
        oldEntry.loadContext = nil
        row.payload = try BackupArchiveCodec.json(oldEntry)
        session.projectionVersion = 5
        try context.save()
        let service = WorkoutMetricsService(modelContext: context)
        let before = try XCTUnwrap(service.exerciseProgressDataset(for: "pull-up"))
        XCTAssertEqual(before.sessions.first?.loadContext?.bestRepsSet, .init(reps: 12, kilograms: 0))
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try repository.backfillIfNeeded(), 1)
        let after = try XCTUnwrap(service.exerciseProgressDataset(for: "pull-up"))
        XCTAssertEqual(before, after)
        XCTAssertEqual(session.projectionVersion, HistoryProjectionRepository.currentVersion)
        XCTAssertEqual(try repository.backfillIfNeeded(), 0)
        XCTAssertEqual(session.exercises?.first?.sets?.count, 2)
        XCTAssertFalse(context.hasChanges)
    }

    func testSameLoadRepComparisonAndUnknownEquipmentRemainConservative() throws {
        let context = try makeContext()
        insertSession(in: context, day: 1, unit: .kg, weights: [20], reps: [10])
        insertSession(in: context, day: 2, unit: .kg, weights: [20], reps: [12])
        try context.save()
        let service = WorkoutMetricsService(modelContext: context)
        let dataset = try XCTUnwrap(service.exerciseProgressDataset(for: "pull-up"))
        XCTAssertFalse(dataset.usesAddedWeight)
        XCTAssertNil(project(dataset, metric: .bestSetReps).comparisonNote)
        XCTAssertTrue(project(dataset, metric: .estimatedOneRepMax).availability.isAvailable)
        XCTAssertTrue(try service.exerciseMetricTrend(for: "pull-up", metric: .maxReps)
            .comparisonText(for: .maxReps)?.contains("same logged load") == true)
        XCTAssertTrue(ExerciseLoadSemantics.usesAddedWeight(equipment: "Bodyweight"))
        XCTAssertTrue(ExerciseLoadSemantics.usesAddedWeight(equipment: "Dip station"))
        XCTAssertFalse(ExerciseLoadSemantics.usesAddedWeight(equipment: "Assisted pull-up machine"))
        XCTAssertFalse(ExerciseLoadSemantics.usesAddedWeight(equipment: "Barbell"))
        XCTAssertFalse(context.hasChanges)
    }

    func testAddedWeightRulesReachRecordsHistoryCompletionAndComparison() throws {
        let context = try makeContext()
        context.insert(ExerciseCatalogItem(remoteUUID: "pull-up", displayName: "Pull Up", equipmentSummary: "Pull-up bar"))
        let bodyweight = insertSession(in: context, day: 1, unit: .bodyweight, weights: [nil], reps: [40])
        let volume = insertSession(in: context, day: 2, unit: .kg, weights: [10], reps: [20])
        let heaviest = insertSession(in: context, day: 3, unit: .kg, weights: [15], reps: [1])
        let later = insertSession(in: context, day: 4, unit: .kg, weights: [14], reps: [10])
        try context.save()
        let service = WorkoutMetricsService(modelContext: context)
        // External-load Epley would award strength here, despite no new weight, reps or volume record.
        XCTAssertTrue(try service.sessionSetPRAchievements(sessionID: later.id).isEmpty)
        XCTAssertTrue(try service.sessionPRAchievements(sessionID: later.id).isEmpty)
        XCTAssertNil(try service.bestEstimatedOneRepMax(for: "pull-up"))
        let record = try XCTUnwrap(service.personalRecords().first)
        XCTAssertEqual(record.weight, 15)
        XCTAssertEqual(record.reps, 1)
        XCTAssertTrue(record.usesAddedWeight)
        XCTAssertNil(record.estimatedOneRepMax)
        let history = try HistoryDetailSnapshotBuilder.load(modelContext: context, sessionID: heaviest.id)
        XCTAssertTrue(history.exercises.first?.usesAddedWeight == true)
        XCTAssertEqual(history.personalRecordHighlights.first?.performanceText, "15 kg × 1 rep")
        XCTAssertFalse(history.personalRecordHighlights.contains { $0.kinds.contains(.strength) })
        let recap = try XCTUnwrap(WorkoutCompletionSnapshotBuilder.build(sessionID: heaviest.id, modelContext: context))
        XCTAssertEqual(recap.exerciseRecap.first?.bestSetText, "15 kg × 1 rep")
        let rows = try HistorySessionSummaryBuilder.rows(for: try WorkoutSessionRepository(modelContext: context)
            .sessionExercises(sessionID: heaviest.id), cardioBlocks: [], repository: WorkoutSessionRepository(modelContext: context))
        XCTAssertEqual(rows.first?.bestSet, "15 kg × 1 rep")
        let comparison = try WorkoutProgressSnapshotLoader.load(modelContext: context,
            selectedPreviousSessionID: bodyweight.id, selectedCurrentSessionID: volume.id)
        guard case let .ready(result) = comparison.state else { return XCTFail("Expected comparison") }
        XCTAssertEqual(result.exerciseComparisons.first?.direction, .flat)
        XCTAssertTrue(result.exerciseComparisons.first?.deltaText.contains("Added weight changed") == true)
        XCTAssertEqual(result.exerciseComparisons.first?.previousBestSetText, "40 reps")
        XCTAssertEqual(result.exerciseComparisons.first?.currentBestSetText, "10 kg × 20 reps")
        for session in [bodyweight, volume, heaviest, later] {
            _ = try HistoryProjectionRepository(modelContext: context).rebuildFacts(forSessionID: session.id)
            session.summaryMetricsVersion = 5
        }
        later.prHitsCount = 1
        try context.save()
        _ = try WorkoutSessionRepository(modelContext: context).backfillCompletedSessionSummariesIfNeeded()
        XCTAssertEqual(later.prHitsCount, 0)
        XCTAssertEqual(later.summaryMetricsVersion, WorkoutMetricsService.currentSummaryMetricsVersion)
        XCTAssertEqual(try service.countPRHits(sessionID: later.id), later.prHitsCount)
        XCTAssertFalse(context.hasChanges)
    }

    func testActiveSetFeedbackDoesNotTreatChangedLoadAsRepRegression() throws {
        for previousUnit in [TemplateLoadUnit.kg, .bodyweight] {
            let reference = try XCTUnwrap(WorkoutSetProgressReference.make(
                draft: WorkoutSessionSetDraft(actualReps: 6, actualWeight: 10, actualLoadUnit: .kg),
                previous: .init(reps: 10, weight: nil, unit: previousUnit), targetRepMin: nil, targetRepMax: nil))
            XCTAssertEqual(reference.statusTone, .accent)
            XCTAssertTrue(reference.statusText?.contains("Load changed") == true)
        }
        let equivalent = try XCTUnwrap(WorkoutSetProgressReference.make(
            draft: WorkoutSessionSetDraft(actualReps: 8, actualWeight: 20 / 0.45359237, actualLoadUnit: .lb),
            previous: .init(reps: 6, weight: 20, unit: .kg), targetRepMin: nil, targetRepMax: nil))
        XCTAssertEqual(equivalent.statusTone, .success)
        XCTAssertEqual(equivalent.statusText, "+2 reps vs last")
    }

    func testAddedWeightComparisonNormalizesEquivalentLoadsAcrossUnits() throws {
        let context = try makeContext()
        context.insert(ExerciseCatalogItem(remoteUUID: "pull-up", displayName: "Pull Up", equipmentSummary: "Pull-up bar"))
        let first = insertSession(in: context, day: 1, unit: .kg, weights: [10], reps: [6])
        let second = insertSession(in: context, day: 2, unit: .lb, weights: [10 / 0.45359237], reps: [8])
        try context.save()
        let comparison = try WorkoutProgressSnapshotLoader.load(modelContext: context,
            selectedPreviousSessionID: first.id, selectedCurrentSessionID: second.id)
        guard case let .ready(result) = comparison.state else { return XCTFail("Expected comparison") }
        XCTAssertEqual(result.exerciseComparisons.first?.direction, .up)
        XCTAssertEqual(result.exerciseComparisons.first?.deltaText, "+2 reps at the same added weight")
        XCTAssertFalse(context.hasChanges)
    }

    func testBundledBodyweightVariantsShareLoadSemanticsWithoutClassifyingOrdinaryLifts() throws {
        let seed = try BundleExerciseSeedLoader().loadSeed()
        let expectedIDs: Set<String> = [
            "seed-pull-up", "seed-chin-up", "seed-neutral-grip-pull-up", "seed-weighted-pull-up",
            "seed-dips", "seed-weighted-dip", "seed-chest-dip", "seed-bench-dip",
            "seed-push-up", "seed-weighted-push-up", "seed-ring-push-up", "seed-inverted-row",
            "seed-weighted-crunch", "seed-decline-sit-up", "seed-45-degree-back-extension"
        ]
        XCTAssertEqual(seed.exercises.filter { expectedIDs.contains($0.uuid) }.count, expectedIDs.count)
        for exercise in seed.exercises {
            let addedWeight = ExerciseLoadSemantics.usesAddedWeight(
                equipment: exercise.equipmentSummary, exerciseName: exercise.name)
            if expectedIDs.contains(exercise.uuid) {
                XCTAssertTrue(addedWeight, exercise.name)
            }
            if exercise.equipmentSummary.lowercased().contains("machine")
                || ["seed-bench-press", "seed-back-squat", "seed-lat-pulldown", "seed-rack-pull", "seed-plate-front-raise"].contains(exercise.uuid) {
                XCTAssertFalse(addedWeight, exercise.name)
            }
        }
        XCTAssertTrue(ExerciseLoadSemantics.usesAddedWeight(equipment: " Dip Belt, DIP STATION "))
        XCTAssertTrue(ExerciseLoadSemantics.usesAddedWeight(equipment: "Pull-Up Bar, Weight Belt"))
        XCTAssertFalse(ExerciseLoadSemantics.usesAddedWeight(equipment: "Pull-up bar,Band", exerciseName: "Band Assisted Pull Up"))
        XCTAssertFalse(ExerciseLoadSemantics.usesAddedWeight(equipment: "Bench", exerciseName: "Bench Press"))
        XCTAssertFalse(ExerciseLoadSemantics.usesAddedWeight(equipment: "Unknown", exerciseName: "Custom Lift"))
    }

    func testCatalogVariantsKeepSeparateHistoriesAndShareAddedWeightPresentation() throws {
        let context = try makeContext()
        let seed = try BundleExerciseSeedLoader().loadSeed()
        let ids: Set<String> = [
            "seed-pull-up", "seed-neutral-grip-pull-up", "seed-chin-up", "seed-weighted-pull-up",
            "seed-dips", "seed-weighted-dip", "seed-chest-dip", "seed-bench-dip",
            "seed-ring-push-up", "seed-inverted-row"
        ]
        let variants = seed.exercises.filter { ids.contains($0.uuid) }
        var latestSessions: [String: WorkoutSession] = [:]
        for variant in variants {
            context.insert(ExerciseCatalogItem(remoteUUID: variant.uuid, displayName: variant.name,
                equipmentSummary: variant.equipmentSummary))
            insertSession(in: context, day: 1, unit: .bodyweight, weights: [nil], reps: [10],
                exerciseID: variant.uuid, exerciseName: variant.name)
            latestSessions[variant.uuid] = insertSession(in: context, day: 2, unit: .kg, weights: [10], reps: [6],
                exerciseID: variant.uuid, exerciseName: variant.name)
            let snapshot = TrainingGuidanceCatalogSnapshot(exerciseName: variant.name, categoryName: variant.categoryName,
                equipmentSummary: variant.equipmentSummary, primaryMuscleNames: "")
            XCTAssertTrue(snapshot.usesAddedWeight, variant.name)
        }
        try context.saveWithRecoveryProtection()
        let service = WorkoutMetricsService(modelContext: context)
        let records = try service.personalRecords(limit: 50)
        XCTAssertEqual(records.count, variants.count)
        for variant in variants {
            let dataset = try XCTUnwrap(service.exerciseProgressDataset(for: variant.uuid))
            XCTAssertEqual(dataset.sessions.count, 2, "Variations must not merge histories")
            XCTAssertTrue(dataset.usesAddedWeight, variant.name)
            XCTAssertEqual(project(dataset, metric: .bestSetReps).points.map(\.context),
                ["10 reps", "10 kg × 6 reps"], variant.name)
            XCTAssertFalse(project(dataset, metric: .estimatedOneRepMax).availability.isAvailable)
            let trend = try service.exerciseMetricTrend(for: variant.uuid, metric: .maxReps)
            XCTAssertEqual(trend.points.last?.context, "10 kg × 6 reps", variant.name)
            XCTAssertTrue(try service.exerciseMetricTrend(for: variant.uuid, metric: .oneRepMax).points.isEmpty)
            let record = try XCTUnwrap(records.first { $0.catalogExerciseUUID == variant.uuid })
            XCTAssertTrue(record.usesAddedWeight)
            XCTAssertNil(record.estimatedOneRepMax)
            let session = try XCTUnwrap(latestSessions[variant.uuid])
            let detail = try HistoryDetailSnapshotBuilder.load(modelContext: context, sessionID: session.id)
            XCTAssertTrue(detail.exercises.first?.usesAddedWeight == true)
            let recap = try XCTUnwrap(WorkoutCompletionSnapshotBuilder.build(sessionID: session.id, modelContext: context))
            XCTAssertEqual(recap.exerciseRecap.first?.bestSetText, "10 kg × 6 reps", variant.name)
        }
        XCTAssertFalse(context.hasChanges)
    }

    func testAssistanceDoesNotRewardEasierSetsOrCountSupportAsLiftedVolume() throws {
        let context = try makeContext()
        context.insert(ExerciseCatalogItem(remoteUUID: "pull-up", displayName: "Assisted Pull Up", equipmentSummary: "Machine"))
        let first = insertSession(in: context, day: 1, unit: .kg, weights: [40], reps: [8])
        let easier = insertSession(in: context, day: 2, unit: .kg, weights: [50], reps: [12])
        let harder = insertSession(in: context, day: 3, unit: .kg, weights: [30], reps: [8])
        let moreReps = insertSession(in: context, day: 4, unit: .lb, weights: [30 / 0.45359237], reps: [10])
        let unassisted = insertSession(in: context, day: 5, unit: .kg, weights: [0], reps: [6])
        let unknown = insertSession(in: context, day: 6, unit: .kg, weights: [nil], reps: [20])
        try context.saveWithRecoveryProtection()
        let service = WorkoutMetricsService(modelContext: context)
        XCTAssertTrue(try service.sessionSetPRAchievements(sessionID: easier.id).isEmpty)
        let lessAssistance = try XCTUnwrap(service.sessionSetPRAchievements(sessionID: harder.id).first)
        XCTAssertEqual(lessAssistance.kinds, [.assistance])
        XCTAssertEqual(lessAssistance.performanceText, "8 reps · 30 kg assistance")
        XCTAssertEqual(lessAssistance.detailText, "Least Assistance PR")
        XCTAssertEqual(try service.sessionSetPRAchievements(sessionID: moreReps.id).first?.kinds, [.assistedReps])
        XCTAssertTrue(try service.sessionSetPRAchievements(sessionID: unknown.id).isEmpty)
        XCTAssertEqual(try service.totalVolume(sessionID: first.id), 0)
        XCTAssertNil(try service.bestEstimatedOneRepMax(for: "pull-up"))
        let dataset = try XCTUnwrap(service.exerciseProgressDataset(for: "pull-up"))
        XCTAssertTrue(dataset.usesAssistance)
        XCTAssertEqual(dataset.preferredMetric, .bestSetReps)
        for metric in [ExerciseProgressMetric.estimatedOneRepMax, .sessionVolume, .heaviestWeight] {
            XCTAssertFalse(project(dataset, metric: metric).availability.isAvailable)
        }
        let points = project(dataset, metric: .bestSetReps).points
        XCTAssertEqual(points.count, 5, "An unknown assistance must not imply an unassisted set")
        XCTAssertEqual(points.first?.context, ExerciseSetPerformance(reps: 8, kilograms: 40).label(unit: dataset.preferredLoadUnit, addedWeight: false, assistance: true))
        XCTAssertEqual(points.last?.context, "6 reps · No assistance")
        let options = try service.exerciseHistoryOptions(metric: .oneRepMax)
        XCTAssertEqual(options.first?.availableTrendMetrics, [.maxReps])
        for metric in [ProfileExerciseTrendMetric.oneRepMax, .maxWeight, .volume] {
            XCTAssertTrue(try service.exerciseMetricTrend(for: "pull-up", metric: metric).points.isEmpty)
        }
        let record = try XCTUnwrap(service.personalRecords().first)
        XCTAssertTrue(record.usesAssistance)
        XCTAssertEqual(record.weight, 0)
        XCTAssertEqual(record.reps, 6)
        let history = try HistoryDetailSnapshotBuilder.load(modelContext: context, sessionID: harder.id)
        XCTAssertTrue(history.exercises.first?.usesAssistance == true)
        let recap = try XCTUnwrap(WorkoutCompletionSnapshotBuilder.build(sessionID: harder.id, modelContext: context))
        XCTAssertEqual(recap.exerciseRecap.first?.bestSetText, "8 reps · 30 kg assistance")
        let comparison = try WorkoutProgressSnapshotLoader.load(modelContext: context,
            selectedPreviousSessionID: first.id, selectedCurrentSessionID: harder.id)
        guard case let .ready(result) = comparison.state else { return XCTFail("Expected comparison") }
        XCTAssertEqual(result.exerciseComparisons.first?.direction, .up)
        XCTAssertEqual(result.exerciseComparisons.first?.deltaText, "Less assistance with the same or more reps")
        for session in [first, easier, harder, moreReps, unassisted, unknown] {
            session.totalVolume = 999
            session.prHitsCount = 99
            session.summaryMetricsVersion = 6
        }
        try context.saveWithRecoveryProtection()
        _ = try WorkoutSessionRepository(modelContext: context).backfillCompletedSessionSummariesIfNeeded()
        XCTAssertEqual(easier.prHitsCount, 0)
        XCTAssertEqual(moreReps.prHitsCount, 1)
        XCTAssertEqual(unknown.prHitsCount, 0)
        XCTAssertEqual(first.totalVolume, 0)
        XCTAssertEqual(easier.totalVolume, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testAssistanceTotalRepsShowsLoadRangeAndUnknownAssistanceStaysUnknown() throws {
        let context = try makeContext()
        context.insert(ExerciseCatalogItem(remoteUUID: "pull-up", displayName: "Assisted Pull Up", equipmentSummary: "Machine"))
        insertSession(in: context, day: 1, unit: .kg, weights: [nil], reps: [20])
        try context.saveWithRecoveryProtection()
        let service = WorkoutMetricsService(modelContext: context)
        let unknownDataset = try XCTUnwrap(service.exerciseProgressDataset(for: "pull-up"))
        let availability = ExerciseProgressProjector.availabilityByMetric(dataset: unknownDataset, range: .allTime,
            now: Date(timeIntervalSince1970: 1_000_000), calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(availability[.bestSetReps]?.isAvailable, false)
        XCTAssertEqual(project(unknownDataset, metric: .totalReps).points.first?.context, "Assistance not recorded")

        insertSession(in: context, day: 2, unit: .kg, weights: [40, 30, nil], reps: [12, 8, 20])
        try context.saveWithRecoveryProtection()
        HistoryAnalyticsCache.shared.invalidate(container: context.container)
        let dataset = try XCTUnwrap(service.exerciseProgressDataset(for: "pull-up"))
        let point = try XCTUnwrap(project(dataset, metric: .totalReps).points.last)
        XCTAssertEqual(point.value, 40)
        XCTAssertEqual(point.context, "30 kg assistance – 40 kg assistance")
        XCTAssertNil(point.performance, "A session total must not claim to represent one set")
    }

    func testRepeatedAssistedExerciseKeepsKnownLoadInComparison() throws {
        for unknownFirst in [false, true] {
            let context = try makeContext()
            context.insert(ExerciseCatalogItem(remoteUUID: "pull-up", displayName: "Assisted Pull Up", equipmentSummary: "Machine"))
            let previous = insertSession(in: context, day: 1, unit: .kg, weights: [40], reps: [8])
            let current = insertSession(in: context, day: 2, unit: .kg,
                weights: [unknownFirst ? nil : 30], reps: [unknownFirst ? 20 : 8])
            let duplicate = WorkoutSessionExercise(sessionID: current.id,
                catalogExerciseUUID: "pull-up", exerciseNameSnapshot: "Assisted Pull Up",
                categorySnapshot: "Back", muscleSummarySnapshot: "Back", sortOrder: 1, session: current)
            context.insert(duplicate)
            context.insert(WorkoutSessionSet(sessionExerciseID: duplicate.id, sortOrder: 0,
                targetLoadUnit: .kg, actualReps: unknownFirst ? 8 : 20,
                actualWeight: unknownFirst ? 30 : nil, actualLoadUnit: .kg,
                isCompleted: true, sessionExercise: duplicate))
            try context.saveWithRecoveryProtection()
            let snapshot = try WorkoutProgressSnapshotLoader.load(modelContext: context,
                selectedPreviousSessionID: previous.id, selectedCurrentSessionID: current.id)
            guard case let .ready(result) = snapshot.state else { return XCTFail("Expected comparison") }
            XCTAssertEqual(result.exerciseComparisons.first?.direction, .up)
            XCTAssertEqual(result.exerciseComparisons.first?.deltaText, "Less assistance with the same or more reps")
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testAssistanceInlineFeedbackAndGuidanceNeverSuggestHeavierAssistanceAsProgress() throws {
        let previous = WorkoutPreviousSetSnapshot(reps: 8, weight: 40, unit: .kg)
        let easier = try XCTUnwrap(WorkoutSetProgressReference.make(usesAssistance: true,
            draft: .init(actualReps: 12, actualWeight: 50, actualLoadUnit: .kg), previous: previous,
            targetRepMin: 6, targetRepMax: 10))
        XCTAssertEqual(easier.statusTone, .accent)
        XCTAssertTrue(easier.statusText?.contains("More assistance") == true)
        let harder = try XCTUnwrap(WorkoutSetProgressReference.make(usesAssistance: true,
            draft: .init(actualReps: 8, actualWeight: 30, actualLoadUnit: .kg), previous: previous,
            targetRepMin: 6, targetRepMax: 10))
        XCTAssertEqual(harder.statusTone, .success)
        XCTAssertEqual(harder.aimValue, "Compare reps at the same assistance")
        XCTAssertEqual(ExerciseLoadSemantics.kind(equipment: "Machine", exerciseName: "Assisted Pull Up"), .assistance)
        XCTAssertEqual(ExerciseLoadSemantics.kind(equipment: "Machine", exerciseName: "Machine Dip"), .resistance)
        XCTAssertEqual(ExerciseLoadSemantics.kind(equipment: "Machine", exerciseName: "Custom", override: "addedWeight"), .addedWeight)
    }

    func testCustomLoadTypeSurvivesBackupAndLegacyPayloadStillDecodes() throws {
        let exercise = ExerciseCatalogItem(remoteUUID: "custom-one", displayName: "Custom Movement", loadTrackingRaw: "assistance", sourceName: "custom")
        let payload = BackupCustomExercise(exercise)
        let data = try JSONEncoder().encode(payload)
        let restored = try JSONDecoder().decode(BackupCustomExercise.self, from: data).model
        XCTAssertEqual(restored.loadKind, .assistance)
        XCTAssertEqual(CustomExerciseDraft(exercise: restored).loadTrackingRaw, "assistance")
        XCTAssertEqual(ExerciseCatalogSelection(catalogItem: restored).loadTrackingRaw, "assistance")
        XCTAssertEqual(ExerciseCatalogItemSnapshot(exercise: restored).selection.loadTrackingRaw, "assistance")
        XCTAssertNil(TemplateLoadUnit.inferredDefault(fromEquipmentSummary: "Bodyweight", loadTrackingRaw: "assistance"))
        XCTAssertNil(TemplateLoadUnit.inferredDefault(fromEquipmentSummary: "Bodyweight", loadTrackingRaw: "resistance"))
        XCTAssertEqual(TemplateLoadUnit.inferredDefault(fromEquipmentSummary: "", loadTrackingRaw: "addedWeight"), .bodyweight)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "loadTrackingRaw")
        let old = try JSONDecoder().decode(BackupCustomExercise.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.loadTrackingRaw)
        XCTAssertEqual(old.model.loadKind, .resistance)
    }

    func testChangingCustomLoadTypeRebuildsHistoricalTotalsAtTheSaveBoundary() throws {
        let context = try makeContext()
        context.insert(MuscleGroup(remoteID: 1, name: "Back", nameEn: "Back"))
        let repository = ExerciseCatalogRepository(modelContext: context, boundaryEffects: .init { _, _ in })
        var draft = CustomExerciseDraft(name: "Custom Pull", categoryName: "Back", equipmentSummary: "Machine",
            aliases: [], primaryMuscleIDs: [1], secondaryMuscleIDs: [], instructionText: "")
        draft.loadTrackingRaw = "resistance"
        let exercise = try repository.createCustomExercise(draft: draft)
        let session = insertSession(in: context, day: 1, unit: .kg, weights: [40], reps: [8],
            exerciseID: exercise.remoteUUID, exerciseName: exercise.displayName)
        try context.saveWithRecoveryProtection()
        _ = try WorkoutSessionRepository(modelContext: context).backfillCompletedSessionSummariesIfNeeded()
        XCTAssertEqual(session.totalVolume, 320)
        draft.loadTrackingRaw = "assistance"
        try repository.updateCustomExercise(exercise, draft: draft)
        XCTAssertEqual(exercise.loadKind, .assistance)
        XCTAssertEqual(session.totalVolume, 0)
        XCTAssertTrue(try WorkoutMetricsService(modelContext: context).exerciseProgressDataset(for: exercise.remoteUUID)?.usesAssistance == true)
        XCTAssertFalse(context.hasChanges)
        let updatedAt = exercise.updatedAt
        try repository.updateCustomExercise(exercise, draft: draft)
        XCTAssertEqual(exercise.updatedAt, updatedAt)
        XCTAssertFalse(context.hasChanges)
    }

    func testWeeklyCoachExcludesAssistanceFromVolumeAndExerciseSignals() throws {
        let context = try makeContext()
        context.insert(ExerciseCatalogItem(remoteUUID: "assisted", displayName: "Assisted Pull Up", equipmentSummary: "Machine"))
        for week in 0..<7 {
            insertSession(in: context, day: 3 + week * 7, unit: .kg, weights: [week == 6 ? 80 : 40], reps: [8],
                exerciseID: "assisted", exerciseName: "Assisted Pull Up")
            insertSession(in: context, day: 3 + week * 7, unit: .kg, weights: [100], reps: [8],
                exerciseID: "bench", exerciseName: "Bench Press")
        }
        try context.saveWithRecoveryProtection()
        _ = try WorkoutSessionRepository(modelContext: context).backfillCompletedSessionSummariesIfNeeded()
        let result = try WeeklyCoachInsightService(modelContext: context, calendar: Calendar(identifier: .iso8601))
            .weeklyInsightSnapshot(asOf: Date(timeIntervalSince1970: 45 * 86_400 + 100))
        XCTAssertEqual(result.baselineWeekCount, 6)
        XCTAssertEqual(result.totalVolumeDelta, 0)
        XCTAssertFalse((result.topRisingSignals + result.topWatchSignals).contains { $0.catalogExerciseUUID == "assisted" })
        XCTAssertFalse(context.hasChanges)
    }

    func testUnassistedNamesDoNotInvertLoadMeaning() {
        for name in ["Unassisted Pull Up", "UNASSISTED DIPS", "Unassisted (neutral-grip) pull-up"] {
            XCTAssertEqual(ExerciseLoadSemantics.kind(equipment: "Bodyweight", exerciseName: name), .addedWeight)
            XCTAssertTrue(ExerciseLoadSemantics.usesAddedWeight(equipment: "Pull-up bar", exerciseName: name))
        }
        for name in ["Assisted Pull Up", "Band-assisted dip", "Pull Up (assisted)"] {
            XCTAssertEqual(ExerciseLoadSemantics.kind(equipment: "Bodyweight", exerciseName: name), .assistance)
        }
        XCTAssertEqual(ExerciseLoadSemantics.kind(equipment: "Assisted Dip Machine", exerciseName: "Dip"), .assistance)
    }

    func testAssistanceTrendPagesPastUnknownLoadsBeforeApplyingLimit() throws {
        let context = try makeContext()
        context.insert(ExerciseCatalogItem(remoteUUID: "pull-up", displayName: "Assisted Pull Up", equipmentSummary: "Machine"))
        for day in 1...42 {
            insertSession(in: context, day: day, unit: .kg, weights: [day <= 8 ? 30 : nil], reps: [day <= 8 ? day : 20])
        }
        try context.saveWithRecoveryProtection()
        let service = WorkoutMetricsService(modelContext: context)
        for projected in [false, true] {
            if projected { _ = try HistoryProjectionRepository(modelContext: context).backfillIfNeeded() }
            let trend = try service.exerciseMetricTrend(for: "pull-up", metric: .maxReps, limit: 3)
            XCTAssertEqual(trend.points.map(\.value), [6, 7, 8])
            XCTAssertTrue(trend.points.allSatisfy { $0.context?.contains("30 kg assistance") == true })
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testUnknownAssistanceDoesNotAdvertiseAnEmptyProfileMetric() throws {
        let context = try makeContext()
        context.insert(ExerciseCatalogItem(remoteUUID: "pull-up", displayName: "Assisted Pull Up", equipmentSummary: "Machine"))
        insertSession(in: context, day: 1, unit: .kg, weights: [nil], reps: [12])
        try context.saveWithRecoveryProtection()
        XCTAssertTrue(try WorkoutMetricsService(modelContext: context).exerciseHistoryOptions().isEmpty)
    }

    func testDeletedCustomExerciseKeepsLoadMeaningThroughBackupRestore() throws {
        for kind in [ExerciseLoadKind.assistance, .addedWeight] {
            let context = try makeContext()
            let exercise = ExerciseCatalogItem(remoteUUID: "pull-up", displayName: "Custom Pull",
                equipmentSummary: "Machine", loadTrackingRaw: kind.rawValue, sourceName: "custom")
            context.insert(exercise)
            let session = insertSession(in: context, day: 1, unit: .kg, weights: [30], reps: [8])
            try context.saveWithRecoveryProtection()
            _ = try WorkoutSessionRepository(modelContext: context).backfillCompletedSessionSummariesIfNeeded()
            let service = WorkoutMetricsService(modelContext: context)
            let expectedVolume = try service.totalVolume(sessionID: session.id)
            let expectedRecords = try service.personalRecords()
            let repository = ExerciseCatalogRepository(modelContext: context, boundaryEffects: .init { _, _ in })
            try repository.deleteCustomExercise(exercise)
            HistoryAnalyticsCache.shared.invalidate(container: context.container)
            XCTAssertTrue(exercise.isHidden)
            var picker = ExercisesCatalogSnapshot.empty
            picker.rebuild(from: try repository.allExercises(), muscleGroups: [])
            XCTAssertTrue(picker.searchDocuments.isEmpty)
            XCTAssertEqual(try service.totalVolume(sessionID: session.id), expectedVolume)
            XCTAssertEqual(try service.personalRecords(), expectedRecords)
            let history = try HistoryDetailSnapshotBuilder.load(modelContext: context, sessionID: session.id)
            XCTAssertEqual(history.exercises.first?.usesAssistance, kind == .assistance)
            XCTAssertEqual(history.exercises.first?.usesAddedWeight, kind == .addedWeight)

            let data = try JSONEncoder().encode(UserDataCloudBackupPayload(context: context))
            let payload = try JSONDecoder().decode(UserDataCloudBackupPayload.self, from: data)
            try payload.validate()
            let restored = try makeContext()
            try UserDataCloudRestoreTransaction(container: restored.container).commit(
                replacingLocalData: true, replacementPayload: payload,
                mergeDatabaseGraph: { try payload.mergeDatabaseGraph(into: $0) },
                relinkRelationships: { try payload.relinkRelationships(in: $0) })
            let restoredService = WorkoutMetricsService(modelContext: restored)
            XCTAssertEqual(try restoredService.totalVolume(sessionID: session.id), expectedVolume)
            XCTAssertEqual(try restoredService.personalRecords(), expectedRecords)
            let savedExercise = try XCTUnwrap(restored.fetch(FetchDescriptor<ExerciseCatalogItem>()).first)
            XCTAssertTrue(savedExercise.isHidden)
            XCTAssertEqual(savedExercise.loadKind, kind)
            XCTAssertFalse(restored.hasChanges)
        }
    }

    func testDeletingCustomExerciseRetainsAnActiveRotationAlternativeAfterTemplateDeletion() throws {
        for kind in [ExerciseLoadKind.assistance, .addedWeight] {
            let context = try makeContext()
            let primary = ExerciseCatalogItem(remoteUUID: "primary", displayName: "Primary Pull", sourceName: "custom")
            let alternative = ExerciseCatalogItem(remoteUUID: "alternative", displayName: "Custom Pull",
                equipmentSummary: "Machine", loadTrackingRaw: kind.rawValue, sourceName: "custom")
            context.insert(primary)
            context.insert(alternative)
            let templates = TemplateRepository(modelContext: context)
            let template = try templates.createTemplate(name: "Rotation", notes: "")
            var draft = TemplateExerciseDraft(selection: ExerciseCatalogSelection(catalogItem: primary), preferredLoadUnit: .kg)
            draft.components = [TemplateExerciseComponentDraft(catalogItem: primary), TemplateExerciseComponentDraft(catalogItem: alternative)]
            try templates.importExercises(templateID: template.id, drafts: [draft])
            let active = ActiveWorkoutDraftRepository(modelContext: context)
            let session = try active.createSessionFromTemplate(templateID: template.id)
            let row = try XCTUnwrap(active.sessionExercises(sessionID: session.id).first)
            XCTAssertEqual(row.catalogExerciseUUID, primary.remoteUUID)
            let component = try XCTUnwrap(active.components(sessionExerciseID: row.id).first { $0.catalogExerciseUUID == alternative.remoteUUID })
            let rowID = row.id
            let componentID = component.id
            try templates.deleteTemplate(id: template.id)
            try ExerciseCatalogRepository(modelContext: context, boundaryEffects: .init { _, _ in }).deleteCustomExercise(alternative)

            // Resume through another context so cached catalog objects cannot hide deletion.
            let resumedContext = ModelContext(context.container)
            resumedContext.autosaveEnabled = false
            let retained = try XCTUnwrap(ExerciseCatalogRepository(modelContext: resumedContext)
                .exerciseMap(for: ["alternative"])["alternative"])
            XCTAssertTrue(retained.isHidden)
            XCTAssertEqual(retained.loadKind, kind)
            let resumed = ActiveWorkoutDraftRepository(modelContext: resumedContext)
            try resumed.overrideExerciseComponent(sessionExerciseID: rowID, componentID: componentID)
            let selected = try XCTUnwrap(resumed.sessionExercises(sessionID: session.id).first)
            XCTAssertEqual(selected.catalogExerciseUUID, "alternative")
            let snapshot = try XCTUnwrap(ExerciseCatalogRepository(modelContext: resumedContext)
                .exerciseSnapshotMap(for: [selected.catalogExerciseUUID])[selected.catalogExerciseUUID])
            XCTAssertEqual(snapshot.loadKind, kind)
            XCTAssertFalse(resumedContext.hasChanges)
        }
    }

    func testRecreatingDeletedCustomNameKeepsHistorySeparateAndRejectsVisibleDuplicates() throws {
        let context = try makeContext()
        context.insert(MuscleGroup(remoteID: 1, name: "Back", nameEn: "Back"))
        let repository = ExerciseCatalogRepository(modelContext: context, boundaryEffects: .init { _, _ in })
        var draft = CustomExerciseDraft(name: "Custom Pull", categoryName: "Back", equipmentSummary: "Machine",
            aliases: [], primaryMuscleIDs: [1], secondaryMuscleIDs: [], instructionText: "")
        draft.loadTrackingRaw = "assistance"
        let original = try repository.createCustomExercise(draft: draft)
        let session = insertSession(in: context, day: 1, unit: .kg, weights: [30], reps: [8],
            exerciseID: original.remoteUUID, exerciseName: original.displayName)
        try context.saveWithRecoveryProtection()
        try repository.deleteCustomExercise(original)

        draft.name = "custom pull"
        draft.loadTrackingRaw = "resistance"
        let replacement = try repository.createCustomExercise(draft: draft)
        XCTAssertNotEqual(original.remoteUUID, replacement.remoteUUID)
        XCTAssertTrue(original.isHidden)
        XCTAssertFalse(replacement.isHidden)
        XCTAssertEqual(original.loadKind, .assistance)
        XCTAssertEqual(replacement.loadKind, .resistance)
        let service = WorkoutMetricsService(modelContext: context)
        XCTAssertEqual(try service.totalVolume(sessionID: session.id), 0)
        XCTAssertTrue(try service.exerciseProgressDataset(for: original.remoteUUID)?.usesAssistance == true)
        XCTAssertNil(try service.exerciseProgressDataset(for: replacement.remoteUUID))
        var picker = ExercisesCatalogSnapshot.empty
        picker.rebuild(from: try repository.allExercises(), muscleGroups: [])
        XCTAssertEqual(picker.searchDocuments.map(\.id), [replacement.remoteUUID])
        XCTAssertEqual(try repository.exactImportMatch(remoteUUID: "", exerciseName: "Custom Pull",
            categoryName: "Back")?.remoteUUID, replacement.remoteUUID)
        XCTAssertEqual(try repository.exactImportMatch(remoteUUID: original.remoteUUID, exerciseName: "Custom Pull",
            categoryName: "Back")?.remoteUUID, original.remoteUUID)

        draft.name = "CUSTOM PULL"
        XCTAssertThrowsError(try repository.createCustomExercise(draft: draft)) { error in
            XCTAssertEqual(error as? ExerciseCatalogRepositoryError, .duplicateName)
        }
        XCTAssertFalse(context.hasChanges)
    }

    private func project(_ dataset: ExerciseProgressDataset, metric: ExerciseProgressMetric) -> ExerciseProgressProjection {
        ExerciseProgressProjector.project(
            dataset: dataset, metric: metric, range: .allTime,
            now: Date(timeIntervalSince1970: 1_000_000), calendar: Calendar(identifier: .gregorian)
        )
    }

    @discardableResult
    private func insertSession(
        in context: ModelContext, day: Int, unit: TemplateLoadUnit, weights: [Double?], reps: [Int],
        exerciseID: String = "pull-up", exerciseName: String = "Pull Up"
    ) -> WorkoutSession {
        let date = Date(timeIntervalSince1970: Double(day) * 86_400)
        let session = WorkoutSession(
            name: "Pull", status: .completed, startedAt: date, endedAt: date,
            summaryMetricsVersion: WorkoutMetricsService.currentSummaryMetricsVersion,
            createdAt: date, updatedAt: date
        )
        context.insert(session)
        let exercise = WorkoutSessionExercise(
            sessionID: session.id, catalogExerciseUUID: exerciseID, exerciseNameSnapshot: exerciseName,
            categorySnapshot: "Back", muscleSummarySnapshot: "Back",
            createdAt: date, updatedAt: date, session: session
        )
        context.insert(exercise)
        for (index, weight) in weights.enumerated() {
            context.insert(WorkoutSessionSet(
                sessionExerciseID: exercise.id, sortOrder: index, targetLoadUnit: unit,
                actualReps: reps[index], actualWeight: weight, actualLoadUnit: unit,
                isCompleted: true, createdAt: date, updatedAt: date, sessionExercise: exercise
            ))
        }
        return session
    }

    private func makeContext() throws -> ModelContext {
        let container = try AppSchema.makeInMemoryContainer(
            name: "ExerciseDetailProgressServiceTests-\(UUID().uuidString)"
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        HistoryAnalyticsCache.shared.invalidate(container: container)
        return context
    }

    private func fact(
        sessionID: UUID,
        completedAt: Date,
        index: Int,
        reps: Int,
        weight: Double,
        volume: Double,
        isWarmup: Bool = false
    ) -> CompletedSetFact {
        CompletedSetFact(
            sessionSetID: UUID(),
            sessionID: sessionID,
            sessionExerciseID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            completedAt: completedAt,
            setIndex: index,
            isWarmup: isWarmup,
            reps: reps,
            weight: weight,
            loadUnit: .kg,
            normalizedWeightKg: weight,
            estimatedOneRepMaxKg: WorkoutPerformanceMath.estimatedOneRepMax(weight: weight, reps: reps),
            volumeKg: volume,
            sourceSessionUpdatedAt: completedAt
        )
    }
}
