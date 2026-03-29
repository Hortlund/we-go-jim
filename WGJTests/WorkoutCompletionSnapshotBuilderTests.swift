import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct WorkoutCompletionSnapshotBuilderTests {
    @Test
    func snapshotCountsCompletedSetsAndBuildsExerciseRecap() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "summary-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)

        let session = try repository.createEmptySession(name: "Upper")
        try repository.addExercise(sessionID: session.id, catalogItem: bench)
        let sessionExercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        var drafts = try repository.setDrafts(sessionExerciseID: sessionExercise.id)
        drafts[0].actualWeight = 60
        drafts[0].actualReps = 10
        drafts[0].isCompleted = true
        drafts[1].actualWeight = 80
        drafts[1].actualReps = 8
        drafts[1].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: sessionExercise.id, drafts: drafts)
        try repository.finishSession(sessionID: session.id)

        let snapshot = try #require(
            try WorkoutCompletionSnapshotBuilder.build(sessionID: session.id, modelContext: context)
        )

        #expect(snapshot.exerciseCount == 1)
        #expect(snapshot.completedSetCount == 2)
        #expect(snapshot.exerciseRecap.count == 1)
        #expect(snapshot.exerciseRecap.first?.completedSetCount == 2)
        #expect(snapshot.exerciseRecap.first?.totalSetCount == 3)
        #expect(snapshot.exerciseRecap.first?.bestSetText == "80 kg x 8")
    }

    @Test
    func snapshotBuildsOnePersonalRecordCardPerExercise() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "summary-pr-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        let squat = ExerciseCatalogItem(
            remoteUUID: "summary-pr-squat",
            displayName: "Back Squat",
            categoryName: "Legs",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)
        context.insert(squat)

        let baseline = try repository.createEmptySession(name: "Baseline")
        try repository.addExercise(sessionID: baseline.id, catalogItem: bench)
        try repository.addExercise(sessionID: baseline.id, catalogItem: squat)
        let baselineExercises = try repository.sessionExercises(sessionID: baseline.id)

        if let baselineBench = baselineExercises.first(where: { $0.catalogExerciseUUID == bench.remoteUUID }) {
            var drafts = try repository.setDrafts(sessionExerciseID: baselineBench.id)
            drafts[0].actualWeight = 100
            drafts[0].actualReps = 5
            drafts[0].isCompleted = true
            try repository.saveSetDrafts(sessionExerciseID: baselineBench.id, drafts: drafts)
        }

        if let baselineSquat = baselineExercises.first(where: { $0.catalogExerciseUUID == squat.remoteUUID }) {
            var drafts = try repository.setDrafts(sessionExerciseID: baselineSquat.id)
            drafts[0].actualWeight = 130
            drafts[0].actualReps = 5
            drafts[0].isCompleted = true
            try repository.saveSetDrafts(sessionExerciseID: baselineSquat.id, drafts: drafts)
        }

        try repository.finishSession(sessionID: baseline.id)

        let current = try repository.createEmptySession(name: "PR Day")
        try repository.addExercise(sessionID: current.id, catalogItem: bench)
        try repository.addExercise(sessionID: current.id, catalogItem: squat)
        let currentExercises = try repository.sessionExercises(sessionID: current.id)

        if let currentBench = currentExercises.first(where: { $0.catalogExerciseUUID == bench.remoteUUID }) {
            var drafts = try repository.setDrafts(sessionExerciseID: currentBench.id)
            drafts[0].actualWeight = 102.5
            drafts[0].actualReps = 5
            drafts[0].isCompleted = true
            drafts[1].actualWeight = 90
            drafts[1].actualReps = 10
            drafts[1].isCompleted = true
            try repository.saveSetDrafts(sessionExerciseID: currentBench.id, drafts: drafts)
        }

        if let currentSquat = currentExercises.first(where: { $0.catalogExerciseUUID == squat.remoteUUID }) {
            var drafts = try repository.setDrafts(sessionExerciseID: currentSquat.id)
            drafts[0].actualWeight = 140
            drafts[0].actualReps = 5
            drafts[0].isCompleted = true
            drafts[1].actualWeight = 120
            drafts[1].actualReps = 8
            drafts[1].isCompleted = true
            try repository.saveSetDrafts(sessionExerciseID: currentSquat.id, drafts: drafts)
        }

        try repository.finishSession(sessionID: current.id)

        let snapshot = try #require(
            try WorkoutCompletionSnapshotBuilder.build(sessionID: current.id, modelContext: context)
        )
        let recordsByExercise = Dictionary(
            uniqueKeysWithValues: snapshot.personalRecords.map { ($0.exerciseName, $0) }
        )

        #expect(snapshot.personalRecords.count == 2)
        #expect(snapshot.prHeadline == "2 new PRs today")
        #expect(recordsByExercise["Bench Press"]?.performanceText == "90 kg x 10")
        #expect(recordsByExercise["Back Squat"]?.performanceText == "140 kg x 5")
    }

    @Test
    func snapshotBuildsNoPRFallbackCopy() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "summary-no-pr-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)

        let baseline = try repository.createEmptySession(name: "Heavy Day")
        try repository.addExercise(sessionID: baseline.id, catalogItem: bench)
        let baselineExercise = try #require(try repository.sessionExercises(sessionID: baseline.id).first)
        var baselineDrafts = try repository.setDrafts(sessionExerciseID: baselineExercise.id)
        baselineDrafts[0].actualWeight = 110
        baselineDrafts[0].actualReps = 5
        baselineDrafts[0].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: baselineExercise.id, drafts: baselineDrafts)
        try repository.finishSession(sessionID: baseline.id)

        let current = try repository.createEmptySession(name: "Medium Day")
        try repository.addExercise(sessionID: current.id, catalogItem: bench)
        let currentExercise = try #require(try repository.sessionExercises(sessionID: current.id).first)
        var currentDrafts = try repository.setDrafts(sessionExerciseID: currentExercise.id)
        currentDrafts[0].actualWeight = 100
        currentDrafts[0].actualReps = 5
        currentDrafts[0].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: currentExercise.id, drafts: currentDrafts)
        try repository.finishSession(sessionID: current.id)

        let snapshot = try #require(
            try WorkoutCompletionSnapshotBuilder.build(sessionID: current.id, modelContext: context)
        )

        #expect(snapshot.personalRecords.isEmpty)
        #expect(snapshot.prHeadline == "No new PRs today")
        #expect(snapshot.prSupportText.contains("completed sets"))
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
            UserProfile.self,
            ProfileWidgetConfig.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            TemplateExerciseSet.self,
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            SocialOutboxItem.self,
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
