# RevenueCat Pro Design

## Goal

Integrate RevenueCat into We Go Jim and introduce a clear `We Go Jim Pro` entitlement that unlocks premium training, analytics, template, and Bros features without breaking the local-first workout loop.

## RevenueCat Setup

- Swift Package URL: `https://github.com/RevenueCat/purchases-ios-spm.git`
- Package products: `RevenueCat` and `RevenueCatUI`
- Version rule: up to next major from `5.0.0`, matching RevenueCat's current iOS SPM guidance.
- Debug/Test API key: `test_XUFcsPSSOoRjJduGqgMTQirLDjV`
- Entitlement identifier: `We Go Jim Pro`
- Products:
  - `monthly`
  - `yearly`
- Offering:
  - `default`, with monthly and yearly packages attached.
- Dashboard setup:
  - Attach both products to the `We Go Jim Pro` entitlement.
  - Pair the default offering with a RevenueCat Paywall.
  - Configure Customer Center if the RevenueCat plan supports it.

Release builds must not ship with a `test_` RevenueCat key. WGJ should use a small runtime/config boundary so Debug/Test can use the provided key while Release either requires a production RevenueCat key or fails clearly during development.

## Architecture

RevenueCat state should be owned near the app root and flow through SwiftUI environment, matching WGJ's existing root-owned state pattern.

- Add a focused subscription state object, for example `SubscriptionState`, that stores:
  - latest `CustomerInfo`
  - `isPro`
  - loading state
  - last recoverable error message
- Add a focused service, for example `RevenueCatSubscriptionService`, that wraps:
  - SDK configuration
  - customer info refresh
  - restore purchases
  - entitlement checking for `We Go Jim Pro`
  - customer info update delegate callbacks
- Inject subscription state from `ContentView`/`WGJApp` into the environment. Do not add global singleton UI routing or scatter RevenueCat calls through feature views.
- Use `RevenueCatUI` for Paywall and Customer Center presentation. App-owned paywall triggers should be simple SwiftUI state, not custom StoreKit purchase flows.

## Free Tier

Free users keep the core training product:

- Unlimited workout logging.
- Active workout editing, completion, minimize, restore, rest timers, and basic completion flow.
- Exercise catalog search, detail, custom exercises, and filters.
- Basic history list and workout detail.
- Existing templates remain visible, editable, deletable, and startable.
- Up to 4 saved workout templates.
- Bros circles up to 2 members.
- Basic Profile stats:
  - PRs
  - weekly goals

## Pro Gates

Pro unlocks these v1 gates:

- Unlimited templates.
- Template creation after the fourth template.
- Template duplication after the fourth template.
- Creating a new template from a completed workout after the fourth template.
- Importing templates or folders when import would exceed the free cap.
- Template export/import and folder export.
- Profile muscle map widget.
- History workout muscle map.
- Workout completion summary muscle map.
- Coach Brief.
- Coach follow-up analysis.
- Advanced Profile dashboard widgets:
  - 1RM trend
  - Volume trend
  - Top exercises
  - Consistency calendar
  - Streaks
- Bros circles above 2 members.
- Raising a Bros member cap above 2.
- Joining a Bros circle whose current or configured member cap is above 2.
- Customer Center entry from Settings for subscription management.

Additional Pro surfaces that fit WGJ and can be included when the touched code path is already in scope:

- Advanced workout completion insights:
  - top muscles trained
  - recovery focus
  - volume PR callouts
- Historical analytics filters:
  - by muscle group
  - by exercise
  - by time window
- Personal record deep dives beyond the basic PR card.
- Custom Profile dashboard layout beyond the default free widgets.
- Bros premium enhancements later:
  - circle leaderboard
  - monthly circle recap
  - richer member stats
  - reaction history

## Gate Behavior

Template gates must block creation paths, not punish existing data.

- If a Free user already has more than 4 templates, do not hide, delete, lock, or mutate those templates.
- Allow view, start, edit, move, and delete for existing templates.
- Block new template creation, duplication, import, and save-from-workout when the user is at or above the Free cap.
- Show the RevenueCat Paywall at the moment the user asks for the Pro action.

