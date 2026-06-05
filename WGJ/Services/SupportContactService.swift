import Foundation

struct SupportContactDraft: Equatable {
    let recipient: String
    let subject: String
    let body: String

    var mailtoURL: URL? {
        guard !recipient.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}

enum SupportContactService {
    static func reportMemberDraft(
        snapshot: BrosFeedSnapshot,
        reportedMember: BroMemberSummary
    ) -> SupportContactDraft {
        SupportContactDraft(
            recipient: AppRuntimeConfig.supportEmail,
            subject: "WGJ Member Report",
            body: """
            I want to report a member in Bros.

            Circle ID: \(snapshot.circle.circleID)
            Reported membership ID: \(reportedMember.id)
            Reported user record: \(reportedMember.userRecordName)
            Reported display name: \(reportedMember.displayName)
            Reported athlete type: \(reportedMember.athleteType?.title ?? "None")
            Reported role: \(reportedMember.role.rawValue)

            Reporter membership ID: \(snapshot.currentMember.id)
            Reporter user record: \(snapshot.currentMember.userRecordName)
            Reporter display name: \(snapshot.currentMember.displayName)
            Reporter athlete type: \(snapshot.currentMember.athleteType?.title ?? "None")

            Additional details:
            """
        )
    }

    static func reportEventDraft(
        snapshot: BrosFeedSnapshot,
        event: BroFeedEvent
    ) -> SupportContactDraft {
        SupportContactDraft(
            recipient: AppRuntimeConfig.supportEmail,
            subject: "WGJ Feed Report",
            body: """
            I want to report a Bros feed post.

            Circle ID: \(snapshot.circle.circleID)
            Event ID: \(event.id)
            Event kind: \(event.kind.rawValue)
            Event created at: \(event.createdAt.formatted(date: .abbreviated, time: .shortened))

            Actor membership ID: \(event.actorMembershipID)
            Actor user record: \(event.actorUserRecordName)
            Actor display name: \(event.actorDisplayName)

            Reporter membership ID: \(snapshot.currentMember.id)
            Reporter user record: \(snapshot.currentMember.userRecordName)
            Reporter display name: \(snapshot.currentMember.displayName)

            Additional details:
            """
        )
    }
}
