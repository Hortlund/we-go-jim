# RevenueCat Pro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate RevenueCat and gate We Go Jim Pro features while keeping the core workout loop local-first and free.

**Architecture:** RevenueCat is configured at app startup, then app-facing subscription access flows through a small root-owned observable state. Feature gates use pure policy helpers at action boundaries, and SwiftUI surfaces show locked Pro cards or RevenueCat Paywalls instead of running direct StoreKit purchase flows.

**Tech Stack:** SwiftUI, SwiftData, RevenueCat 5.x, RevenueCatUI, StoreKit/App Store Connect product configuration, Swift Testing, XCTest UI tests.

---

## File Structure

- Modify `WGJ.xcodeproj/project.pbxproj`: add SPM package `purchases-ios-spm`, target products `RevenueCat` and `RevenueCatUI`, and In-App Purchase capability.
- Modify `WGJ/Models/AppRuntimeConfig.swift`: add RevenueCat keys, entitlement/product/offering constants, test override hooks, and a Release guard against `test_` keys.
- Create `WGJ/Services/SubscriptionService.swift`: configure RevenueCat, refresh customer info, restore purchases, parse entitlement status, and expose testable protocols.
- Create `WGJ/Models/SubscriptionState.swift`: root-owned observable subscription state with loading/error/customer/pro access flags and paywall presentation state.
- Create `WGJ/Models/ProAccessPolicy.swift`: pure policy helpers for template caps, widget gates, muscle map gates, Bros caps, and export/import gates.
- Create `WGJ/Views/Shared/ProLockedCard.swift`: reusable locked card with WGJ styling and an unlock callback.
- Create `WGJ/Views/Profile/ProSubscriptionView.swift`: subscription status, restore, paywall, and Customer Center controls.
- Modify `WGJ/WGJApp.swift`: configure RevenueCat in app init and inject subscription state.
- Modify `WGJ/ContentView.swift`: pass subscription state through the environment and refresh on main entry/scene activation without blocking startup.
- Modify `WGJ/Views/Profile/SettingsView.swift`: add Pro subscription management tile/section.
- Modify `WGJ/Views/Profile/ProfileView.swift`: gate Pro-only widgets and Coach Brief.
- Modify `WGJ/Views/Profile/ProfileWidgetManagerView.swift`: mark Pro widgets and present paywall when enabling/selecting locked widgets.
- Modify `WGJ/Views/Workout/WorkoutMuscleHeatmapCard.swift`: no logic change unless shared locked styling needs card parity.
- Modify `WGJ/Views/History/HistoryDetailView.swift`: gate History muscle map with locked card.
- Modify `WGJ/Views/Workout/WorkoutCompletionSummaryView.swift`: gate completion muscle heatmap with locked card.
- Modify `WGJ/Views/Templates/TemplatesOverviewView.swift`: gate new template and folder export/import entry points visible from overview.
- Modify `WGJ/Views/Templates/FolderDetailView.swift`: gate new template, add existing if it creates over-cap indirectly, and folder export.
- Modify `WGJ/Views/Templates/TemplateDetailView.swift`: gate duplicate/export actions.
- Modify `WGJ/Views/Workout/StartWorkoutHomeView.swift`: gate save-completed-workout-as-template if the free cap is reached.
- Modify `WGJ/Views/Bros/BrosView.swift`: cap free member limits at 2, show Pro copy, and block join/create/manage paths above free cap.
- Add `WGJTests/SubscriptionStateTests.swift`: entitlement parsing and state refresh behavior.
- Add `WGJTests/ProAccessPolicyTests.swift`: pure gate behavior.
- Modify existing `WGJUITests/WGJUITests.swift`: add smoke coverage for Settings Pro entry, template cap lock, Profile muscle-map lock, History lock, completion lock, and Bros free cap.

## StoreKit And RevenueCat Configuration

- [ ] **Step 1: Configure Apple products outside the app code**

