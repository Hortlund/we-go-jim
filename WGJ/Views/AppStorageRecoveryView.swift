import SwiftUI

struct AppStorageRecoveryView: View {
    let state: AppStorageRecoveryState
    let onRetry: () -> Void
    let onEnterDiagnosticMode: () -> Void

    var body: some View {
        AppStorageStatusSurface(
            title: "Storage unavailable",
            message: state.message,
            systemImage: "externaldrive.badge.exclamationmark",
            primaryActionTitle: "Retry",
            primaryAction: onRetry
        ) {
            ShareLink(item: state.diagnosticReport) {
                Label("Share Diagnostics", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WGJGhostButtonStyle())

            Button("Enter Temporary Diagnostics", action: onEnterDiagnosticMode)
                .buttonStyle(WGJGhostButtonStyle())

            Text("Temporary diagnostics cannot save workouts, templates, profile changes, or history edits.")
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityIdentifier("app-storage-recovery-view")
    }
}

struct AppStorageDiagnosticModeView: View {
    let reason: String
    let onRetry: () -> Void

    var body: some View {
        AppStorageStatusSurface(
            title: "Temporary diagnostics",
            message: "Changes cannot be saved. Normal workout and editing features are unavailable until durable storage opens.",
            systemImage: "wrench.and.screwdriver.fill",
            primaryActionTitle: "Retry Durable Storage",
            primaryAction: onRetry
        ) {
            ShareLink(item: reason) {
                Label("Share Diagnostics", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WGJGhostButtonStyle())
        }
        .accessibilityIdentifier("app-storage-diagnostic-mode-view")
    }
}

private struct AppStorageStatusSurface<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    let primaryActionTitle: String
    let primaryAction: () -> Void
    @ViewBuilder let actions: Actions

    var body: some View {
        ZStack {
            WGJTheme.screenBackgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: systemImage)
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(WGJTheme.accentGold)
                        .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        Text(title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(WGJTheme.textPrimary)

                        Text(message)
                            .font(.body)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(WGJPrimaryButtonStyle())

                    actions
                }
                .frame(maxWidth: 520)
                .padding(24)
                .wgjCardContainer(strong: true)
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: 640)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Storage recovery") {
    AppStorageRecoveryView(
        state: AppStorageRecoveryState(
            message: "WGJ could not open durable app storage.",
            diagnosticReport: "Example diagnostic report"
        ),
        onRetry: {},
        onEnterDiagnosticMode: {}
    )
}
