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
        self.templateRepository = TemplateRepository(modelContext: modelContext)
        self.catalogRepository = ExerciseCatalogRepository(modelContext: modelContext)
    }

    func seedDemoDataIfEmpty() throws {
        try catalogRepository.ensureSeedImportedIfNeeded()

        let profile = try profileRepository.loadOrCreateProfile()
        if profile.displayName == "Athlete" {
            try profileRepository.updateDisplayName("Demo Lifter")
        }

        let existingFolders = try templateRepository.folders()
        let hasAnyTemplates = existingFolders.contains { !($0.templates ?? []).isEmpty }

        if hasAnyTemplates {
            return
        }

        for folderName in DemoSeedCatalog.folderNames where !existingFolders.contains(where: { $0.name.caseInsensitiveCompare(folderName) == .orderedSame }) {
            try templateRepository.createFolder(name: folderName)
        }

        let refreshedFolders = try templateRepository.folders()
        let foldersByName = Dictionary(
            refreshedFolders.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let catalogItems = try modelContext.fetch(
            FetchDescriptor<ExerciseCatalogItem>(
                sortBy: [SortDescriptor(\.displayName, order: .forward)]
            )
        )
        let itemsByUUID = Dictionary(
            catalogItems.map { ($0.remoteUUID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for seedTemplate in DemoSeedCatalog.templates {
            guard let folder = foldersByName[seedTemplate.folderName.lowercased()] else {
                continue
            }

            let existingTemplates = try templateRepository.templates(in: folder.id)
            let template: WorkoutTemplate

            if let existing = existingTemplates.first(where: { $0.name.caseInsensitiveCompare(seedTemplate.name) == .orderedSame }) {
                template = existing
            } else {
                template = try templateRepository.createTemplate(
                    folderID: folder.id,
                    name: seedTemplate.name,
                    notes: seedTemplate.notes
                )
            }

            if !(try templateRepository.exercises(in: template.id)).isEmpty {
                continue
            }

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

    func clearDemoData() throws {
        let folders = try modelContext.fetch(FetchDescriptor<TemplateFolder>())
        for folder in folders {
            modelContext.delete(folder)
        }

        let profiles = try modelContext.fetch(FetchDescriptor<UserProfile>())
        for profile in profiles {
            modelContext.delete(profile)
        }

        try modelContext.save()
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
}
#endif
