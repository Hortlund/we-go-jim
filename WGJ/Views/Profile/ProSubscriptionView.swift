import SwiftUI

struct ProSubscriptionView: View {
    @Environment(SubscriptionState.self) private var subscriptionState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader(
                    "We Go Jim Pro",
                    subtitle: subscriptionState.isPro
                        ? "Your Pro access is active."
                        : "Unlock deeper planning, analysis, and Bros controls."
                )

                statusCard
                includedCard
                managementCard
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("We Go Jim Pro")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await subscriptionState.refreshCustomerInfo()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(
                subscriptionState.isPro ? "Pro Active" : "Free Plan",
                subtitle: subscriptionState.isPro
                    ? "RevenueCat reports the We Go Jim Pro entitlement as active."
                    : "Free keeps the core training loop open. Pro removes caps and unlocks analysis."
            )

            if let customerID = subscriptionState.customerInfo?.originalAppUserID, !customerID.isEmpty {
                infoRow("Customer ID", value: customerID)
            }

            if let errorMessage = subscriptionState.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !subscriptionState.isPro {
                Button {
                    subscriptionState.presentPaywall()
                } label: {
                    Label("View Plans", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .accessibilityIdentifier("pro-subscription-view-plans-button")
            }
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    private var includedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJSectionHeader("Included With Pro")

            proFeatureRow("Unlimited templates", systemImage: "square.grid.2x2")
            proFeatureRow("Muscle maps in Profile, History, and workout summaries", systemImage: "figure.strengthtraining.traditional")
            proFeatureRow("Coach Brief and follow-up analysis", systemImage: "brain.head.profile")
            proFeatureRow("Advanced trend widgets", systemImage: "chart.line.uptrend.xyaxis")
            proFeatureRow("Bros circles above two members", systemImage: "person.3.fill")
        }
        .padding(14)
        .wgjCardContainer()
    }

    private var managementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJSectionHeader(
                "Subscription Management",
                subtitle: "Use RevenueCat Customer Center for plan changes, refunds, and billing support when it is enabled in RevenueCat."
            )

            Button {
                subscriptionState.isCustomerCenterPresented = true
            } label: {
                Label("Open Customer Center", systemImage: "person.crop.circle.badge.questionmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WGJGhostButtonStyle())
            .accessibilityIdentifier("pro-subscription-customer-center-button")

            Button {
                Task {
                    await subscriptionState.restorePurchases()
                }
            } label: {
                if subscriptionState.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(WGJGhostButtonStyle())
            .disabled(subscriptionState.isLoading)
            .accessibilityIdentifier("pro-subscription-restore-button")
        }
        .padding(14)
        .wgjCardContainer()
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(WGJTheme.textPrimary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(WGJTheme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .font(.subheadline)
    }

    private func proFeatureRow(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(WGJTheme.accentGold)
        }
    }
}

#Preview {
    NavigationStack {
        ProSubscriptionView()
    }
    .environment(SubscriptionState.shared)
}
