import SwiftUI
import UIKit

struct SupportView: View {
    @Environment(\.openURL) private var openURL

    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Support", subtitle: "Contact support, open your hosted support page, or copy details for App Review.")

                VStack(alignment: .leading, spacing: 12) {
                    WGJSectionHeader("Support Email", subtitle: AppRuntimeConfig.supportEmail)

                    Button {
                        contactSupport()
                    } label: {
                        Label("Email Support", systemImage: "envelope.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())

                    Button {
                        UIPasteboard.general.string = AppRuntimeConfig.supportEmail
                        showAlert(
                            title: "Copied",
                            message: "The support email address is on your clipboard."
                        )
                    } label: {
                        Label("Copy Support Email", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WGJGhostButtonStyle())

                    if let supportURL = AppRuntimeConfig.supportURL {
                        Button {
                            openURL(supportURL)
                        } label: {
                            Label("Open Support Site", systemImage: "globe")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WGJGhostButtonStyle())
                    }
                }
                .padding(14)
                .wgjCardContainer(strong: true)

                infoCard(
                    title: "What support handles",
                    lines: [
                        "Account and iCloud sync issues.",
                        "Bug reports, crashes, and review follow-up.",
                        "Abuse and moderation reports from Bros.",
                    ]
                )

                if AppRuntimeConfig.supportURL == nil {
                    WGJEmptyStateCard(
                        title: "Hosted support URL still needed",
                        message: "You can ship with in-app support details, but App Store Connect still needs a real support URL before review.",
                        icon: "link.badge.plus"
                    )
                }
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Support")
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func contactSupport() {
        let draft = SupportContactService.generalSupportDraft()
        guard let url = draft.mailtoURL else {
            UIPasteboard.general.string = draft.body
            showAlert(
                title: "Mail unavailable",
                message: "Support details were copied to your clipboard instead."
            )
            return
        }

        openURL(url) { accepted in
            guard !accepted else { return }
            UIPasteboard.general.string = draft.body
            showAlert(
                title: "Mail unavailable",
                message: "The support message was copied to your clipboard. Send it to \(AppRuntimeConfig.supportEmail)."
            )
        }
    }

    private func infoCard(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(title)

            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(WGJTheme.accentBlue.opacity(0.24))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textPrimary)
                }
            }
        }
        .padding(14)
        .wgjCardContainer()
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

#Preview {
    NavigationStack {
        SupportView()
    }
}
