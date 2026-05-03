import SwiftUI

struct ProLockedCard<Actions: View>: View {
    @Environment(SubscriptionState.self) private var subscriptionState

    let title: String
    let message: String
    let systemImage: String
    @ViewBuilder let actions: Actions

    init(
        title: String,
        message: String,
        systemImage: String = "lock.fill",
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = actions()
    }

    init(
        title: String,
        message: String,
        systemImage: String = "lock.fill"
    ) where Actions == ProLockedCardDefaultActions {
        self.init(title: title, message: message, systemImage: systemImage) {
            ProLockedCardDefaultActions()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(WGJTheme.accentGold)
                .frame(width: 42, height: 42)
                .background {
                    Circle()
                        .fill(WGJTheme.cardElevated.opacity(0.9))
                }

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            actions
        }
        .padding(WGJSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer()
    }
}

struct ProLockedCardDefaultActions: View {
    @Environment(SubscriptionState.self) private var subscriptionState

    var body: some View {
        Button {
            subscriptionState.presentPaywall()
        } label: {
            Label("Unlock Pro", systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJPrimaryButtonStyle())
        .accessibilityIdentifier("pro-locked-card-unlock-button")
    }
}
