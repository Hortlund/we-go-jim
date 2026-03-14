import Foundation
import SwiftData

enum BlockedBroRepositoryError: LocalizedError {
    case missingUserRecordName

    var errorDescription: String? {
        switch self {
        case .missingUserRecordName:
            return "That bro can't be blocked right now."
        }
    }
}

@MainActor
final class BlockedBroRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func blockedItems() throws -> [BlockedBro] {
        let descriptor = FetchDescriptor<BlockedBro>(
            sortBy: [SortDescriptor(\.blockedAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func blockedUserRecordNames() -> Set<String> {
        let items = (try? blockedItems()) ?? []
        return Set(
            items
                .map(\.userRecordName)
                .filter { !$0.isEmpty }
        )
    }

    func isBlocked(userRecordName: String) -> Bool {
        guard !userRecordName.isEmpty else { return false }
        return blockedUserRecordNames().contains(userRecordName)
    }

    func block(userRecordName: String, displayName: String) throws {
        let cleanedRecordName = userRecordName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedRecordName.isEmpty else {
            throw BlockedBroRepositoryError.missingUserRecordName
        }

        if let existing = try blockedItem(userRecordName: cleanedRecordName) {
            existing.displayNameSnapshot = ReviewModerationService.sanitizedForSharing(
                displayName,
                kind: .displayName
            )
            existing.blockedAt = .now
        } else {
            let created = BlockedBro(
                userRecordName: cleanedRecordName,
                displayNameSnapshot: ReviewModerationService.sanitizedForSharing(
                    displayName,
                    kind: .displayName
                )
            )
            modelContext.insert(created)
        }

        try modelContext.save()
    }

    func unblock(userRecordName: String) throws {
        guard let existing = try blockedItem(userRecordName: userRecordName) else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }

    private func blockedItem(userRecordName: String) throws -> BlockedBro? {
        let descriptor = FetchDescriptor<BlockedBro>(
            predicate: #Predicate { item in
                item.userRecordName == userRecordName
            }
        )
        return try modelContext.fetch(descriptor).first
    }
}
