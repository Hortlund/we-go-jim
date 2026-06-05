import Testing
@testable import WGJ

struct SubscriptionStateTests {
    @Test
    func entitlementParserRequiresExactWeGoJimProIdentifier() {
        let active = SubscriptionCustomerInfoSnapshot(activeEntitlementIdentifiers: ["We Go Jim Pro"])
        let inactive = SubscriptionCustomerInfoSnapshot(activeEntitlementIdentifiers: ["we_go_jim_pro"])

        #expect(SubscriptionEntitlementPolicy.isPro(active) == true)
        #expect(SubscriptionEntitlementPolicy.isPro(inactive) == false)
    }

    @Test
    func productionAPIKeyPolicyAcceptsOnlyPlatformPublicKeys() {
        #expect(RevenueCatAPIKeyPolicy.isValidReleaseKey("appl_hLQVEpwIIHRMWePRAvutzpdrJcn") == true)
        #expect(RevenueCatAPIKeyPolicy.isValidReleaseKey("") == false)
        #expect(RevenueCatAPIKeyPolicy.isValidReleaseKey(" test_XUFcsPSSOoRjJduGqgMTQirLDjV ") == false)
    }

    @Test
    func apiKeyDescriptionIdentifiesBillingModeWithoutLeakingFullKey() {
        #expect(
            RevenueCatAPIKeyPolicy.diagnosticDescription(for: "test_XUFcsPSSOoRjJduGqgMTQirLDjV")
            == "RevenueCat Test Store (test_...LDjV)"
        )
        #expect(
            RevenueCatAPIKeyPolicy.diagnosticDescription(for: "appl_hLQVEpwIIHRMWePRAvutzpdrJcn")
            == "App Store/TestFlight (appl_...rJcn)"
        )
        #expect(
            RevenueCatAPIKeyPolicy.diagnosticDescription(for: "")
            == "Not configured"
        )
    }

    @MainActor
    @Test
    func revenueCatServiceThrowsBeforeSuccessfulConfiguration() async {
        let service = RevenueCatSubscriptionService(
            isConfigured: { false },
            configure: { _ in },
            customerInfoProvider: {
                throw SubscriptionTestError.unexpectedSDKAccess
            },
            restorePurchasesProvider: {
                throw SubscriptionTestError.unexpectedSDKAccess
            }
        )

        await #expect(throws: SubscriptionServiceError.notConfigured) {
            try await service.customerInfo()
        }

        await #expect(throws: SubscriptionServiceError.notConfigured) {
            try await service.restorePurchases()
        }
    }

    @MainActor
    @Test
    func stateRefreshStoresCustomerInfoAndClearsError() async {
        let service = SubscriptionServiceProbe(
            refreshResult: .success(SubscriptionCustomerInfoSnapshot(activeEntitlementIdentifiers: ["We Go Jim Pro"]))
        )
        let state = SubscriptionState(service: service)

        await state.refreshCustomerInfo()

        #expect(state.isPro == true)
        #expect(state.errorMessage == nil)
        #expect(service.configureCount == 1)
        #expect(service.refreshCount == 1)
    }

    @MainActor
    @Test
    func stateRefreshStoresConfigurationErrorInsteadOfRequestingUnconfiguredSDK() async {
        let service = SubscriptionServiceProbe(
            configureResult: .failure(SubscriptionTestError.invalidConfiguration),
            refreshResult: .success(SubscriptionCustomerInfoSnapshot(activeEntitlementIdentifiers: ["We Go Jim Pro"]))
        )
        let state = SubscriptionState(service: service)

        await state.refreshCustomerInfo()

        #expect(state.isPro == false)
        #expect(service.configureCount == 1)
        #expect(service.refreshCount == 0)
        #expect(state.errorMessage == "invalidConfiguration")
    }

    @MainActor
    @Test
    func restorePurchasesConfiguresRevenueCatBeforeRequestingRestore() async {
        let service = SubscriptionServiceProbe(
            refreshResult: .success(SubscriptionCustomerInfoSnapshot(activeEntitlementIdentifiers: ["We Go Jim Pro"]))
        )
        let state = SubscriptionState(service: service)

        await state.restorePurchases()

        #expect(state.isPro == true)
        #expect(service.configureCount == 1)
        #expect(service.restoreCount == 1)
        #expect(state.errorMessage == nil)
    }

    @MainActor
    @Test
    func stateRefreshKeepsPriorAccessAndStoresRecoverableError() async {
        let service = SubscriptionServiceProbe(refreshResult: .failure(SubscriptionTestError.offline))
        let state = SubscriptionState(service: service)
        state.applyForTesting(SubscriptionCustomerInfoSnapshot(activeEntitlementIdentifiers: ["We Go Jim Pro"]))

        await state.refreshCustomerInfo()

        #expect(state.isPro == true)
        #expect(state.errorMessage == "offline")
    }

    @MainActor
    @Test
    func presentPaywallConfiguresRevenueCatBeforePresentation() {
        let service = SubscriptionServiceProbe(refreshResult: .failure(SubscriptionTestError.offline))
        let state = SubscriptionState(service: service)

        state.presentPaywall()

        #expect(service.configureCount == 1)
        #expect(state.isPaywallPresented == true)
        #expect(state.errorMessage == nil)
    }

    @MainActor
    @Test
    func presentPaywallStoresConfigurationErrorInsteadOfPresentingUnconfiguredSDK() {
        let service = SubscriptionServiceProbe(
            configureResult: .failure(SubscriptionTestError.invalidConfiguration),
            refreshResult: .failure(SubscriptionTestError.offline)
        )
        let state = SubscriptionState(service: service)

        state.presentPaywall()

        #expect(service.configureCount == 1)
        #expect(state.isPaywallPresented == false)
        #expect(state.errorMessage == "invalidConfiguration")
    }

    @MainActor
    @Test
    func redeemOfferCodeConfiguresRevenueCatBeforePresentingSheet() {
        let service = SubscriptionServiceProbe(refreshResult: .failure(SubscriptionTestError.offline))
        let state = SubscriptionState(service: service)

        state.redeemOfferCode()

        #expect(service.configureCount == 1)
        #expect(service.redeemOfferCodeCount == 1)
        #expect(state.errorMessage == nil)
    }

    @MainActor
    @Test
    func redeemOfferCodeStoresConfigurationErrorInsteadOfPresentingUnconfiguredSDK() {
        let service = SubscriptionServiceProbe(
            configureResult: .failure(SubscriptionTestError.invalidConfiguration),
            refreshResult: .failure(SubscriptionTestError.offline)
        )
        let state = SubscriptionState(service: service)

        state.redeemOfferCode()

        #expect(service.configureCount == 1)
        #expect(service.redeemOfferCodeCount == 0)
        #expect(state.errorMessage == "invalidConfiguration")
    }

    @MainActor
    @Test
    func verifiedPurchaseCompletionPresentsThankYouOnlyWhenProIsActive() {
        let service = SubscriptionServiceProbe(refreshResult: .failure(SubscriptionTestError.offline))
        let state = SubscriptionState(service: service)

        state.applyVerifiedPurchaseCompletion(
            SubscriptionCustomerInfoSnapshot(activeEntitlementIdentifiers: ["We Go Jim Pro"])
        )

        #expect(state.isPro == true)
        #expect(state.isPaywallPresented == false)
        #expect(state.isPurchaseThankYouPresented == true)
    }

    @MainActor
    @Test
    func offerCodeCustomerInfoUpdatePresentsThankYouAfterProAccessArrives() {
        let service = SubscriptionServiceProbe(refreshResult: .failure(SubscriptionTestError.offline))
        let state = SubscriptionState(service: service)

        state.redeemOfferCode()
        state.applyCustomerInfoUpdate(
            SubscriptionCustomerInfoSnapshot(activeEntitlementIdentifiers: ["We Go Jim Pro"])
        )

        #expect(state.isPro == true)
        #expect(state.isPurchaseThankYouPresented == true)
    }

    @MainActor
    @Test
    func offerCodeRefreshPresentsThankYouAfterProAccessArrives() async {
        let service = SubscriptionServiceProbe(
            refreshResult: .success(SubscriptionCustomerInfoSnapshot(activeEntitlementIdentifiers: ["We Go Jim Pro"]))
        )
        let state = SubscriptionState(service: service)

        state.redeemOfferCode()
        await state.refreshCustomerInfo()

        #expect(state.isPro == true)
        #expect(state.isPurchaseThankYouPresented == true)
    }

    @MainActor
    @Test
    func normalRefreshToExistingProDoesNotPresentPurchaseThankYou() async {
        let service = SubscriptionServiceProbe(
            refreshResult: .success(SubscriptionCustomerInfoSnapshot(activeEntitlementIdentifiers: ["We Go Jim Pro"]))
        )
        let state = SubscriptionState(service: service)

        await state.refreshCustomerInfo()

        #expect(state.isPro == true)
        #expect(state.isPurchaseThankYouPresented == false)
    }

    @Test
    func lifecycleRefreshSkipsWhileRevenueCatPresentationIsActive() {
        #expect(
            !SubscriptionLifecycleRefreshPolicy.shouldRefresh(
                isPaywallPresented: true,
                isCustomerCenterPresented: false,
                isPurchaseThankYouPresented: false,
                isLoading: false
            )
        )
        #expect(
            !SubscriptionLifecycleRefreshPolicy.shouldRefresh(
                isPaywallPresented: false,
                isCustomerCenterPresented: true,
                isPurchaseThankYouPresented: false,
                isLoading: false
            )
        )
        #expect(
            !SubscriptionLifecycleRefreshPolicy.shouldRefresh(
                isPaywallPresented: false,
                isCustomerCenterPresented: false,
                isPurchaseThankYouPresented: true,
                isLoading: false
            )
        )
        #expect(
            !SubscriptionLifecycleRefreshPolicy.shouldRefresh(
                isPaywallPresented: false,
                isCustomerCenterPresented: false,
                isPurchaseThankYouPresented: false,
                isLoading: true
            )
        )
        #expect(
            SubscriptionLifecycleRefreshPolicy.shouldRefresh(
                isPaywallPresented: false,
                isCustomerCenterPresented: false,
                isPurchaseThankYouPresented: false,
                isLoading: false
            )
        )
    }
}

