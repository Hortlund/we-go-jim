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
        #expect(service.refreshCount == 1)
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
        try await customerInfo()
    }
}
