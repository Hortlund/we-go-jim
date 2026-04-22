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
        try repository.setCardioBlocks(
            templateID: template.id,
            drafts: [
                TemplateCardioBlockDraft(
                    phase: .preWorkout,
                    catalogExerciseUUID: "bike-1",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
                TemplateCardioBlockDraft(
                    phase: .postWorkout,
                    catalogExerciseUUID: "treadmill-1",
                    exerciseNameSnapshot: "Incline Treadmill Walk",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Cooldown",
                    targetDurationSeconds: 1200
                ),
            ]
        )

        try repository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: "bench-1",
                    exerciseNameSnapshot: "WGJ Export Press",
                    categorySnapshot: "WGJ Test Chest",
                    muscleSummarySnapshot: "WGJ Test Muscles",
                    notes: "Pause the first rep and keep shoulders pinned.",
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
                    notes: "Lean slightly forward and stay smooth at lockout.",
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
        let importedCardio = try repository.cardioBlocks(templateID: importedTemplate.id)
        let importedExercises = try repository.exercises(in: importedTemplate.id)
        let benchSets = try repository.setDrafts(for: try #require(importedExercises.first).id)
        let dipSets = try repository.setDrafts(for: try #require(importedExercises.last).id)

        #expect(importedTemplate.folderID == TemplateRepository.unfiledFolderID)
        #expect(importedTemplate.name == "Push Prime")
        #expect(importedTemplate.notes == "Heavy top sets and a backoff.")
        #expect(importedCardio.map(\.phase) == [.preWorkout, .postWorkout])
        #expect(importedCardio.map(\.exerciseNameSnapshot) == ["Bike", "Incline Treadmill Walk"])
        #expect(importedCardio.map(\.targetDurationSeconds) == [300, 1200])
        #expect(importedExercises.map(\.exerciseNameSnapshot) == ["WGJ Export Press", "Weighted Dip"])
        #expect(importedExercises.map(\.notes) == [
            "Pause the first rep and keep shoulders pinned.",
            "Lean slightly forward and stay smooth at lockout.",
        ])
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
    func exportImportRoundTripPreservesSupersetAndDropsetStructure() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        let supersetID = UUID()
        let template = try repository.createTemplate(name: "Push Pull", notes: "Pair the main work.")
        try repository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: "transfer-superset-incline-press",
                    exerciseNameSnapshot: "Incline DB Press",
                    categorySnapshot: "Chest",
                    muscleSummarySnapshot: "Chest, Front Delts",
                    targetRepMin: 8,
                    targetRepMax: 10,
                    restSeconds: 60,
                    setDrafts: [
                        TemplateExerciseSetDraft(
                            targetReps: 10,
                            targetWeight: 28,
                            loadUnit: .kg,
                            restSeconds: 60,
                            dropStages: [
                                TemplateExerciseDropStageDraft(targetReps: 8, targetWeight: 22, loadUnit: .kg),
                                TemplateExerciseDropStageDraft(targetReps: 10, targetWeight: 18, loadUnit: .kg),
                            ]
                        ),
                    ],
                    superset: ExerciseSupersetMembershipDraft(
                        groupID: supersetID,
                        position: .first,
                        roundRestSeconds: 75
                    )
                ),
                TemplateExerciseDraft(
                    catalogExerciseUUID: "transfer-superset-supported-row",
                    exerciseNameSnapshot: "Chest Supported Row",
                    categorySnapshot: "Back",
                    muscleSummarySnapshot: "Lats, Upper Back",
                    targetRepMin: 8,
                    targetRepMax: 12,
                    restSeconds: 60,
                    setDrafts: [
                        TemplateExerciseSetDraft(
                            targetReps: 12,
                            targetWeight: 55,
                            loadUnit: .kg,
                            restSeconds: 60
                        ),
                    ],
                    superset: ExerciseSupersetMembershipDraft(
                        groupID: supersetID,
                        position: .second,
                        roundRestSeconds: 75
                    )
                ),
            ]
        )

        let importedTemplate = try service.importTemplate(from: try service.exportData(templateID: template.id))
        let importedExercises = try repository.exercises(in: importedTemplate.id)
        let firstExercise = try #require(importedExercises.first)
        let secondExercise = try #require(importedExercises.last)
        let firstSetDrafts = try repository.setDrafts(for: firstExercise.id)

        #expect(firstExercise.supersetGroupID == secondExercise.supersetGroupID)
        #expect(firstExercise.supersetPosition == .first)
        #expect(secondExercise.supersetPosition == .second)
        #expect(firstExercise.supersetGroup?.roundRestSeconds == 75)
        #expect(firstSetDrafts[0].dropStages.map(\.targetWeight) == [22, 18])
        #expect(firstSetDrafts[0].dropStages.map(\.targetReps) == [8, 10])
    }

    @Test
    func exportTemplateBundleUsesVersionSixArtifactEnvelope() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        let reverseCurl = ExerciseCatalogItem(
            remoteUUID: "transfer-reverse-curl",
            displayName: "Reverse Curl",
            categoryName: "Arms",
            equipmentSummary: "EZ bar",
            isCurated: true,
            sourceName: "custom"
        )
        let wristCurl = ExerciseCatalogItem(
            remoteUUID: "transfer-wrist-curl",
            displayName: "Wrist Curl",
            categoryName: "Arms",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "custom"
        )
        context.insert(reverseCurl)
        context.insert(wristCurl)

        let template = try repository.createTemplate(name: "Forearms", notes: "Rotate the curl variation.")
        try repository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: reverseCurl.remoteUUID,
                    exerciseNameSnapshot: reverseCurl.displayName,
                    categorySnapshot: reverseCurl.categoryName,
                    muscleSummarySnapshot: reverseCurl.primaryMuscleNames,
                    targetRepMin: 10,
                    targetRepMax: 12,
                    restSeconds: 60,
                    setDrafts: [
                        TemplateExerciseSetDraft(targetReps: 12, targetWeight: 20, loadUnit: .kg, restSeconds: 60),
                    ],
                    components: [
                        TemplateExerciseComponentDraft(catalogItem: reverseCurl),
                        TemplateExerciseComponentDraft(catalogItem: wristCurl),
                    ]
                ),
            ]
        )

        let exportedData = try service.exportData(templateID: template.id, format: .bundle)
        let json = try #require(try JSONSerialization.jsonObject(with: exportedData) as? [String: Any])
        let artifact = try #require(json["artifact"] as? [String: Any])
        let exportedTemplate = try #require(artifact["template"] as? [String: Any])
        let exportedExercises = try #require(exportedTemplate["exercises"] as? [[String: Any]])
        let firstExercise = try #require(exportedExercises.first)
        let exportedComponents = try #require(firstExercise["components"] as? [[String: Any]])

        #expect(json["formatVersion"] as? Int == 6)
        #expect(artifact["kind"] as? String == "template")
        #expect(exportedComponents.map { $0["exerciseNameSnapshot"] as? String } == ["Reverse Curl", "Wrist Curl"])

        let importResult = try service.importTransfer(from: exportedData)
        let importedTemplateID: UUID
        switch importResult {
        case .template(let templateID):
            importedTemplateID = templateID
        case .folder:
            Issue.record("Expected template import result")
            return
        }

        let importedTemplate = try #require(try repository.template(id: importedTemplateID))
        let importedExercise = try #require(try repository.exercises(in: importedTemplate.id).first)
        let importedComponents = try repository.components(for: importedExercise.id)

        #expect(importedExercise.exerciseNameSnapshot == "Reverse Curl")
        #expect(importedComponents.map(\.catalogExerciseUUID) == [reverseCurl.remoteUUID, wristCurl.remoteUUID])
    }

    @Test
    func exportFolderBundleAndImportTransferPreservesFolderStructure() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        try repository.createFolder(name: "Push")
        let sourceFolder = try #require(try repository.folders().first(where: { $0.name == "Push" }))

        let primaryTemplate = try repository.createTemplate(
            folderID: sourceFolder.id,
            name: "Bench Day",
            notes: "Heavy press"
        )
        try repository.setExercises(
            templateID: primaryTemplate.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: "folder-bench",
                    exerciseNameSnapshot: "WGJ Folder Bench",
                    categorySnapshot: "WGJ Folder Chest",
                    muscleSummarySnapshot: "WGJ Folder Chest",
                    targetRepMin: 5,
                    targetRepMax: 8,
                    restSeconds: 150,
                    setDrafts: [
                        TemplateExerciseSetDraft(
                            targetReps: 5,
                            targetWeight: 110,
                            loadUnit: .kg,
                            restSeconds: 150
                        ),
                    ]
                ),
            ]
        )

        let secondaryTemplate = try repository.createTemplate(
            folderID: sourceFolder.id,
            name: "Row Day",
            notes: "Lats and upper back"
        )
        try repository.setExercises(
            templateID: secondaryTemplate.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: "folder-row",
                    exerciseNameSnapshot: "WGJ Folder Row",
                    categorySnapshot: "WGJ Folder Back",
                    muscleSummarySnapshot: "WGJ Folder Lats",
                    targetRepMin: 8,
                    targetRepMax: 10,
                    restSeconds: 120,
                    setDrafts: [
                        TemplateExerciseSetDraft(
                            targetReps: 8,
                            targetWeight: 80,
                            loadUnit: .kg,
                            restSeconds: 120
                        ),
                    ]
                ),
            ]
        )

        let exportedData = try service.exportData(folderID: sourceFolder.id, format: .bundle)
        let importResult = try service.importTransfer(from: exportedData)
        let importedFolderID: UUID
        switch importResult {
        case .folder(let folderID):
            importedFolderID = folderID
        case .template:
            Issue.record("Expected folder import result")
            return
        }

        let importedFolder = try #require(try repository.folders().first(where: { $0.id == importedFolderID }))
        let importedTemplates = try repository.templates(in: importedFolder.id)

        #expect(importedFolder.name == "Push Copy")
        #expect(importedTemplates.map(\.name) == ["Bench Day", "Row Day"])
        #expect(importedTemplates.map(\.notes) == ["Heavy press", "Lats and upper back"])
        #expect(try repository.exercises(in: importedTemplates[0].id).map(\.exerciseNameSnapshot) == ["WGJ Folder Bench"])
        #expect(try repository.exercises(in: importedTemplates[1].id).map(\.exerciseNameSnapshot) == ["WGJ Folder Row"])
    }

    @Test
    func importFolderKeepsAddingCopySuffixesForRepeatedImports() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        try repository.createFolder(name: "Push")
        let sourceFolder = try #require(try repository.folders().first(where: { $0.name == "Push" }))
        _ = try repository.createTemplate(folderID: sourceFolder.id, name: "Bench Day", notes: "")

        let exportedData = try service.exportData(folderID: sourceFolder.id, format: .bundle)
        let firstImport = try service.importTransfer(from: exportedData)
        let secondImport = try service.importTransfer(from: exportedData)

        let firstFolderID: UUID
        switch firstImport {
        case .folder(let folderID):
            firstFolderID = folderID
        case .template:
            Issue.record("Expected folder import result")
            return
        }

        let secondFolderID: UUID
        switch secondImport {
        case .folder(let folderID):
            secondFolderID = folderID
        case .template:
            Issue.record("Expected folder import result")
            return
        }

        let importedFolders = try repository.folders()
            .filter { [$0.id].contains(firstFolderID) || [$0.id].contains(secondFolderID) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        #expect(importedFolders.map(\.name) == ["Push Copy", "Push Copy 2"])
    }

    @Test
    func exportTemplateAsJsonRoundTripsThroughTransferImport() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        let template = try repository.createTemplate(name: "JSON Push", notes: "Machine readable")
        try repository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: "json-bench",
                    exerciseNameSnapshot: "WGJ JSON Bench",
                    categorySnapshot: "WGJ JSON Chest",
                    muscleSummarySnapshot: "WGJ JSON Chest",
                    targetRepMin: 6,
                    targetRepMax: 8,
                    restSeconds: 120,
                    setDrafts: [
                        TemplateExerciseSetDraft(
                            targetReps: 6,
                            targetWeight: 100,
                            loadUnit: .kg,
                            restSeconds: 120
                        ),
                    ]
                ),
            ]
        )

        let exportedData = try service.exportData(templateID: template.id, format: .json)
        let importResult = try service.importTransfer(from: exportedData)
        let importedTemplateID: UUID
        switch importResult {
        case .template(let templateID):
            importedTemplateID = templateID
        case .folder:
            Issue.record("Expected template import result")
            return
        }

        let importedTemplate = try #require(try repository.template(id: importedTemplateID))
        #expect(importedTemplate.name == "JSON Push Copy")
        #expect(try repository.exercises(in: importedTemplate.id).map(\.exerciseNameSnapshot) == ["WGJ JSON Bench"])
    }

    @Test
    func exportTemplateAsTextIncludesHumanReadableStructure() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        let template = try repository.createTemplate(name: "Readable Push", notes: "Use a controlled eccentric.")
        try repository.setCardioBlocks(
            templateID: template.id,
            drafts: [
                TemplateCardioBlockDraft(
                    phase: .preWorkout,
                    catalogExerciseUUID: "readable-bike",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
            ]
        )
        try repository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: "readable-bench",
                    exerciseNameSnapshot: "Bench Press",
                    categorySnapshot: "Chest",
                    muscleSummarySnapshot: "Chest",
                    notes: "Pause on the chest.",
                    targetRepMin: 6,
                    targetRepMax: 8,
                    restSeconds: 150,
                    setDrafts: [
                        TemplateExerciseSetDraft(
                            targetReps: 8,
                            targetWeight: 100,
                            loadUnit: .kg,
                            restSeconds: 150,
                            isWarmup: true
                        ),
                        TemplateExerciseSetDraft(
                            targetReps: 6,
                            targetWeight: 110,
                            loadUnit: .kg,
                            restSeconds: 150,
                            isLocked: true,
                            dropStages: [
                                TemplateExerciseDropStageDraft(targetReps: 8, targetWeight: 90, loadUnit: .kg),
                            ]
                        ),
                    ],
                    components: [
                        TemplateExerciseComponentDraft(
                            catalogExerciseUUID: "readable-bench",
                            exerciseNameSnapshot: "Bench Press",
                            categorySnapshot: "Chest",
                            muscleSummarySnapshot: "Chest"
                        ),
                        TemplateExerciseComponentDraft(
                            catalogExerciseUUID: "readable-incline",
                            exerciseNameSnapshot: "Incline Press",
                            categorySnapshot: "Chest",
                            muscleSummarySnapshot: "Upper Chest"
                        ),
                    ],
                    superset: ExerciseSupersetMembershipDraft(
                        groupID: UUID(uuidString: "00000000-0000-0000-0000-000000000090")!,
                        position: .first,
                        roundRestSeconds: 90
                    )
                ),
                TemplateExerciseDraft(
                    catalogExerciseUUID: "readable-row",
                    exerciseNameSnapshot: "Chest Supported Row",
                    categorySnapshot: "Back",
                    muscleSummarySnapshot: "Upper Back",
                    targetRepMin: 8,
                    targetRepMax: 10,
                    restSeconds: 90,
                    setDrafts: [
                        TemplateExerciseSetDraft(
                            targetReps: 10,
                            targetWeight: 60,
                            loadUnit: .kg,
                            restSeconds: 90
                        ),
                    ],
                    superset: ExerciseSupersetMembershipDraft(
                        groupID: UUID(uuidString: "00000000-0000-0000-0000-000000000090")!,
                        position: .second,
                        roundRestSeconds: 90
                    )
                ),
            ]
        )

        let exportedData = try service.exportData(templateID: template.id, format: .text)
        let text = try #require(String(data: exportedData, encoding: .utf8))

        #expect(text.contains("Template: Readable Push"))
        #expect(text.contains("Notes: Use a controlled eccentric."))
        #expect(text.contains("Pre-workout cardio"))
        #expect(text.contains("Bike"))
        #expect(text.contains("Exercise 1: Bench Press"))
        #expect(text.contains("Components: Bench Press, Incline Press"))
        #expect(text.contains("Superset: first, round rest 90s"))
        #expect(text.contains("Set 1: warmup"))
        #expect(text.contains("Set 2: locked"))
        #expect(text.contains("Drop set 1: 90 kg x 8"))
    }

    @Test
    func exportFolderAsTextIncludesFolderAndTemplateSections() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        try repository.createFolder(name: "Legs")
        let folder = try #require(try repository.folders().first(where: { $0.name == "Legs" }))
        _ = try repository.createTemplate(folderID: folder.id, name: "Squat Day", notes: "Heavy squats first.")
        _ = try repository.createTemplate(folderID: folder.id, name: "Hinge Day", notes: "Posterior chain.")

        let exportedData = try service.exportData(folderID: folder.id, format: .text)
        let text = try #require(String(data: exportedData, encoding: .utf8))

        #expect(text.contains("Folder: Legs"))
        #expect(text.contains("Template 1: Squat Day"))
        #expect(text.contains("Template 2: Hinge Day"))
    }

    @Test
    func writeExportFilesUseRequestedExtensions() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        try repository.createFolder(name: "Export Targets")
        let folder = try #require(try repository.folders().first(where: { $0.name == "Export Targets" }))
        let template = try repository.createTemplate(folderID: folder.id, name: "Push", notes: "")

        let jsonFileURL = try service.writeExportFile(templateID: template.id, format: .json)
        let textFileURL = try service.writeExportFile(folderID: folder.id, format: .text)

        defer {
            try? FileManager.default.removeItem(at: jsonFileURL)
            try? FileManager.default.removeItem(at: textFileURL)
        }

        #expect(jsonFileURL.pathExtension == "json")
        #expect(textFileURL.pathExtension == "txt")
    }

    @Test
    func importUsesLocalCatalogSnapshotsWhenIncomingUUIDAlreadyExists() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        let localBench = makeCatalogItem(
            remoteUUID: "existing-bench",
            displayName: "WGJ UUID Match Press",
            categoryName: "WGJ Test Chest"
        )
        context.insert(localBench)
        try context.save()

        let importedTemplate = try service.importTemplate(
            from: try encoded(
                TemplateTransferEnvelope(
                    template: TemplateTransferTemplate(
                        name: "Friend Push",
                        notes: "",
                        exercises: [
                            TemplateTransferExercise(
                                catalogExerciseUUID: localBench.remoteUUID,
                                exerciseNameSnapshot: "Wrong Imported Name",
                                categorySnapshot: "Wrong Imported Category",
                                muscleSummarySnapshot: "Wrong Imported Muscles",
                                targetRepMin: 5,
                                targetRepMax: 8,
                                restSeconds: 120,
                                sets: []
                            ),
                        ]
                    )
                )
            )
        )

        let importedExercise = try #require(try repository.exercises(in: importedTemplate.id).first)
        #expect(importedExercise.catalogExerciseUUID == localBench.remoteUUID)
        #expect(importedExercise.exerciseNameSnapshot == localBench.displayName)
        #expect(importedExercise.categorySnapshot == localBench.categoryName)
        #expect(importedExercise.muscleSummarySnapshot == localBench.primaryMuscleNames)
    }

    @Test
    func importRemapsUnknownUUIDToUniqueLocalExerciseAndCarriesPreviousSetHistory() throws {
        let context = try makeInMemoryContext()
        let service = TemplateTransferService(modelContext: context)
        let repository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)

        let localBench = makeCatalogItem(
            remoteUUID: "local-bench",
            displayName: "WGJ History Press",
            categoryName: "WGJ Test Chest"
        )
        context.insert(localBench)
        try context.save()

        let priorSession = try sessionRepository.createEmptySession(name: "Existing Push")
        try sessionRepository.addExercise(sessionID: priorSession.id, catalogItem: localBench)
        let priorExercise = try #require(try sessionRepository.sessionExercises(sessionID: priorSession.id).first)
        var priorDrafts = try sessionRepository.setDrafts(sessionExerciseID: priorExercise.id)
        priorDrafts[0].actualWeight = 100
        priorDrafts[0].actualReps = 8
        priorDrafts[0].actualLoadUnit = .kg
        priorDrafts[0].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: priorExercise.id, drafts: priorDrafts)
        try sessionRepository.finishSession(sessionID: priorSession.id)

        let importedTemplate = try service.importTemplate(
            from: try encoded(
                TemplateTransferEnvelope(
                    template: TemplateTransferTemplate(
                        name: "Shared Push",
                        notes: "",
                        exercises: [
                            TemplateTransferExercise(
                                catalogExerciseUUID: "friend-bench",
                                exerciseNameSnapshot: "WGJ History Press",
                                categorySnapshot: "WGJ Test Chest",
                                muscleSummarySnapshot: "WGJ Test Muscles",
                                targetRepMin: 5,
                                targetRepMax: 8,
                                restSeconds: 120,
                                sets: [
                                    TemplateTransferSet(
                                        targetReps: 8,
                                        targetWeight: 100,
                                        loadUnit: .kg,
                                        restSeconds: 120,
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

        let importedExercise = try #require(try repository.exercises(in: importedTemplate.id).first)
        #expect(importedExercise.catalogExerciseUUID == localBench.remoteUUID)

        let session = try sessionRepository.createSessionFromTemplate(templateID: importedTemplate.id)
        let sessionExercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)
        #expect(sessionExercise.catalogExerciseUUID == localBench.remoteUUID)

        let previousMap = try sessionRepository.previousSetMap(
            for: sessionExercise.catalogExerciseUUID,
            before: session.startedAt,
            excludingSessionID: session.id,
            maxSetCount: 1
        )
        let previous = try #require(previousMap[0])
        #expect(previous.weight == 100)
        #expect(previous.reps == 8)
        #expect(previous.unit == .kg)
    }

    @Test
    func importDoesNotRemapUnknownUUIDWhenExactNameMatchIsAmbiguous() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        context.insert(
            makeCatalogItem(
                remoteUUID: "bench-a",
                displayName: "WGJ Ambiguous Press",
                categoryName: "WGJ Test Chest"
            )
        )
        context.insert(
            makeCatalogItem(
                remoteUUID: "bench-b",
                displayName: "WGJ Ambiguous Press",
                categoryName: "WGJ Test Chest"
            )
        )
        try context.save()

        let importedTemplate = try service.importTemplate(
            from: try encoded(
                TemplateTransferEnvelope(
                    template: TemplateTransferTemplate(
                        name: "Ambiguous Push",
                        notes: "",
                        exercises: [
                            TemplateTransferExercise(
                                catalogExerciseUUID: "friend-flat-bench",
                                exerciseNameSnapshot: "WGJ Ambiguous Press",
                                categorySnapshot: "WGJ Test Chest",
                                muscleSummarySnapshot: "WGJ Test Muscles",
                                targetRepMin: 5,
                                targetRepMax: 8,
                                restSeconds: 120,
                                sets: []
                            ),
                        ]
                    )
                )
            )
        )

        let importedExercise = try #require(try repository.exercises(in: importedTemplate.id).first)
        #expect(importedExercise.catalogExerciseUUID == "friend-flat-bench")
        #expect(importedExercise.exerciseNameSnapshot == "WGJ Ambiguous Press")
        #expect(importedExercise.categorySnapshot == "WGJ Test Chest")
    }

    @Test
    func importDoesNotRemapUnknownUUIDWhenCategoryDoesNotMatchExactly() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        let localBench = makeCatalogItem(
            remoteUUID: "bench-local",
            displayName: "WGJ Category Press",
            categoryName: "WGJ Test Strength"
        )
        context.insert(localBench)
        try context.save()

        let importedTemplate = try service.importTemplate(
            from: try encoded(
                TemplateTransferEnvelope(
                    template: TemplateTransferTemplate(
                        name: "Category Mismatch",
                        notes: "",
                        exercises: [
                            TemplateTransferExercise(
                                catalogExerciseUUID: "friend-bench",
                                exerciseNameSnapshot: "WGJ Category Press",
                                categorySnapshot: "WGJ Test Chest",
                                muscleSummarySnapshot: "WGJ Test Muscles",
                                targetRepMin: 5,
                                targetRepMax: 8,
                                restSeconds: 120,
                                sets: []
                            ),
                        ]
                    )
                )
            )
        )

        let importedExercise = try #require(try repository.exercises(in: importedTemplate.id).first)
        #expect(importedExercise.catalogExerciseUUID == "friend-bench")
        #expect(importedExercise.exerciseNameSnapshot == "WGJ Category Press")
        #expect(importedExercise.categorySnapshot == "WGJ Test Chest")
    }

    @Test
    func importDeduplicatesComponentsThatResolveToSameLocalExercise() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let service = TemplateTransferService(modelContext: context)

        let localBench = makeCatalogItem(
            remoteUUID: "bench-local",
            displayName: "WGJ Component Press",
            categoryName: "WGJ Test Chest"
        )
        let localAlias = ExerciseAlias(value: "WGJ Alias Press", exercise: localBench)
        context.insert(localBench)
        context.insert(localAlias)
        localBench.aliases = [localAlias]
        try context.save()

        let importedTemplate = try service.importTemplate(
            from: try encoded(
                TemplateTransferEnvelope(
                    template: TemplateTransferTemplate(
                        name: "Component Dedupe",
                        notes: "",
                        exercises: [
                            TemplateTransferExercise(
                                catalogExerciseUUID: "friend-bench-a",
                                exerciseNameSnapshot: "WGJ Component Press",
                                categorySnapshot: "WGJ Test Chest",
                                muscleSummarySnapshot: "WGJ Test Muscles",
                                targetRepMin: 5,
                                targetRepMax: 8,
                                restSeconds: 120,
                                sets: [],
                                components: [
                                    TemplateTransferExerciseComponent(
                                        catalogExerciseUUID: "friend-bench-a",
                                        exerciseNameSnapshot: "WGJ Component Press",
                                        categorySnapshot: "WGJ Test Chest",
                                        muscleSummarySnapshot: "WGJ Test Muscles"
                                    ),
                                    TemplateTransferExerciseComponent(
                                        catalogExerciseUUID: "friend-bench-b",
                                        exerciseNameSnapshot: "WGJ Alias Press",
                                        categorySnapshot: "WGJ Test Chest",
                                        muscleSummarySnapshot: "WGJ Test Muscles"
                                    ),
                                ]
                            ),
                        ]
                    )
                )
            )
        )

        let importedExercise = try #require(try repository.exercises(in: importedTemplate.id).first)
        let importedComponents = try repository.components(for: importedExercise.id)

        #expect(importedExercise.catalogExerciseUUID == localBench.remoteUUID)
        #expect(importedComponents.count == 1)
        #expect(importedComponents.first?.catalogExerciseUUID == localBench.remoteUUID)
        #expect(importedComponents.first?.exerciseNameSnapshot == localBench.displayName)
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
                                exerciseNameSnapshot: "WGJ Unknown Carry",
                                categorySnapshot: "WGJ Unknown Category",
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
        #expect(sessionExercise.exerciseNameSnapshot == "WGJ Unknown Carry")
        #expect(sessionExercise.categorySnapshot == "WGJ Unknown Category")
    }

    @Test
    func importFromFileURLKeepsCopySuffixesForRepeatedDirectOpens() throws {
        let context = try makeInMemoryContext()
        let service = TemplateTransferService(modelContext: context)
        let fileURL = try makeTransferFileURL(
            envelope: TemplateTransferEnvelope(
                template: TemplateTransferTemplate(
                    name: "Shared Push",
                    notes: "Friend copy",
                    exercises: []
                )
            )
        )

        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }

        let firstImportedTemplate = try service.importTemplate(from: fileURL)
        let secondImportedTemplate = try service.importTemplate(from: fileURL)

        #expect(firstImportedTemplate.name == "Shared Push")
        #expect(secondImportedTemplate.name == "Shared Push Copy")
        #expect(firstImportedTemplate.folderID == TemplateRepository.unfiledFolderID)
        #expect(secondImportedTemplate.folderID == TemplateRepository.unfiledFolderID)
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

    @Test
    func importSupportsLegacyFormatVersionOneWithoutCardio() throws {
        let context = try makeInMemoryContext()
        let service = TemplateTransferService(modelContext: context)
        let repository = TemplateRepository(modelContext: context)
        let legacyData = try encoded(
            TemplateTransferEnvelope(
                formatVersion: 1,
                template: TemplateTransferTemplate(
                    name: "Legacy Push",
                    notes: "Old share file",
                    exercises: [
                        TemplateTransferExercise(
                            catalogExerciseUUID: "legacy-bench",
                            exerciseNameSnapshot: "WGJ Legacy Press",
                            categorySnapshot: "WGJ Legacy Category",
                            muscleSummarySnapshot: "WGJ Legacy Muscles",
                            targetRepMin: 5,
                            targetRepMax: 8,
                            restSeconds: 120,
                            sets: []
                        ),
                    ]
                )
            )
        )

        let importedTemplate = try service.importTemplate(from: legacyData)

        #expect(importedTemplate.name == "Legacy Push")
        #expect(try repository.cardioBlocks(templateID: importedTemplate.id).isEmpty)
        #expect(try repository.exercises(in: importedTemplate.id).map(\.exerciseNameSnapshot) == ["WGJ Legacy Press"])
    }

    @Test
    func importSupportsLegacyFormatVersionTwoWithoutExerciseComponents() throws {
        let context = try makeInMemoryContext()
        let service = TemplateTransferService(modelContext: context)
        let repository = TemplateRepository(modelContext: context)
        let legacyData = try encoded(
            TemplateTransferEnvelope(
                formatVersion: 2,
                template: TemplateTransferTemplate(
                    name: "Legacy Hybrid",
                    notes: "Older cardio-capable share file",
                    preWorkoutCardio: TemplateTransferCardioBlock(
                        catalogExerciseUUID: "legacy-bike",
                        exerciseNameSnapshot: "Bike",
                        categorySnapshot: "Cardio",
                        muscleSummarySnapshot: "Warmup",
                        targetDurationSeconds: 300
                    ),
                    exercises: [
                        TemplateTransferExercise(
                            catalogExerciseUUID: "legacy-seated-calf-raise",
                            exerciseNameSnapshot: "Seated Calf Raise",
                            categorySnapshot: "Legs",
                            muscleSummarySnapshot: "Calves",
                            targetRepMin: 12,
                            targetRepMax: 15,
                            restSeconds: 60,
                            sets: []
                        ),
                    ]
                )
            )
        )

        let importedTemplate = try service.importTemplate(from: legacyData)
        let importedExercise = try #require(try repository.exercises(in: importedTemplate.id).first)
        let importedComponents = try repository.components(for: importedExercise.id)

        #expect(importedTemplate.name == "Legacy Hybrid")
        #expect(try repository.cardioBlocks(templateID: importedTemplate.id).map(\.phase) == [.preWorkout])
        #expect(importedComponents.count == 1)
        #expect(importedComponents.first?.exerciseNameSnapshot == "Seated Calf Raise")
    }

    @Test
    func importSupportsLegacyFormatVersionFiveWithoutArtifactKey() throws {
        let context = try makeInMemoryContext()
        let service = TemplateTransferService(modelContext: context)
        let repository = TemplateRepository(modelContext: context)
        let legacyPayload: [String: Any] = [
            "formatVersion": 5,
            "exportedAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 0)),
            "template": [
                "name": "Legacy V5 Push",
                "notes": "Pre-artifact envelope",
                "exercises": [
                    [
                        "catalogExerciseUUID": "legacy-v5-bench",
                        "exerciseNameSnapshot": "WGJ Legacy Bench",
                        "categorySnapshot": "WGJ Legacy Chest",
                        "muscleSummarySnapshot": "WGJ Legacy Chest",
                        "restSeconds": 120,
                        "sets": [
                            [
                                "targetReps": 6,
                                "targetWeight": 100,
                                "loadUnit": "kg",
                                "restSeconds": 120,
                                "isWarmup": false,
                                "isLocked": false,
                                "dropStages": [],
                            ],
                        ],
                        "components": [
                            [
                                "catalogExerciseUUID": "legacy-v5-bench",
                                "exerciseNameSnapshot": "WGJ Legacy Bench",
                                "categorySnapshot": "WGJ Legacy Chest",
                                "muscleSummarySnapshot": "WGJ Legacy Chest",
                            ],
                        ],
                    ],
                ],
            ],
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyPayload, options: [])

        let importedTemplate = try service.importTemplate(from: legacyData)
        let importedExercise = try #require(try repository.exercises(in: importedTemplate.id).first)
        let importedComponents = try repository.components(for: importedExercise.id)

        #expect(importedTemplate.name == "Legacy V5 Push")
        #expect(importedExercise.exerciseNameSnapshot == "WGJ Legacy Bench")
        #expect(importedComponents.map(\.exerciseNameSnapshot) == ["WGJ Legacy Bench"])
    }

    @Test
    func importFromFileURLRejectsMalformedFile() throws {
        let context = try makeInMemoryContext()
        let service = TemplateTransferService(modelContext: context)
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL
            .appendingPathComponent("broken")
            .appendingPathExtension(TemplateTransferFileFormat.filenameExtension)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Data("bad json".utf8).write(to: fileURL, options: .atomic)

        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        #expect(throws: TemplateTransferError.self) {
            try service.importTemplate(from: fileURL)
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
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            TemplateSupersetGroup.self,
            TemplateExerciseDropStage.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            ActiveWorkoutDraftSupersetGroup.self,
            ActiveWorkoutDraftDropStage.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            WorkoutSessionSupersetGroup.self,
            WorkoutSessionDropStage.self,
            CompletedSetFact.self,
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

    private func makeCatalogItem(
        remoteUUID: String,
        displayName: String,
        categoryName: String
    ) -> ExerciseCatalogItem {
        ExerciseCatalogItem(
            remoteUUID: remoteUUID,
            displayName: displayName,
            categoryName: categoryName,
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "custom"
        )
    }

    private func makeTransferFileURL(envelope: TemplateTransferEnvelope) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL
            .appendingPathComponent("shared-template")
            .appendingPathExtension(TemplateTransferFileFormat.filenameExtension)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try encoded(envelope).write(to: fileURL, options: .atomic)
        return fileURL
    }
}
