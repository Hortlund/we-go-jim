import Foundation

enum UserProfileSelection {
    static func currentProfile(in profiles: [UserProfile]) -> UserProfile? {
        profiles.min { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
