import Foundation

nonisolated struct TemplateFolderSnapshot: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let templateCount: Int
}
