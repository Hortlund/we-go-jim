import Foundation
import Observation

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

    var isPro: Bool {
        SubscriptionEntitlementPolicy.isPro(customerInfo)
    }

    init(service: any SubscriptionServicing) {
        self.service = service
    }

    func configureIfNeeded() {
        do {
            try service.configureIfNeeded()
            isConfigured = true
            errorMessage = nil
        } catch {
            isConfigured = false
            errorMessage = String(describing: error)
        }
    }

    func refreshCustomerInfo() async {
        await load { try await service.customerInfo() }
    }

    func restorePurchases() async {
        await load { try await service.restorePurchases() }
    }

    func applyCustomerInfo(_ customerInfo: SubscriptionCustomerInfoSnapshot) {
        self.customerInfo = customerInfo
        errorMessage = nil
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
            customerInfo = try await operation()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

#if DEBUG
    func applyForTesting(_ customerInfo: SubscriptionCustomerInfoSnapshot) {
        self.customerInfo = customerInfo
        errorMessage = nil
    }
#endif
}
