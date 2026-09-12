import SwiftUI
import SwiftData

nonisolated struct ActiveWorkoutTemplateFolderSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String

    nonisolated init(folder: TemplateFolder) {
        self.id = folder.id
        self.name = folder.name
    }
}
