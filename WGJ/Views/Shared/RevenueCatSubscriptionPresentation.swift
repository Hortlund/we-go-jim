import RevenueCat
import RevenueCatUI
import SwiftUI

struct RevenueCatPaywallSheet: View {
    let subscriptionState: SubscriptionState

    var body: some View {
        PaywallView(displayCloseButton: true)
            .onPurchaseCompleted { (customerInfo: CustomerInfo) in
                apply(customerInfo)
            }
            .onRestoreCompleted { (customerInfo: CustomerInfo) in
                apply(customerInfo)
            }
            .onPurchaseFailure { error in
                subscriptionState.recordError(error)
            }
            .onRestoreFailure { error in
                subscriptionState.recordError(error)
            }
            .onRequestedDismissal {
                subscriptionState.isPaywallPresented = false
            }
            .accessibilityIdentifier("revenuecat-paywall-sheet")
    }

    private func apply(_ customerInfo: CustomerInfo) {
        let snapshot = SubscriptionCustomerInfoSnapshot(customerInfo: customerInfo)
        subscriptionState.applyCustomerInfo(snapshot)
        if SubscriptionEntitlementPolicy.isPro(snapshot) {
            subscriptionState.isPaywallPresented = false
        }
    }
}
