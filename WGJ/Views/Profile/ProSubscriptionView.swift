import StoreKit
import SwiftUI

nonisolated enum ProSubscriptionManagementPresentation {
    static let sectionTitle = "Subscription Management"
    static let sectionSubtitle = """
        Use Apple to manage or cancel App Store subscriptions. Customer Center can help with billing support, refunds, and save offers when available.
        """
    static let appleActionTitle = "Manage or Cancel Subscription"
    static let customerCenterActionTitle = "Billing Support & Offers"
}

struct ProSubscriptionView: View {
    @Environment(SubscriptionState.self) private var subscriptionState
    @State private var showingAppleSubscriptionManagement = false

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
        .manageSubscriptionsSheet(isPresented: $showingAppleSubscriptionManagement)
        .task {
            await subscriptionState.refreshCustomerInfo()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(
                subscriptionState.isPro ? "Pro Active" : "Free Plan",
                subtitle: subscriptionState.isPro
                    ? "Your We Go Jim Pro access is active."
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer()
    }

    private var managementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJSectionHeader(
                ProSubscriptionManagementPresentation.sectionTitle,
                subtitle: ProSubscriptionManagementPresentation.sectionSubtitle
            )

            Button {
                showingAppleSubscriptionManagement = true
            } label: {
                managementButtonLabel(
                    ProSubscriptionManagementPresentation.appleActionTitle,
                    systemImage: "creditcard"
                )
            }
            .buttonStyle(WGJGhostButtonStyle())
            .accessibilityIdentifier("pro-subscription-manage-apple-button")

            Button {
                subscriptionState.isCustomerCenterPresented = true
            } label: {
                managementButtonLabel(
                    ProSubscriptionManagementPresentation.customerCenterActionTitle,
                    systemImage: "person.crop.circle.badge.questionmark"
                )
            }
            .buttonStyle(WGJGhostButtonStyle())
            .accessibilityIdentifier("pro-subscription-customer-center-button")

            Button {
                subscriptionState.redeemOfferCode()
            } label: {
                managementButtonLabel("Redeem Offer Code", systemImage: "ticket")
            }
            .buttonStyle(WGJGhostButtonStyle())
            .accessibilityIdentifier("pro-subscription-redeem-offer-code-button")

            Button {
                Task {
                    await subscriptionState.restorePurchases()
                }
            } label: {
                if subscriptionState.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    managementButtonLabel("Restore Purchases", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(WGJGhostButtonStyle())
            .disabled(subscriptionState.isLoading)
            .accessibilityIdentifier("pro-subscription-restore-button")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(WGJTheme.accentGold)
                .frame(width: 32, alignment: .center)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func managementButtonLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 24, alignment: .center)

            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        ProSubscriptionView()
    }
    .environment(SubscriptionState.shared)
}
