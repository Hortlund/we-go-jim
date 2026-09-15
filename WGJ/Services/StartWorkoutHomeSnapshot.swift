import Foundation
import Observation
import SwiftData

nonisolated struct StartWorkoutFolderSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let templateCount: Int

    init(id: UUID, name: String, sortOrder: Int, templateCount: Int) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.templateCount = templateCount
    }
}

nonisolated struct StartWorkoutTemplateRowSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let folderID: UUID
    let name: String
    let notes: String?
    let sortOrder: Int
    let exerciseCount: Int

    init(template: WorkoutTemplate) {
        id = template.id
        folderID = template.folderID
        name = template.name
        let trimmedNotes = template.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        sortOrder = template.sortOrder
        exerciseCount = (template.exercises ?? []).count
            + (template.cardioBlocks ?? []).lazy.filter { $0.role == .main }.count
    }

    init(id: UUID, folderID: UUID, name: String, notes: String?, sortOrder: Int, exerciseCount: Int) {
        self.id = id
        self.folderID = folderID
        self.name = name
        self.notes = notes
        self.sortOrder = sortOrder
        self.exerciseCount = exerciseCount
    }
}

nonisolated struct StartWorkoutHomeSnapshot: Sendable {
    let folders: [StartWorkoutFolderSnapshot]
    let templates: [StartWorkoutTemplateRowSnapshot]
    let sections: [StartWorkoutTemplateSection]
    let lastCompletedByTemplateID: [UUID: Date]

    static let empty = StartWorkoutHomeSnapshot(
        folders: [],
        templates: [],
        sections: [],
        lastCompletedByTemplateID: [:]
    )

    func containsSavedTemplateResult(_ result: TemplateEditorSaveResult) -> Bool {
        let trimmedName = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = result.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return templates.contains { template in
            template.id == result.templateID
                && template.name == trimmedName
                && (template.notes ?? "") == trimmedNotes
        }
    }
}

@MainActor
@Observable
final class StartWorkoutHomeController {
    var snapshot = StartWorkoutHomeSnapshot.empty

    func apply(_ snapshot: StartWorkoutHomeSnapshot) {
        self.snapshot = snapshot
    }

    func applyTemplateSaveResult(_ result: TemplateEditorSaveResult) {
        snapshot = StartWorkoutHomeSnapshotBuilder.applyingTemplateSaveResult(result, to: snapshot)
    }
}

nonisolated enum StartWorkoutHomeSnapshotLoader {
    static func load(modelContext: ModelContext) throws -> StartWorkoutHomeSnapshot {
        let templateRepository = TemplateRepository(modelContext: modelContext)
        let sessionRepository = WorkoutSessionRepository(modelContext: modelContext)
        return StartWorkoutHomeSnapshotBuilder.build(
            folders: try templateRepository.folders(),
            templates: try templateRepository.templates(),
            completedSessions: try sessionRepository.completedSessions()
        )
    }
}