private enum SubscriptionTestError: Error, CustomStringConvertible {
    case invalidConfiguration
    case offline
    case unexpectedSDKAccess

    var description: String {
        switch self {
        case .invalidConfiguration:
            return "invalidConfiguration"
        case .offline:
            return "offline"
        case .unexpectedSDKAccess:
            return "unexpected SDK access"
        }
    }
}

private final class SubscriptionServiceProbe: SubscriptionServicing {
    var configureCount = 0
    var refreshCount = 0
    var restoreCount = 0
    var redeemOfferCodeCount = 0
    var observeCustomerInfoUpdatesCount = 0
    let configureResult: Result<Void, Error>
    let refreshResult: Result<SubscriptionCustomerInfoSnapshot, Error>

    init(
        configureResult: Result<Void, Error> = .success(()),
        refreshResult: Result<SubscriptionCustomerInfoSnapshot, Error>
    ) {
        self.configureResult = configureResult
        self.refreshResult = refreshResult
    }

    func configureIfNeeded() throws {
        configureCount += 1
        try configureResult.get()
    }

    func customerInfo() async throws -> SubscriptionCustomerInfoSnapshot {
        refreshCount += 1
        return try refreshResult.get()
    }

    func restorePurchases() async throws -> SubscriptionCustomerInfoSnapshot {
        restoreCount += 1
        return try await customerInfo()
    }

    func presentOfferCodeRedemptionSheet() throws {
        redeemOfferCodeCount += 1
    }

    func observeCustomerInfoUpdates(
        _ handler: @escaping @Sendable (SubscriptionCustomerInfoSnapshot) async -> Void
    ) -> Task<Void, Never> {
        observeCustomerInfoUpdatesCount += 1
        return Task {}
    }
}
