import Foundation
import Observation

nonisolated enum SubscriptionLifecycleRefreshPolicy {
    static func shouldRefresh(
        isPaywallPresented: Bool,
        isCustomerCenterPresented: Bool,
        isPurchaseThankYouPresented: Bool,
        isLoading: Bool
    ) -> Bool {
        !isPaywallPresented
            && !isCustomerCenterPresented
            && !isPurchaseThankYouPresented
            && !isLoading
    }
}

@MainActor
@Observable
final class SubscriptionState {
    static let shared = SubscriptionState(service: RevenueCatSubscriptionService())

    private let service: any SubscriptionServicing
    private(set) var customerInfo: SubscriptionCustomerInfoSnapshot?
    private(set) var isLoading = false
    private(set) var isConfigured = false
    private(set) var errorMessage: String?
    var isPaywallPresented = false
    var isCustomerCenterPresented = false
    var isPurchaseThankYouPresented = false
    private var isAwaitingOfferCodeVerification = false
    private var customerInfoObservationTask: Task<Void, Never>?
    private var purchaseThankYouPresentationTask: Task<Void, Never>?

    var isPro: Bool {
        SubscriptionEntitlementPolicy.isPro(customerInfo)
    }

    var shouldRefreshOnLifecycleActivation: Bool {
        SubscriptionLifecycleRefreshPolicy.shouldRefresh(
            isPaywallPresented: isPaywallPresented,
            isCustomerCenterPresented: isCustomerCenterPresented,
            isPurchaseThankYouPresented: isPurchaseThankYouPresented,
            isLoading: isLoading
        )
    }

    init(service: any SubscriptionServicing) {
        self.service = service
    }

    func configureIfNeeded() {
        do {
            try service.configureIfNeeded()
            isConfigured = true
            startCustomerInfoObservationIfNeeded()
            errorMessage = nil
        } catch {
            isConfigured = false
            errorMessage = String(describing: error)
        }
    }

    func refreshCustomerInfo() async {
        guard configureForRequest() else { return }
        await load { try await service.customerInfo() }
    }

    func restorePurchases() async {
        guard configureForRequest() else { return }
        await load { try await service.restorePurchases() }
    }

    func redeemOfferCode() {
        configureIfNeeded()
        guard isConfigured else { return }

        do {
            try service.presentOfferCodeRedemptionSheet()
            isAwaitingOfferCodeVerification = true
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func applyCustomerInfo(_ customerInfo: SubscriptionCustomerInfoSnapshot) {
        self.customerInfo = customerInfo
        errorMessage = nil
    }

    func applyCustomerInfoUpdate(_ customerInfo: SubscriptionCustomerInfoSnapshot) {
        let wasPro = isPro
        applyCustomerInfo(customerInfo)

        let isNewlyPro = !wasPro && SubscriptionEntitlementPolicy.isPro(customerInfo)
        if isNewlyPro && isAwaitingOfferCodeVerification {
            isAwaitingOfferCodeVerification = false
            presentPurchaseThankYou(afterPaywallDismissal: false)
        }
    }

    func applyVerifiedPurchaseCompletion(_ customerInfo: SubscriptionCustomerInfoSnapshot) {
        applyCustomerInfo(customerInfo)
        guard SubscriptionEntitlementPolicy.isPro(customerInfo) else { return }

        let shouldDelayThankYou = isPaywallPresented
        isPaywallPresented = false
        isAwaitingOfferCodeVerification = false
        presentPurchaseThankYou(afterPaywallDismissal: shouldDelayThankYou)
    }

    func dismissPurchaseThankYou() {
        purchaseThankYouPresentationTask?.cancel()
        purchaseThankYouPresentationTask = nil
        isPurchaseThankYouPresented = false
    }

    func recordError(_ error: Error) {
        errorMessage = String(describing: error)
    }

    func presentPaywall() {
        configureIfNeeded()
        guard isConfigured else { return }
        isPaywallPresented = true
    }

    private func load(_ operation: () async throws -> SubscriptionCustomerInfoSnapshot) async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            applyCustomerInfoUpdate(try await operation())
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func configureForRequest() -> Bool {
        configureIfNeeded()
        return isConfigured
    }

    private func startCustomerInfoObservationIfNeeded() {
        guard customerInfoObservationTask == nil else { return }

        customerInfoObservationTask = service.observeCustomerInfoUpdates { [weak self] customerInfo in
            await self?.applyCustomerInfoUpdate(customerInfo)
        }
    }

    private func presentPurchaseThankYou(afterPaywallDismissal shouldDelay: Bool) {
        purchaseThankYouPresentationTask?.cancel()
        guard shouldDelay else {
            isPurchaseThankYouPresented = true
            return
        }

        purchaseThankYouPresentationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isPurchaseThankYouPresented = true
            purchaseThankYouPresentationTask = nil
        }
    }

#if DEBUG
    func applyForTesting(_ customerInfo: SubscriptionCustomerInfoSnapshot) {
        self.customerInfo = customerInfo
        errorMessage = nil
    }
#endif
}
