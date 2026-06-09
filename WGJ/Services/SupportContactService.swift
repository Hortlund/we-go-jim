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
    static func appSupportDraft(subject: String = "WGJ Support") -> SupportContactDraft {
        SupportContactDraft(
            recipient: AppRuntimeConfig.supportEmail,
            subject: subject,
            body: """
            Tell me what happened:
            """
        )
    }
}
