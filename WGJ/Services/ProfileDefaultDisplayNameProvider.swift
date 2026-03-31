import CloudKit
import Foundation

protocol ProfileDefaultDisplayNameProviding {
    func defaultDisplayName() async -> String?
}

struct ICloudProfileDefaultDisplayNameProvider: ProfileDefaultDisplayNameProviding {
    private let container: CKContainer?

    init(container: CKContainer? = nil) {
        self.container = container ?? AppRuntimeConfig.makeCloudKitContainer()
    }

    func defaultDisplayName() async -> String? {
        guard let container else {
            return nil
        }

        do {
            let userRecordID = try await container.userRecordID()
            let participant = try await container.shareParticipant(forUserRecordID: userRecordID)
            return Self.formattedName(from: participant.userIdentity.nameComponents)
        } catch {
            return nil
        }
    }

    private static func formattedName(from components: PersonNameComponents?) -> String? {
        guard let components else {
            return nil
        }

        let formatter = PersonNameComponentsFormatter()
        let formatted = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        if !formatted.isEmpty {
            return formatted
        }

        let fallback = [components.givenName, components.middleName, components.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return fallback.isEmpty ? nil : fallback
    }
}