Muscle map gates should preserve context.

- Profile, History detail, and Workout Completion should show a compact locked card where the muscle map would appear.
- The locked card should explain the Pro value in product terms and provide a button that opens the RevenueCat Paywall.
- Avoid hiding the feature entirely because the visible locked card is the conversion surface.

Bros gates should be conservative and review-safe.

- Free users can create a circle with a maximum member limit of 2.
- Free owners cannot raise the member cap above 2.
- Joining a circle with more than 2 members or a member limit above 2 requires Pro.
- If an existing circle is already above the Free cap and the user loses Pro, do not remove members or reduce the remote circle automatically. Block increasing/inviting/raising limits and show a Pro locked state for expanded management.
- Preserve local-only fallback. If CloudKit is unavailable, the app should still degrade exactly as it does today; RevenueCat must not make local workouts depend on cloud state.

Paywall presentation should be explicit and recoverable.

- Use RevenueCat Paywalls for conversion surfaces.
- Use `presentPaywallIfNeeded` or a manual `PaywallView` where it keeps the UI flow simple.
- Refresh customer info after purchase, restore, and paywall dismissal.
- Handle cancellation silently.
- Show recoverable purchase/restore errors in the local screen that initiated the action.

Customer Center should live in Settings.

- Add it when `RevenueCatUI` is available and the current RevenueCat plan supports Customer Center.
- Use it for restore, cancellation, refund, and subscription management support.
- Keep WGJ's existing Privacy, Support, Community Guidelines, Blocked Bros, and Delete My Data flows intact.

## Product Copy

Use direct copy that fits WGJ's tone:

- Pro title: `We Go Jim Pro`
- Paywall trigger examples:
  - `Unlock Pro`
  - `Go Pro`
  - `Manage Pro`
- Locked card examples:
  - `Muscle maps are a Pro feature. See which areas your session hit and where your week is trending.`
  - `Free includes 4 templates. Go Pro for unlimited templates, folders, imports, and exports.`
  - `Free Bros circles support 2 members. Go Pro to grow the circle.`

## Testing

Use Swift Testing for logic and XCTest for UI smoke coverage.

Required logic coverage:

- Entitlement parser marks Pro active only when `customerInfo.entitlements["We Go Jim Pro"]?.isActive == true`.
- Free template policy allows creation below 4 and blocks at 4.
- Pro template policy allows creation at or above 4.
- Existing templates remain usable when Free and over the cap.
- Free Bros policy caps member limit at 2.
- Pro Bros policy allows existing WGJ member limit range.
- Locked-widget policy identifies Pro-only widgets.

Required UI coverage:

- Settings shows Pro status and subscription management entry points.
- Free user at template cap sees paywall/locked copy when creating another template.
- Profile muscle map widget shows locked Pro card when Free.
- History detail muscle map shows locked Pro card when Free.
- Workout completion muscle map shows locked Pro card when Free.
- Bros free creation/member-limit controls cannot exceed 2 and show Pro copy for larger circles.

Verification:

- Build the WGJ app target after adding the Swift package.
- Run focused `WGJTests` for subscription, template policy, profile widget policy, and Bros policy.
- Run focused `WGJUITests` for Settings, template cap, and at least one locked muscle-map surface.
- RevenueCat live purchase flows need sandbox/Test Store validation on a simulator or device after dashboard products, offerings, and paywall are configured. State explicitly whether this was done.

## Risks And Tradeoffs

- The provided key is a Test Store key, so it is useful for development but not App Store submission.
- RevenueCat Paywalls and Customer Center depend on dashboard configuration. The app must show sane errors if offerings or paywall config are missing.
- Template and Bros gates touch persistence and CloudKit-adjacent flows. Gates should be policy checks at action boundaries rather than schema changes.
- Muscle map lock cards are intentionally visible conversion surfaces. They should be concise and not make the app feel broken.
- The active workout input path must stay free of RevenueCat network work and broad subscription refreshes.
