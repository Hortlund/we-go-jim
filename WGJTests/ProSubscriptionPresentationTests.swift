import Testing
@testable import WGJ

struct ProSubscriptionPresentationTests {
    @Test
    func managementActionsKeepApplePrimaryAndCustomerCenterSecondary() {
        #expect(ProSubscriptionManagementPresentation.sectionTitle == "Subscription Management")
        #expect(ProSubscriptionManagementPresentation.sectionSubtitle == "Use Apple to manage or cancel App Store subscriptions. Customer Center can help with billing support, refunds, and save offers when available.")
        #expect(ProSubscriptionManagementPresentation.appleActionTitle == "Manage or Cancel Subscription")
        #expect(ProSubscriptionManagementPresentation.customerCenterActionTitle == "Billing Support & Offers")
    }
}
