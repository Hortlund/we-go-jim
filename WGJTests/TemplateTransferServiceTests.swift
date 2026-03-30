import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct TemplateTransferServiceTests {
    @Test
    func exportImportRoundTripPreservesTemplateContent() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        try repository.createFolder(name: "Push")
        let folder = try #require(try repository.folders().first)
        let template = try repository.createTemplate(
            folderID: folder.id,
            name: "Push Prime",
            notes: "Heavy top sets and a backoff."
        )

        try repository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: "bench-1",
                    exerciseNameSnapshot: "Bench Press",
                    categorySnapshot: "Chest",
                    muscleSummarySnapshot: "Chest, Triceps",
                    targetRepMin: 4,
                    targetRepMax: 6,
                    restSeconds: 180,
                    setDrafts: [
                        TemplateExerciseSetDraft(
                            targetReps: 6,
                            targetWeight: 100,
                            loadUnit: .kg,
                            restSeconds: 180,
                            isWarmup: true
                        ),
                        TemplateExerciseSetDraft(
                            targetReps: 4,
                            targetWeight: 115,
                            loadUnit: .kg,
                            restSeconds: 180,
                            isLocked: true
                        ),
                    ]
                ),
                TemplateExerciseDraft(
                    catalogExerciseUUID: "dip-1",
                    exerciseNameSnapshot: "Weighted Dip",
                    categorySnapshot: "Chest",
                    muscleSummarySnapshot: "Chest, Triceps",
                    targetRepMin: 8,
                    targetRepMax: 10,
                    restSeconds: 120,
                    setDrafts: [
                        TemplateExerciseSetDraft(
                            targetReps: 10,
                            targetWeight: 20,
                            loadUnit: .kg,
                            restSeconds: 120
                        ),
                    ]
                ),
            ]
        )

        let exportedData = try service.exportData(templateID: template.id)
        let importedTemplate = try service.importTemplate(from: exportedData)
        let importedExercises = try repository.exercises(in: importedTemplate.id)
        let benchSets = try repository.setDrafts(for: try #require(importedExercises.first).id)
        let dipSets = try repository.setDrafts(for: try #require(importedExercises.last).id)

        #expect(importedTemplate.folderID == TemplateRepository.unfiledFolderID)
        #expect(importedTemplate.name == "Push Prime")
        #expect(importedTemplate.notes == "Heavy top sets and a backoff.")
        #expect(importedExercises.map(\.exerciseNameSnapshot) == ["Bench Press", "Weighted Dip"])
        #expect(importedExercises.map(\.targetRepMin) == [4, 8])
        #expect(importedExercises.map(\.targetRepMax) == [6, 10])
        #expect(importedExercises.map(\.restSeconds) == [180, 120])
        #expect(benchSets.count == 2)
        #expect(benchSets[0].targetReps == 6)
        #expect(benchSets[0].targetWeight == 100)
        #expect(benchSets[0].isWarmup)
        #expect(benchSets[1].targetReps == 4)
        #expect(benchSets[1].targetWeight == 115)
        #expect(benchSets[1].isLocked)
        #expect(dipSets.count == 1)
        #expect(dipSets[0].targetWeight == 20)
        #expect(dipSets[0].restSeconds == 120)
    }

    @Test
    func importCreatesFreshCopyInUnfiledAndKeepsSourceUntouched() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        let template = try repository.createTemplate(
            name: "Upper Builder",
            notes: "Original notes"
        )
        try repository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: "row-1",
                    exerciseNameSnapshot: "Chest Supported Row",
                    categorySnapshot: "Back",
                    muscleSummarySnapshot: "Lats",
                    targetRepMin: 8,
                    targetRepMax: 12,
                    restSeconds: 90,
                    setDrafts: [
                        TemplateExerciseSetDraft(
                            targetReps: 10,
                            targetWeight: 70,
                            loadUnit: .kg,
                            restSeconds: 90
                        ),
                    ]
                ),
            ]
        )

        let sourceExerciseIDs = Set(try repository.exercises(in: template.id).map(\.id))
        let sourceSetIDs = try Set(
            repository.exercises(in: template.id)
                .flatMap { try repository.setDrafts(for: $0.id).map(\.id) }
        )

        let importedTemplate = try service.importTemplate(from: try service.exportData(templateID: template.id))
        let importedExercises = try repository.exercises(in: importedTemplate.id)
        let importedSetIDs = try Set(
            importedExercises.flatMap { try repository.setDrafts(for: $0.id).map(\.id) }
        )
        let storedSource = try #require(try repository.template(id: template.id))

        #expect(importedTemplate.id != template.id)
        #expect(importedTemplate.folderID == TemplateRepository.unfiledFolderID)
        #expect(importedTemplate.name == "Upper Builder Copy")
        #expect(importedTemplate.notes == "Original notes")
        #expect(sourceExerciseIDs.isDisjoint(with: Set(importedExercises.map(\.id))))
        #expect(sourceSetIDs.isDisjoint(with: importedSetIDs))
        #expect(storedSource.name == "Upper Builder")
        #expect(storedSource.notes == "Original notes")
    }

    @Test
    func importedTemplateCanStartWorkoutWithoutCatalogMatch() throws {
        let context = try makeInMemoryContext()
        let service = TemplateTransferService(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)

        let importedTemplate = try service.importTemplate(
            from: try encoded(
                TemplateTransferEnvelope(
                    template: TemplateTransferTemplate(
                        name: "Garage Strongman",
                        notes: "Imported from a friend.",
                        exercises: [
                            TemplateTransferExercise(
                                catalogExerciseUUID: "missing-catalog-uuid",
                                exerciseNameSnapshot: "Sandbag Carry",
                                categorySnapshot: "Conditioning",
                                muscleSummarySnapshot: "Full Body",
                                targetRepMin: 2,
                                targetRepMax: 3,
                                restSeconds: 150,
                                sets: [
                                    TemplateTransferSet(
                                        targetReps: 3,
                                        targetWeight: nil,
                                        loadUnit: .bodyweight,
                                        restSeconds: 150,
                                        isWarmup: false,
                                        isLocked: false
                                    ),
                                ]
                            ),
                        ]
                    )
                )
            )
        )

        let session = try sessionRepository.createSessionFromTemplate(templateID: importedTemplate.id)
        let sessionExercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)

        #expect(sessionExercise.catalogExerciseUUID == "missing-catalog-uuid")
        #expect(sessionExercise.exerciseNameSnapshot == "Sandbag Carry")
        #expect(sessionExercise.categorySnapshot == "Conditioning")
    }

    @Test
    func importRejectsMalformedFile() throws {
        let context = try makeInMemoryContext()
        let service = TemplateTransferService(modelContext: context)

        #expect(throws: TemplateTransferError.self) {
            try service.importTemplate(from: Data("not valid json".utf8))
        }
    }

    @Test
    func importRejectsUnsupportedFormatVersion() throws {
        let context = try makeInMemoryContext()
        let service = TemplateTransferService(modelContext: context)
        let unsupportedData = try encoded(
            TemplateTransferEnvelope(
                formatVersion: 99,
                template: TemplateTransferTemplate(
                    name: "Unsupported",
                    notes: "",
                    exercises: []
                )
            )
        )

        do {
            _ = try service.importTemplate(from: unsupportedData)
            Issue.record("Expected import to reject unsupported version")
        } catch let error as TemplateTransferError {
            #expect(error == .unsupportedVersion(99))
        } catch {
            Issue.record("Expected TemplateTransferError.unsupportedVersion, got \(error)")
        }
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

    private func encoded(_ envelope: TemplateTransferEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }
}