In App Store Connect, create auto-renewable subscriptions in one subscription group:

```text
Product ID: monthly
Reference name: We Go Jim Pro Monthly

Product ID: yearly
Reference name: We Go Jim Pro Yearly
```

Expected: both products exist in the same subscription group and are ready for sandbox/TestFlight validation.

- [ ] **Step 2: Configure RevenueCat dashboard outside the app code**

Create/verify:

```text
Entitlement identifier: We Go Jim Pro
Offering identifier: default
Monthly package product: monthly
Yearly package product: yearly
Paywall: attached to default offering
Customer Center: enabled if the current RevenueCat plan supports it
```

Expected: RevenueCat Dashboard shows both products attached to entitlement `We Go Jim Pro`, and the default offering has monthly/yearly packages.

- [ ] **Step 3: Do not add direct StoreKit purchase flows**

Keep StoreKit as the Apple product backend. In app code, purchases, restores, paywalls, and entitlement checks must go through RevenueCat.

Expected: no new `Product.purchase()` flow is introduced.

## Task 1: Add RevenueCat Package And Runtime Constants

**Files:**
- Modify: `WGJ.xcodeproj/project.pbxproj`
- Modify: `WGJ/Models/AppRuntimeConfig.swift`

- [ ] **Step 1: Add package reference and products**

Add package reference:

```pbxproj
repositoryURL = "https://github.com/RevenueCat/purchases-ios-spm.git";
requirement = {
    kind = upToNextMajorVersion;
    minimumVersion = 5.0.0;
};
```

Add package products to the `WGJ` app target:

```text
RevenueCat
RevenueCatUI
```

Expected: `import RevenueCat` and `import RevenueCatUI` can compile in app source files.

- [ ] **Step 2: Enable In-App Purchase capability**

Add target capability:

```pbxproj
com.apple.InAppPurchase = {
    enabled = 1;
};
```

Expected: Xcode target has In-App Purchase enabled alongside iCloud/CloudKit and Push.

- [ ] **Step 3: Add runtime constants**

Add to `AppRuntimeConfig`:

```swift
nonisolated enum RevenueCatConfig {
    static let entitlementIdentifier = "We Go Jim Pro"
    static let defaultOfferingIdentifier = "default"
    static let monthlyProductIdentifier = "monthly"
    static let yearlyProductIdentifier = "yearly"

    static var apiKey: String {
        if let override = ProcessInfo.processInfo.environment["WGJ_REVENUECAT_API_KEY"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }

        #if DEBUG
        return "test_XUFcsPSSOoRjJduGqgMTQirLDjV"
        #else
        return Bundle.main.object(forInfoDictionaryKey: "WGJRevenueCatAPIKey") as? String ?? ""
        #endif
    }

    static func validateReleaseAPIKey(_ key: String = apiKey) throws {
        #if !DEBUG
        if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || key.hasPrefix("test_") {
            throw RevenueCatConfigurationError.invalidReleaseAPIKey
        }
        #endif
    }
}

nonisolated enum RevenueCatConfigurationError: Error, Equatable {
    case invalidReleaseAPIKey
}
```

Expected: Debug builds use the provided test key, Release builds require a real key.

## Task 2: Add Subscription Service And State With Tests

**Files:**
- Create: `WGJ/Services/SubscriptionService.swift`
- Create: `WGJ/Models/SubscriptionState.swift`
- Create: `WGJTests/SubscriptionStateTests.swift`
- Modify: `WGJ/WGJApp.swift`
- Modify: `WGJ/ContentView.swift`

- [ ] **Step 1: Write failing entitlement parser tests**

Create `WGJTests/SubscriptionStateTests.swift`:

