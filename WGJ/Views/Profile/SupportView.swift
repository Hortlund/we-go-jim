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
                WGJRootHeader("Support", subtitle: "Best-effort support for app issues, privacy questions, purchases, and moderation reports.")

                VStack(alignment: .leading, spacing: 12) {
                    WGJSectionHeader("Support on X", subtitle: AppRuntimeConfig.supportXHandle)

                    if let supportXURL = AppRuntimeConfig.supportXURL {
                        Button {
                            openURL(supportXURL)
                        } label: {
                            Label("Open \(AppRuntimeConfig.supportXHandle) on X", systemImage: "at")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WGJPrimaryButtonStyle())
                        .accessibilityIdentifier("support-open-x-button")
                    }

                    Button {
                        UIPasteboard.general.string = AppRuntimeConfig.supportXURL?.absoluteString
                        showAlert(
                            title: "Copied",
                            message: "The X support profile link is on your clipboard."
                        )
                    } label: {
                        Label("Copy X Profile Link", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                    .accessibilityIdentifier("support-copy-x-link-button")

                    if let supportURL = AppRuntimeConfig.supportURL {
                        Button {
                            openURL(supportURL)
                        } label: {
                            Label("Open Privacy & Contact", systemImage: "globe")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WGJGhostButtonStyle())
                        .accessibilityIdentifier("support-open-privacy-contact-button")
                    }
                }
                .padding(14)
                .wgjCardContainer(strong: true)

                infoCard(
                    title: "Support expectations",
                    lines: [
                        "WGJ is an independent hobby project, so support is provided when practical and response times are not guaranteed.",
                        "App uptime, iCloud sync, Bros availability, notifications, and external services are not guaranteed.",
                        "Features may change, be limited, or be discontinued if they cannot be maintained safely or reliably.",
                    ]
                )

                infoCard(
                    title: "What to send",
                    lines: [
                        "App bugs, crashes, account state, iCloud sync, and local-only fallback issues.",
                        "Privacy questions, data-deletion follow-up, account issues, and moderation concerns.",
                        "Bros reports, blocks, abuse, harassment, unsafe content, and moderation concerns.",
                        "Purchase, restore, subscription, and billing-support questions for We Go Jim Pro.",
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
