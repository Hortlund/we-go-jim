import RevenueCat
import RevenueCatUI
import SwiftUI

struct RevenueCatPaywallSheet: View {
    let subscriptionState: SubscriptionState

    var body: some View {
        PaywallView(displayCloseButton: true)
            .onPurchaseCompleted { (customerInfo: CustomerInfo) in
                completePurchase(customerInfo)
            }
            .onRestoreCompleted { (customerInfo: CustomerInfo) in
                restore(customerInfo)
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

    private func completePurchase(_ customerInfo: CustomerInfo) {
        let snapshot = SubscriptionCustomerInfoSnapshot(customerInfo: customerInfo)
        subscriptionState.applyVerifiedPurchaseCompletion(snapshot)
    }

    private func restore(_ customerInfo: CustomerInfo) {
        let snapshot = SubscriptionCustomerInfoSnapshot(customerInfo: customerInfo)
        subscriptionState.applyCustomerInfo(snapshot)
        if SubscriptionEntitlementPolicy.isPro(snapshot) {
            subscriptionState.isPaywallPresented = false
        }
    }
}

struct SubscriptionPurchaseThankYouSheet: View {
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            WGJTheme.bgBase
                .ignoresSafeArea()

            SubscriptionThankYouConfettiOverlay()
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [WGJTheme.accentGold, WGJTheme.accentCyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 92, height: 92)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(WGJTheme.textInverse)
                }

                VStack(spacing: 8) {
                    Text("Welcome to Pro")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Thanks for supporting We Go Jim. Your Pro access is verified and ready, bro.")
                        .font(.body)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: dismiss) {
                    Label("Start Training", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .accessibilityIdentifier("subscription-thank-you-dismiss-button")
            }
            .padding(22)
            .frame(maxWidth: 430)
            .accessibilityIdentifier("subscription-thank-you-sheet")
        }
        .presentationDragIndicator(.visible)
    }
}

private struct SubscriptionThankYouConfettiOverlay: View {
    @State private var animate = false

    private let pieces = SubscriptionThankYouConfettiPiece.random(seed: 41, count: 72)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: piece.cornerRadius, style: .continuous)
                        .fill(piece.color)
                        .frame(width: piece.width, height: piece.height)
                        .rotationEffect(.degrees(animate ? piece.endRotation : piece.startRotation))
                        .position(
                            x: proxy.size.width * piece.startX,
                            y: animate ? proxy.size.height * piece.endY : -24
                        )
                        .opacity(animate ? 0 : 1)
                        .animation(
                            .easeOut(duration: piece.duration)
                                .delay(piece.delay),
                            value: animate
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .onAppear {
            animate = true
        }
    }
}

private struct SubscriptionThankYouConfettiPiece: Identifiable {
    let id: Int
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let startX: CGFloat
    let endY: CGFloat
    let startRotation: Double
    let endRotation: Double
    let delay: Double
    let duration: Double
    let color: Color

    static func random(seed: UInt64, count: Int) -> [SubscriptionThankYouConfettiPiece] {
        var generator = SubscriptionThankYouConfettiRandom(seed: seed)
        let colors = [WGJTheme.accentGold, WGJTheme.accentCyan, WGJTheme.accentBlue, WGJTheme.success]

        return (0..<count).map { index in
            let width = generator.value(in: CGFloat(6)...CGFloat(13))
            let height = generator.value(in: CGFloat(9)...CGFloat(21))
            return SubscriptionThankYouConfettiPiece(
                id: index,
                width: width,
                height: height,
                cornerRadius: min(width, height) * generator.value(in: 0.2...0.48),
                startX: generator.value(in: CGFloat(0.04)...CGFloat(0.96)),
                endY: generator.value(in: CGFloat(0.55)...CGFloat(1.1)),
                startRotation: generator.value(in: -80...80),
                endRotation: generator.value(in: 220...840) * (generator.nextBool() ? 1 : -1),
                delay: generator.value(in: 0...0.28),
                duration: generator.value(in: 1.65...2.8),
                color: colors[index % colors.count]
            )
        }
    }
}

private struct SubscriptionThankYouConfettiRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func nextBool() -> Bool {
        nextUnit() >= 0.5
    }

    mutating func value(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextUnit() * (range.upperBound - range.lowerBound)
    }

    mutating func value(in range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat(value(in: Double(range.lowerBound)...Double(range.upperBound)))
    }

    private mutating func nextUnit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64.max >> 11)
    }
}