```swift
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
}

private enum SubscriptionTestError: Error, CustomStringConvertible {
    case offline
    var description: String { "offline" }
}

private final class SubscriptionServiceProbe: SubscriptionServicing {
    var refreshCount = 0
    let refreshResult: Result<SubscriptionCustomerInfoSnapshot, Error>

    init(refreshResult: Result<SubscriptionCustomerInfoSnapshot, Error>) {
        self.refreshResult = refreshResult
    }

    func configureIfNeeded() throws { }

    func customerInfo() async throws -> SubscriptionCustomerInfoSnapshot {
        refreshCount += 1
        return try refreshResult.get()
    }

    func restorePurchases() async throws -> SubscriptionCustomerInfoSnapshot {
        try await customerInfo()
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2' -only-testing:WGJTests/SubscriptionStateTests
```

Expected: FAIL because `SubscriptionState`, `SubscriptionServicing`, and snapshot types do not exist.

- [ ] **Step 3: Implement service-facing types**

Create `WGJ/Services/SubscriptionService.swift`:

```swift
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

protocol SubscriptionServicing: AnyObject {
    func configureIfNeeded() throws
    func customerInfo() async throws -> SubscriptionCustomerInfoSnapshot
    func restorePurchases() async throws -> SubscriptionCustomerInfoSnapshot
}

final class RevenueCatSubscriptionService: SubscriptionServicing {
    private var didConfigure = false

    func configureIfNeeded() throws {
        guard !didConfigure else { return }
        let key = RevenueCatConfig.apiKey
        try RevenueCatConfig.validateReleaseAPIKey(key)
        Purchases.configure(withAPIKey: key)
        didConfigure = true
    }

    func customerInfo() async throws -> SubscriptionCustomerInfoSnapshot {
        try await snapshot(from: Purchases.shared.customerInfo())
    }

    func restorePurchases() async throws -> SubscriptionCustomerInfoSnapshot {
        try await snapshot(from: Purchases.shared.restorePurchases())
    }

    private func snapshot(from customerInfo: CustomerInfo) -> SubscriptionCustomerInfoSnapshot {
        SubscriptionCustomerInfoSnapshot(
            activeEntitlementIdentifiers: Set(customerInfo.entitlements.active.keys),
            originalAppUserID: customerInfo.originalAppUserId
        )
    }
}
```

- [ ] **Step 4: Implement observable state**

Create `WGJ/Models/SubscriptionState.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class SubscriptionState {
    static let shared = SubscriptionState(service: RevenueCatSubscriptionService())

    private let service: any SubscriptionServicing
    private(set) var customerInfo: SubscriptionCustomerInfoSnapshot?
    private(set) var isLoading = false
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshCustomerInfo() async {
        await load { try await service.customerInfo() }
    }

    func restorePurchases() async {
        await load { try await service.restorePurchases() }
    }

    func presentPaywall() {
        isPaywallPresented = true
    }

    private func load(_ operation: () async throws -> SubscriptionCustomerInfoSnapshot) async {
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
```

- [ ] **Step 5: Wire root startup**

In `WGJApp.init()`:

```swift
SubscriptionState.shared.configureIfNeeded()
```

In `ContentView`, add:

```swift
@State private var subscriptionState = SubscriptionState.shared
```

Inject:

```swift
.environment(subscriptionState)
```

Refresh after main entry and scene activation:

```swift
Task { await subscriptionState.refreshCustomerInfo() }
```

Expected: RevenueCat config is app-root owned and refreshes do not block model-container bootstrap.

- [ ] **Step 6: Run tests and verify GREEN**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2' -only-testing:WGJTests/SubscriptionStateTests
```

Expected: PASS.

## Task 3: Add Pure Pro Access Policies

**Files:**
- Create: `WGJ/Models/ProAccessPolicy.swift`
- Create: `WGJTests/ProAccessPolicyTests.swift`

- [ ] **Step 1: Write failing policy tests**

Create `WGJTests/ProAccessPolicyTests.swift`:

```swift
import Testing
@testable import WGJ

