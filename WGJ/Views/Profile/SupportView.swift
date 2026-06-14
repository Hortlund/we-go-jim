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
                WGJRootHeader("Support", subtitle: "Best-effort support for app issues and privacy questions.")

                VStack(alignment: .leading, spacing: 12) {
                    WGJSectionHeader(
                        "Project Support",
                        subtitle: AppRuntimeConfig.supportURL?.absoluteString ?? "No support URL configured"
                    )

                    if let supportURL = AppRuntimeConfig.supportURL {
                        Button {
                            openURL(supportURL)
                        } label: {
                            Label("Open GitHub Issues", systemImage: "exclamationmark.bubble")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WGJPrimaryButtonStyle())
                        .accessibilityIdentifier("support-open-project-issues-button")

                        Button {
                            UIPasteboard.general.string = supportURL.absoluteString
                            showAlert(
                                title: "Copied",
                                message: "The project support link is on your clipboard."
                            )
                        } label: {
                            Label("Copy Support Link", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WGJGhostButtonStyle())
                        .accessibilityIdentifier("support-copy-project-link-button")
                    }
                }
                .padding(14)
                .wgjCardContainer(strong: true)

                infoCard(
                    title: "Support expectations",
                    lines: [
                        "WGJ is an independent hobby project, so support is provided when practical and response times are not guaranteed.",
                        "App uptime, CloudKit backup availability, notifications, and external services are not guaranteed.",
                        "Features may change, be limited, or be discontinued if they cannot be maintained safely or reliably.",
                    ]
                )

                infoCard(
                    title: "What to send",
                    lines: [
                        "App bugs, crashes, account state, iCloud sync, and local-only fallback issues.",
                        "Privacy questions, data-deletion follow-up, account issues, and backup issues.",
                    ]
                )

                if AppRuntimeConfig.supportURL == nil {
                    WGJEmptyStateCard(
                        title: "Support link unavailable",
                        message: "The support link is not available right now. Use the contact options above for help.",
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
        .navigationBarTitleDisplayMode(.inline)
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
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
