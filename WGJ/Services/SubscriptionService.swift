import Foundation
import RevenueCat

nonisolated struct SubscriptionCustomerInfoSnapshot: Equatable, Sendable {
    var activeEntitlementIdentifiers: Set<String>
    var originalAppUserID: String?

    init(activeEntitlementIdentifiers: Set<String>, originalAppUserID: String? = nil) {
        self.activeEntitlementIdentifiers = activeEntitlementIdentifiers
        self.originalAppUserID = originalAppUserID
    }
}

nonisolated enum SubscriptionEntitlementPolicy {
    static func isPro(_ customerInfo: SubscriptionCustomerInfoSnapshot?) -> Bool {
        customerInfo?.activeEntitlementIdentifiers.contains(RevenueCatConfig.entitlementIdentifier) == true
    }
}

nonisolated enum SubscriptionServiceError: Error, Equatable, CustomStringConvertible {
    case notConfigured

    var description: String {
        switch self {
        case .notConfigured:
            return "notConfigured"
        }
    }
}

protocol SubscriptionServicing: AnyObject {
    func configureIfNeeded() throws
    func customerInfo() async throws -> SubscriptionCustomerInfoSnapshot
    func restorePurchases() async throws -> SubscriptionCustomerInfoSnapshot
}

final class RevenueCatSubscriptionService: SubscriptionServicing {
    private let isConfigured: () -> Bool
    private let configurePurchases: (String) throws -> Void
    private let customerInfoProvider: () async throws -> CustomerInfo
    private let restorePurchasesProvider: () async throws -> CustomerInfo
    private var didConfigure = false

    init(
        isConfigured: @escaping () -> Bool = { Purchases.isConfigured },
        configure: @escaping (String) throws -> Void = { key in
            Purchases.configure(withAPIKey: key)
        },
        customerInfoProvider: @escaping () async throws -> CustomerInfo = {
            try await Purchases.shared.customerInfo()
        },
        restorePurchasesProvider: @escaping () async throws -> CustomerInfo = {
            try await Purchases.shared.restorePurchases()
        }
    ) {
        self.isConfigured = isConfigured
        configurePurchases = configure
        self.customerInfoProvider = customerInfoProvider
        self.restorePurchasesProvider = restorePurchasesProvider
    }

    func configureIfNeeded() throws {
        guard !didConfigure else { return }
        guard !isConfigured() else {
            didConfigure = true
            return
        }

        let key = RevenueCatConfig.apiKey
        try RevenueCatConfig.validateReleaseAPIKey(key)
        try configurePurchases(key)
        didConfigure = true
    }

    func customerInfo() async throws -> SubscriptionCustomerInfoSnapshot {
        guard isConfiguredForRequests else {
            throw SubscriptionServiceError.notConfigured
        }

        return try await snapshot(from: customerInfoProvider())
    }

    func restorePurchases() async throws -> SubscriptionCustomerInfoSnapshot {
        guard isConfiguredForRequests else {
            throw SubscriptionServiceError.notConfigured
        }

        return try await snapshot(from: restorePurchasesProvider())
    }

    private var isConfiguredForRequests: Bool {
        didConfigure || isConfigured()
    }

    private func snapshot(from customerInfo: CustomerInfo) -> SubscriptionCustomerInfoSnapshot {
        SubscriptionCustomerInfoSnapshot(
            activeEntitlementIdentifiers: Set(customerInfo.entitlements.active.keys),
            originalAppUserID: customerInfo.originalAppUserId
        )
    }
}