struct ProAccessPolicyTests {
    @Test
    func freeTemplateCreationAllowsOnlyFirstFourTemplates() {
        #expect(ProAccessPolicy.canCreateTemplate(currentTemplateCount: 3, isPro: false))
        #expect(!ProAccessPolicy.canCreateTemplate(currentTemplateCount: 4, isPro: false))
        #expect(ProAccessPolicy.canCreateTemplate(currentTemplateCount: 40, isPro: true))
    }

    @Test
    func existingTemplatesStayUsableEvenAboveFreeCap() {
        #expect(ProAccessPolicy.canUseExistingTemplate(isPro: false))
    }

    @Test
    func freeBrosMemberLimitIsTwoAndProUsesSocialRuleMaximum() {
        #expect(ProAccessPolicy.maximumBrosMemberLimit(isPro: false) == 2)
        #expect(ProAccessPolicy.maximumBrosMemberLimit(isPro: true) == BrosSocialRules.maxMemberLimit)
        #expect(ProAccessPolicy.canUseBrosCircle(memberCount: 2, memberLimit: 2, isPro: false))
        #expect(!ProAccessPolicy.canUseBrosCircle(memberCount: 3, memberLimit: 3, isPro: false))
    }

    @Test
    func advancedProfileWidgetsRequirePro() {
        #expect(!ProAccessPolicy.requiresPro(.prs))
        #expect(!ProAccessPolicy.requiresPro(.weeklyGoals))
        #expect(ProAccessPolicy.requiresPro(.weeklyMuscleHeatmap))
        #expect(ProAccessPolicy.requiresPro(.coachBrief))
        #expect(ProAccessPolicy.requiresPro(.exerciseOneRMTrend))
        #expect(ProAccessPolicy.requiresPro(.exerciseVolumeTrend))
        #expect(ProAccessPolicy.requiresPro(.streaks))
        #expect(ProAccessPolicy.requiresPro(.topExercises))
        #expect(ProAccessPolicy.requiresPro(.consistencyCalendar))
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2' -only-testing:WGJTests/ProAccessPolicyTests
```

Expected: FAIL because `ProAccessPolicy` does not exist.

- [ ] **Step 3: Implement policy**

Create `WGJ/Models/ProAccessPolicy.swift`:

```swift
import Foundation

nonisolated enum ProAccessPolicy {
    static let freeTemplateLimit = 4
    static let freeBrosMemberLimit = 2

    static func canCreateTemplate(currentTemplateCount: Int, isPro: Bool) -> Bool {
        isPro || currentTemplateCount < freeTemplateLimit
    }

    static func canImportTemplates(currentTemplateCount: Int, importingCount: Int, isPro: Bool) -> Bool {
        isPro || currentTemplateCount + importingCount <= freeTemplateLimit
    }

    static func canUseExistingTemplate(isPro: Bool) -> Bool {
        true
    }

    static func canExportTemplates(isPro: Bool) -> Bool {
        isPro
    }

    static func requiresPro(_ widgetKind: ProfileWidgetKind) -> Bool {
        switch widgetKind {
        case .prs, .weeklyGoals:
            return false
        case .weeklyMuscleHeatmap, .coachBrief, .exerciseOneRMTrend, .exerciseVolumeTrend, .streaks, .topExercises, .consistencyCalendar:
            return true
        }
    }

    static func canShowMuscleMap(isPro: Bool) -> Bool {
        isPro
    }

    static func maximumBrosMemberLimit(isPro: Bool) -> Int {
        isPro ? BrosSocialRules.maxMemberLimit : freeBrosMemberLimit
    }

    static func canUseBrosCircle(memberCount: Int, memberLimit: Int, isPro: Bool) -> Bool {
        isPro || (memberCount <= freeBrosMemberLimit && memberLimit <= freeBrosMemberLimit)
    }

    static func canSetBrosMemberLimit(_ memberLimit: Int, currentMemberCount: Int, isPro: Bool) -> Bool {
        guard BrosSocialRules.canSetMemberLimit(memberLimit, currentMemberCount: currentMemberCount) else {
            return false
        }
        return isPro || memberLimit <= freeBrosMemberLimit
    }
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run the same `xcodebuild test` command.

Expected: PASS.

## Task 4: Add Paywall, Customer Center, And Subscription Settings UI

**Files:**
- Create: `WGJ/Views/Shared/ProLockedCard.swift`
- Create: `WGJ/Views/Profile/ProSubscriptionView.swift`
- Modify: `WGJ/Views/Profile/SettingsView.swift`
- Modify: `WGJUITests/WGJUITests.swift`

- [ ] **Step 1: Write failing UI smoke for Settings Pro tile**

Add a UI test:

```swift
@MainActor
func testSettingsShowsProSubscriptionEntry() throws {
    let app = launchApp(mode: .localInMemory)

    tapTab("Profile", in: app)
    let settingsTile = identifiedElement("profile-settings-tile", in: app)
    XCTAssertTrue(settingsTile.waitForExistence(timeout: 5))
    settingsTile.tap()

    XCTAssertTrue(identifiedElement("settings-pro-subscription-tile", in: app).waitForExistence(timeout: 5))
}
```

Expected RED: the Pro tile does not exist.

- [ ] **Step 2: Create locked card**

Create `ProLockedCard`:

```swift
import SwiftUI

struct ProLockedCard: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String
    let accessibilityID: String
    let onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader(title, subtitle: "We Go Jim Pro") {
                Image(systemName: systemImage)
                    .foregroundStyle(WGJTheme.accentGold)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onUnlock()
            } label: {
                Label(actionTitle, systemImage: "lock.open.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WGJPrimaryButtonStyle())
            .accessibilityIdentifier("\(accessibilityID)-unlock-button")
        }
        .padding(14)
        .wgjCardContainer()
        .accessibilityIdentifier(accessibilityID)
    }
}
```

- [ ] **Step 3: Create subscription view**

Create `ProSubscriptionView`:

```swift
import RevenueCatUI
import SwiftUI

struct ProSubscriptionView: View {
    @Environment(SubscriptionState.self) private var subscriptionState

    var body: some View {
        @Bindable var subscriptionState = subscriptionState

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("We Go Jim Pro", subtitle: subscriptionSubtitle)

                VStack(alignment: .leading, spacing: 12) {
                    infoRow("Status", value: subscriptionState.isPro ? "Active" : "Free")
                    if let appUserID = subscriptionState.customerInfo?.originalAppUserID {
                        infoRow("RevenueCat ID", value: appUserID)
                    }
                    if let error = subscriptionState.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.warning)
                    }
                    Button {
                        subscriptionState.presentPaywall()
                    } label: {
                        Label(subscriptionState.isPro ? "View Pro Plans" : "Unlock Pro", systemImage: "crown.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .accessibilityIdentifier("pro-unlock-button")

                    Button {
                        Task { await subscriptionState.restorePurchases() }
                    } label: {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                    .accessibilityIdentifier("pro-restore-button")

                    Button {
                        subscriptionState.isCustomerCenterPresented = true
                    } label: {
                        Label("Manage Subscription", systemImage: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                    .accessibilityIdentifier("pro-customer-center-button")
                }
                .padding(14)
                .wgjCardContainer(strong: true)
            }
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("We Go Jim Pro")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $subscriptionState.isPaywallPresented) {
            PaywallView()
                .onDisappear {
                    Task { await subscriptionState.refreshCustomerInfo() }
                }
        }
        .sheet(isPresented: $subscriptionState.isCustomerCenterPresented) {
            CustomerCenterView()
        }
        .task {
            await subscriptionState.refreshCustomerInfo()
        }
    }

    private var subscriptionSubtitle: String {
        subscriptionState.isPro
            ? "Pro is active. Manage billing, restores, and plan support here."
            : "Unlock unlimited templates, muscle maps, advanced analytics, and bigger Bros circles."
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(WGJTheme.textPrimary)
            Spacer()
            Text(value).foregroundStyle(WGJTheme.textSecondary)
        }
        .font(.subheadline)
    }
}
```

- [ ] **Step 4: Add Settings tile**

In `SettingsView`, add a `WGJNavigationTile` near the top:

```swift
WGJNavigationTile(
    title: "We Go Jim Pro",
    systemImage: "crown.fill",
    subtitle: subscriptionState.isPro
        ? "Pro is active. Manage subscription and support."
        : "Unlock templates, muscle maps, analytics, and bigger Bros circles.",
    accessibilityID: "settings-pro-subscription-tile"
) {
    ProSubscriptionView()
}
```

Add environment:

```swift
@Environment(SubscriptionState.self) private var subscriptionState
```

- [ ] **Step 5: Run UI smoke**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2' -only-testing:WGJUITests/WGJUITests/testSettingsShowsProSubscriptionEntry
```

Expected: PASS.

## Task 5: Gate Profile Widgets And Muscle Maps

**Files:**
- Modify: `WGJ/Views/Profile/ProfileView.swift`
- Modify: `WGJ/Views/Profile/ProfileWidgetManagerView.swift`
- Modify: `WGJ/Views/History/HistoryDetailView.swift`
- Modify: `WGJ/Views/Workout/WorkoutCompletionSummaryView.swift`
- Modify: `WGJUITests/WGJUITests.swift`

- [ ] **Step 1: Add failing UI tests for locked muscle maps**

Add tests that launch with local in-memory store and assert:

```swift
XCTAssertTrue(identifiedElement("profile-weekly-muscle-heatmap-pro-lock", in: app).waitForExistence(timeout: 5))
XCTAssertTrue(identifiedElement("history-muscle-heatmap-pro-lock", in: app).waitForExistence(timeout: 5))
XCTAssertTrue(identifiedElement("workout-completion-muscle-heatmap-pro-lock", in: app).waitForExistence(timeout: 5))
```

Expected RED: locked cards do not exist.

- [ ] **Step 2: Gate Profile widgets**

In `ProfileView`, add:

```swift
@Environment(SubscriptionState.self) private var subscriptionState
```

For `weeklyMuscleHeatmapWidget`:

```swift
private var weeklyMuscleHeatmapWidget: some View {
    if ProAccessPolicy.canShowMuscleMap(isPro: subscriptionState.isPro) {
        ProfileWeeklyMuscleHeatmapWidget(snapshot: dashboardContent.weeklyMuscleHeatmap)
    } else {
        ProLockedCard(
            title: "Muscle Map",
            message: "Muscle maps are a Pro feature. See which areas your week is hitting and where recovery might matter.",
            systemImage: "figure.strengthtraining.traditional",
            actionTitle: "Unlock Pro",
            accessibilityID: "profile-weekly-muscle-heatmap-pro-lock"
        ) {
            subscriptionState.presentPaywall()
        }
    }
}
```

For Pro-only widgets, return locked cards instead of loading heavy content when Free.

- [ ] **Step 3: Gate widget manager enable/select actions**

In `ProfileWidgetManagerView`, inject subscription state and block enabling `ProAccessPolicy.requiresPro(kind)` when Free:

```swift
guard subscriptionState.isPro || !ProAccessPolicy.requiresPro(kind) else {
    subscriptionState.presentPaywall()
    return
}
```

Expected: Free users see Pro value but do not enable Pro-only widgets.

- [ ] **Step 4: Gate History muscle map**

In `HistoryDetailView`, inject `SubscriptionState` and replace `workoutMuscleHeatmapCard`:

```swift
if let muscleHeatmap = snapshot?.muscleHeatmap {
    if subscriptionState.isPro {
        WorkoutMuscleHeatmapCard(
            title: "Muscle Map",
            subtitle: "Heatmap from completed working sets in this workout.",
            snapshot: muscleHeatmap,
            emptyMessage: "No completed working sets with muscle data for this workout."
        )
    } else {
        ProLockedCard(
            title: "Muscle Map",
            message: "Unlock Pro to see exactly which areas this workout hit.",
            systemImage: "figure.strengthtraining.traditional",
            actionTitle: "Unlock Pro",
            accessibilityID: "history-muscle-heatmap-pro-lock"
        ) {
            subscriptionState.presentPaywall()
        }
    }
}
```

- [ ] **Step 5: Gate completion summary muscle map**

In `WorkoutCompletionSummaryView`, inject `SubscriptionState` and replace `muscleHeatmapSection` similarly with accessibility ID `workout-completion-muscle-heatmap-pro-lock`.

- [ ] **Step 6: Run focused tests**

Run policy tests and UI smoke tests added in this task.

Expected: PASS.

## Task 6: Gate Templates, Imports, Exports, And Save-From-Workout

**Files:**
- Modify: `WGJ/Views/Templates/TemplatesOverviewView.swift`
- Modify: `WGJ/Views/Templates/FolderDetailView.swift`
- Modify: `WGJ/Views/Templates/TemplateDetailView.swift`
- Modify: `WGJ/Views/Workout/StartWorkoutHomeView.swift`
- Modify: `WGJ/Views/Workout/ActiveWorkoutTemplateSyncReviewSheet.swift`
- Modify: `WGJUITests/WGJUITests.swift`

- [ ] **Step 1: Add failing template cap UI test**

Seed or create 4 templates in a local in-memory UI run, tap New Template, and expect:

```swift
XCTAssertTrue(identifiedElement("template-limit-pro-lock", in: app).waitForExistence(timeout: 5))
```

Expected RED: cap lock does not exist.

- [ ] **Step 2: Add helper in template views**

In template entry views:

```swift
@Environment(SubscriptionState.self) private var subscriptionState
@State private var showingTemplateProLock = false
```

Before creating a template:

```swift
private func beginCreatingTemplate(folderID: UUID?) {
    guard ProAccessPolicy.canCreateTemplate(
        currentTemplateCount: allTemplates.count,
        isPro: subscriptionState.isPro
    ) else {
        showingTemplateProLock = true
        return
    }

    templateEditorContext = TemplateEditorContext(folderID: folderID, templateID: nil)
}
```

Present lock/paywall:

```swift
.sheet(isPresented: $showingTemplateProLock) {
    ProLockedCard(
        title: "Unlimited Templates",
        message: "Free includes 4 templates. Go Pro for unlimited templates, folders, imports, and exports.",
        systemImage: "doc.badge.plus",
        actionTitle: "Unlock Pro",
        accessibilityID: "template-limit-pro-lock"
    ) {
        showingTemplateProLock = false
        subscriptionState.presentPaywall()
    }
    .padding(16)
    .wgjSheetSurface()
}
```

- [ ] **Step 3: Gate duplicate and save-from-session**

Before duplicate or create-from-session actions, use the same template count policy. Existing templates remain viewable, editable, deletable, movable, and startable.

- [ ] **Step 4: Gate import/export**

Block template/folder export unless Pro:

```swift
guard ProAccessPolicy.canExportTemplates(isPro: subscriptionState.isPro) else {
    subscriptionState.presentPaywall()
    return
}
```

For import, estimate imported template count before saving when possible. If not easy in the first pass, block import for Free and allow Pro.

- [ ] **Step 5: Run focused template tests**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2' -only-testing:WGJTests/ProAccessPolicyTests -only-testing:WGJUITests/WGJUITests/testFreeTemplateCapShowsProLock
```

Expected: PASS.

## Task 7: Gate Bros Member Caps

**Files:**
- Modify: `WGJ/Views/Bros/BrosView.swift`
- Modify: `WGJTests/ProAccessPolicyTests.swift`
- Modify: `WGJUITests/WGJUITests.swift`

- [ ] **Step 1: Add failing UI test for free Bros cap**

Open Bros create-circle state in local UI mode and assert the member limit cannot be increased above 2 for Free:

```swift
XCTAssertTrue(app.staticTexts["Member limit: 2"].waitForExistence(timeout: 5))
XCTAssertTrue(identifiedElement("bros-member-limit-pro-copy", in: app).exists)
```

Expected RED: Pro copy does not exist and current stepper allows the full range.

- [ ] **Step 2: Cap create-circle binding**

In `BrosView`, inject subscription state and change free member limit range:

```swift
private var allowedMemberLimitRange: ClosedRange<Int> {
    BrosSocialRules.minMemberLimit ... ProAccessPolicy.maximumBrosMemberLimit(isPro: subscriptionState.isPro)
}
```

Use it for create and management steppers.

- [ ] **Step 3: Block join/manage above free cap**

Before join/create/update:

```swift
guard ProAccessPolicy.canSetBrosMemberLimit(
    requestedLimit,
    currentMemberCount: currentMemberCount,
    isPro: subscriptionState.isPro
) else {
    subscriptionState.presentPaywall()
    return
}
```

Show copy:

```swift
Text("Free Bros circles support 2 members. Go Pro to grow the circle.")
    .font(.caption)
    .foregroundStyle(WGJTheme.textSecondary)
    .accessibilityIdentifier("bros-member-limit-pro-copy")
```

- [ ] **Step 4: Preserve existing over-cap circles**

If the loaded snapshot is already above the free cap, do not modify CloudKit records automatically. Show the roster/feed, but block raising limits or inviting above current state and expose Pro copy in management.

- [ ] **Step 5: Run focused tests**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2' -only-testing:WGJTests/ProAccessPolicyTests -only-testing:WGJUITests/WGJUITests/testFreeBrosCircleCapsAtTwoMembers
```

Expected: PASS.

## Task 8: Full Build And RevenueCat Verification

**Files:**
- No planned source edits unless verification finds issues.

- [ ] **Step 1: Build**

Run:

```bash
xcodebuild build -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Run focused logic tests**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2' -only-testing:WGJTests/SubscriptionStateTests -only-testing:WGJTests/ProAccessPolicyTests
```

Expected: PASS.

- [ ] **Step 3: Run focused UI tests**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2' -only-testing:WGJUITests/WGJUITests/testSettingsShowsProSubscriptionEntry -only-testing:WGJUITests/WGJUITests/testFreeTemplateCapShowsProLock -only-testing:WGJUITests/WGJUITests/testFreeBrosCircleCapsAtTwoMembers
```

Expected: PASS.

- [ ] **Step 4: Manual RevenueCat smoke**

After dashboard setup, run the app and verify:

```text
Settings > We Go Jim Pro opens.
Unlock Pro presents RevenueCat Paywall.
Restore Purchases completes or returns a visible recoverable error.
Customer Center presents if configured for the project/plan.
After a test purchase/restore, customer info refresh makes `isPro == true`.
```

Expected: Paywall and Customer Center surfaces are functional with the configured RevenueCat project.

## Self-Review

- Spec coverage: covered SPM, API key, entitlement, products/offering, Paywall, Customer Center, customer info, error handling, template cap, muscle maps, Coach Brief/widgets, Bros cap, StoreKit boundary, and verification.
- Placeholder scan: clear of unresolved markers or unresolved file names.
- Type consistency: plan uses `SubscriptionState`, `SubscriptionServicing`, `SubscriptionCustomerInfoSnapshot`, `SubscriptionEntitlementPolicy`, and `ProAccessPolicy` consistently.