nonisolated enum StartWorkoutHomeSnapshotBuilder {
    static func build(
        folders: [TemplateFolder],
        templates: [WorkoutTemplate],
        completedSessions: [WorkoutSession]
    ) -> StartWorkoutHomeSnapshot {
        let templateCountsByFolderID = Dictionary(
            grouping: templates,
            by: \.folderID
        ).mapValues(\.count)
        let folderSnapshots = folders.map { folder in
            StartWorkoutFolderSnapshot(
                id: folder.id,
                name: folder.name,
                sortOrder: folder.sortOrder,
                templateCount: templateCountsByFolderID[folder.id, default: 0]
            )
        }
        let templateSnapshots = templates.map(StartWorkoutTemplateRowSnapshot.init(template:))
        let orderedTemplates = orderTemplates(templateSnapshots, folders: folderSnapshots)
        let sections = buildSections(folders: folderSnapshots, templates: orderedTemplates)
        let lastCompletedByTemplateID = buildLastCompletedByTemplateID(completedSessions)

        return StartWorkoutHomeSnapshot(
            folders: folderSnapshots,
            templates: orderedTemplates,
            sections: sections,
            lastCompletedByTemplateID: lastCompletedByTemplateID
        )
    }

    static func applyingTemplateSaveResult(
        _ result: TemplateEditorSaveResult,
        to snapshot: StartWorkoutHomeSnapshot
    ) -> StartWorkoutHomeSnapshot {
        let trimmedName = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = result.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var didUpdateTemplate = false
        let updatedTemplates = snapshot.templates.map { template in
            guard template.id == result.templateID else { return template }
            didUpdateTemplate = true
            return StartWorkoutTemplateRowSnapshot(
                id: template.id,
                folderID: template.folderID,
                name: trimmedName.isEmpty ? template.name : trimmedName,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                sortOrder: template.sortOrder,
                exerciseCount: template.exerciseCount
            )
        }

        guard didUpdateTemplate else { return snapshot }

        let orderedTemplates = orderTemplates(updatedTemplates, folders: snapshot.folders)
        return StartWorkoutHomeSnapshot(
            folders: snapshot.folders,
            templates: orderedTemplates,
            sections: buildSections(folders: snapshot.folders, templates: orderedTemplates),
            lastCompletedByTemplateID: snapshot.lastCompletedByTemplateID
        )
    }

    private static func orderTemplates(
        _ templates: [StartWorkoutTemplateRowSnapshot],
        folders: [StartWorkoutFolderSnapshot]
    ) -> [StartWorkoutTemplateRowSnapshot] {
        let folderOrderByID = Dictionary(
            folders.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { existing, _ in existing }
        )
        return templates.sorted {
            let lhsFolderOrder = $0.folderID == TemplateRepository.unfiledFolderID
                ? -1
                : (folderOrderByID[$0.folderID] ?? Int.max)
            let rhsFolderOrder = $1.folderID == TemplateRepository.unfiledFolderID
                ? -1
                : (folderOrderByID[$1.folderID] ?? Int.max)

            if lhsFolderOrder != rhsFolderOrder {
                return lhsFolderOrder < rhsFolderOrder
            }
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func buildSections(
        folders: [StartWorkoutFolderSnapshot],
        templates: [StartWorkoutTemplateRowSnapshot]
    ) -> [StartWorkoutTemplateSection] {
        let templatesByFolderID = Dictionary(grouping: templates, by: \.folderID)
        var sections: [StartWorkoutTemplateSection] = []

        if let unfiledTemplates = templatesByFolderID[TemplateRepository.unfiledFolderID],
           !unfiledTemplates.isEmpty
        {
            sections.append(
                StartWorkoutTemplateSection(
                    id: TemplateRepository.unfiledFolderID,
                    title: "Unfiled",
                    systemImage: "tray.full.fill",
                    folderIDForCreation: nil,
                    templates: unfiledTemplates
                )
            )
        }

        for folder in folders {
            sections.append(
                StartWorkoutTemplateSection(
                    id: folder.id,
                    title: folder.name,
                    systemImage: "folder.fill",
                    folderIDForCreation: folder.id,
                    templates: templatesByFolderID[folder.id] ?? []
                )
            )
        }

        return sections
    }

    private static func buildLastCompletedByTemplateID(_ sessions: [WorkoutSession]) -> [UUID: Date] {
        var completedByTemplateID: [UUID: Date] = [:]

        for session in sessions {
            guard session.status == .completed, let templateID = session.templateID else {
                continue
            }
            let completedAt = session.endedAt ?? session.startedAt
            if let existing = completedByTemplateID[templateID] {
                if completedAt > existing {
                    completedByTemplateID[templateID] = completedAt
                }
            } else {
                completedByTemplateID[templateID] = completedAt
            }
        }

        return completedByTemplateID
    }
}

nonisolated struct StartWorkoutTemplateSection: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let systemImage: String
    let folderIDForCreation: UUID?
    let templates: [StartWorkoutTemplateRowSnapshot]

    var isUnfiled: Bool {
        folderIDForCreation == nil
    }
}
