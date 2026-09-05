import Foundation

/// Upload progress does not change local counts. Retain the last mutation marker
/// when the status advances from pending to success or failure.
nonisolated struct ProfileBackupSummaryRefreshState: Equatable, Sendable {
    private(set) var latestMutationAt: Date?

    mutating func observe(_ status: UserDataSyncStatusSnapshot) {
        if let mutationAt = status.latestLocalMutationAt {
            latestMutationAt = mutationAt
        }
    }
}

nonisolated struct ProfileBackupSummaryRefreshKey: Equatable, Sendable {
    let isActive: Bool
    let latestMutationAt: Date?
    let profileInvalidationVersion: Int
    let cloudSessionRevision: Int
}
