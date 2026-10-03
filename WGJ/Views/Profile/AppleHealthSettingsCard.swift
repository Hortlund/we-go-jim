import SwiftUI

struct AppleHealthSettingsCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var service = AppleHealthExportService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Apple Health", subtitle: "Save new workouts to Apple Health.")

            Toggle("Save workouts", isOn: Binding(
                get: { service.isEnabled },
                set: { enabled in Task { await service.setEnabled(enabled) } }
            ))
            .foregroundStyle(WGJTheme.textPrimary)
            .tint(WGJTheme.accentBlue)
            .disabled(!service.isAvailable || service.isAuthorizing || service.isExporting)
            .accessibilityIdentifier("settings-apple-health-workouts-toggle")

            if service.isEnabled {
                Toggle("Include active calories", isOn: Binding(
                    get: { service.sharesEstimatedCalories },
                    set: { enabled in Task { await service.setSharesEstimatedCalories(enabled) } }
                ))
                .foregroundStyle(WGJTheme.textPrimary)
                .tint(WGJTheme.accentBlue)
                .disabled(service.isAuthorizing || service.isExporting)
                .accessibilityIdentifier("settings-apple-health-calories-toggle")

                Text("Uses WGJ's estimates, not measured calories.")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Calories require your calorie details and Show calorie estimates to be enabled.")
                    Text("Editing or deleting workouts in WGJ, or turning export off, leaves saved Health records unchanged.")
                }
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            } label: {
                Text("How it works")
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            }
            .tint(WGJTheme.accentBlue)
            .accessibilityIdentifier("settings-apple-health-details")

            if !service.isAvailable {
                Text("Apple Health is unavailable on this device.")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            if service.isAuthorizing || service.isExporting {
                ProgressView(service.isAuthorizing ? "Connecting Apple Health…" : "Saving to Apple Health…")
                    .font(.caption)
            }
            if let message = service.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .accessibilityIdentifier("settings-apple-health-status")
            }
            if service.canRetry {
                if service.pendingCount > 0 {
                    Text("Pending exports: \(service.pendingCount)")
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
                Button("Retry Apple Health") { service.resumePending() }
                    .buttonStyle(WGJGhostButtonStyle())
                    .disabled(service.isAuthorizing || service.isExporting)
                    .accessibilityIdentifier("settings-apple-health-retry-button")
            }
        }
        .padding(14)
        .wgjCardContainer()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { service.resumePending() }
        }
    }
}
