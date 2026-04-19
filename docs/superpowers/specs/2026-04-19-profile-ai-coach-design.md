# Profile AI Coach Design

- Date: 2026-04-19
- Status: Draft approved in conversation, written for spec review
- Owner: Codex with user review pending

## Summary

WGJ should add an in-app AI coach surface that lives inside the existing Profile dashboard widget system and opens into a deeper analysis sheet. The feature should be strongest at two jobs:

1. Weekly coach recap.
2. Trend and plateau detection.

The shipped shape is "coach brief first": a high-signal weekly recap card in Profile, followed by supporting trend and watchlist details in a drill-down sheet. The system should use Apple Foundation Models for language generation and explanation, while keeping the underlying training analytics deterministic and local-first.

This feature must feel lightweight. It must never block workout logging, never depend on CloudKit, and always degrade to a deterministic non-AI summary when Apple Intelligence is unavailable.

## Product Goals

- Give the user a weekly recap that compares the last 7 days against their own recent baseline.
- Surface momentum and plateau signals without forcing the user to read raw charts first.
- Explain the top changes in plain language, without acting like a full programming coach.
- Keep the AI layer additive, fast, and optional.
- Reuse WGJ's existing profile widget and local analytics architecture instead of creating a parallel coach subsystem.

## Non-Goals

- No active-workout AI dependency.
- No freeform coach chat in v1.
- No concrete program prescriptions such as exercise swaps, split rewrites, or set/rep programming.
- No system Home Screen or Lock Screen widget work in this phase.
- No CloudKit dependency for recap generation or storage.
- No Core ML custom predictor in v1.

## User Decisions Captured

- AI can be unavailable on unsupported devices. That is acceptable.
- "Widget" means WGJ's in-app profile widget, not WidgetKit.
- The feature should use AI aggressively where it adds value, but without making the app heavy or slow.
- AI should not participate in active workout flows.
- The feature should be strongest at weekly recap and trend or plateau detection.
- Recommendations should stay broad and explanatory, not prescriptive.
- The main surface should live in Profile as a widget plus a deeper sheet.
- Refresh should compute analytics continuously enough to stay cheap, but only generate AI recaps on workout finish and when the profile widget opens with stale data.
- The visual direction is "Coach Brief First", not "Stats First".
- Weekly recap should compare the current week against a rolling recent baseline.
- The drill-down sheet should offer tappable follow-up prompts, not freeform chat.

## Existing Repo Fit

WGJ already has the core ingredients needed for this feature:

- Rule-based guidance lives in `WGJ/Services/TrainingGuidanceService.swift`.
- Local projected history facts live in `WGJ/Services/HistoryAnalyticsProjector.swift`.
- Profile/dashboard metrics and trend series live in `WGJ/Services/WorkoutMetricsService.swift`.
- The in-app widget shell already exists in `WGJ/Views/Profile/ProfileView.swift`, `WGJ/Views/Profile/ProfileWidgetManagerView.swift`, and `WGJ/Models/UserDomainModels.swift`.
- The app is explicitly local-first, with CloudKit as additive behavior, so the feature must preserve that constraint.

This makes WGJ a strong fit for a deterministic analytics core plus an AI explanation layer.

## Options Considered

### Option 1: Deterministic analytics core plus Foundation Models explanation

Compute trend and plateau facts in app code, then use Apple Foundation Models to generate the recap and short explanations from a compact snapshot.

Pros:

- Best fit for WGJ's local-first architecture.
- Fast and testable because the model is not the source of truth.
- Easier to cache.
- Easier to verify and debug.

Cons:

- Requires extra snapshot design work.
- Less flashy than letting the model infer everything directly.

### Option 2: Foundation Models infer both the facts and the language

Prompt the on-device model with more raw history and let it produce recap plus trend calls in one pass.

Pros:

- Faster prototype.
- Minimal deterministic insight modeling at first.

Cons:

- Worse fit for long-term reliability.
- Harder to test.
- More fragile as history grows because prompt size grows with raw history.
- More likely to drift or hallucinate edge cases.

### Option 3: Core ML predictor plus Foundation Models explainer

Train a custom predictive model for plateau risk or momentum scoring, then use Foundation Models to explain the results.

Pros:

- Strong future phase for deeper personalization.
- Most "AI-rich" end state.

Cons:

- Heavy first phase.
- Needs feature engineering, training workflow, evaluation, and cold-start handling.
- More operational complexity than v1 needs.

## Recommended Approach

Ship Option 1 first.

WGJ should compute a compact weekly insight snapshot from local history and use Foundation Models only to narrate and explain that snapshot. This captures the strongest user-facing AI value while preserving deterministic analytics, performance, and local fallback behavior.

The design should leave room for Option 3 later by keeping the UI and output contracts stable. If a future Core ML model is added, it can feed the same insight snapshot shape or the same derived narrative inputs without changing the widget or sheet structure.

## Product Design

### Entry Surface

Add a new in-app profile widget kind for AI coach analysis.

The widget should appear inside the existing Profile dashboard flow and participate in the current widget manager model. It should be enableable, reorderable, and removable the same way the current profile widgets are.

### Widget Layout

The widget uses a "coach brief first" hierarchy:

- A weekly headline recap.
- A compact momentum or health signal for the week.
- Two supporting chips or rows that summarize the top rising area and top watchlist area.
- A clear affordance to open the deeper sheet.

Example shape:

- Title: `Coach Brief`
- Recap: `Lower-body strength moved well this week while pressing stayed flat against your baseline.`
- Signals: `Trending Up: Back Squat`, `Watchlist: Bench Press`
- Drill-down title: `Weekly Coach`

### Drill-Down Sheet

The deeper sheet opens from the widget and follows this order:

1. AI recap summary.
2. Deterministic support cards.
3. Small charts and context.
4. Tappable follow-up questions.

The sheet should not feel like a chat product. It is a structured analysis surface with optional explainers.

Content blocks:

- Weekly recap banner.
- Rising lifts section.
- Watchlist lifts section.
- Weekly consistency and workload context.
- Small trend visuals for the most relevant signals.
- Follow-up actions such as:
  - `Why is bench flat?`
  - `What improved this week?`
  - `What changed from last week?`

## Behavioral Scope

The feature should explain:

- Which lifts or movement areas are rising.
- Which ones are flat or slowing relative to the user's recent baseline.
- How this week's consistency and workload compare to the recent norm.
- Broad focus areas for next week.

The feature should not:

- Rewrite the user's training program.
- Recommend exercise swaps.
- Prescribe exact load, volume, or rest changes in v1.
- Operate as a live active-workout assistant.

## Architecture

The implementation should have three layers.

### 1. Deterministic analytics layer

Add a new service in `WGJ/Services`, tentatively named `WeeklyCoachInsightService`.

Responsibilities:

- Build a current-week summary from projected training facts.
- Build a rolling personal baseline from the previous 6 completed weeks, excluding the current 7-day analysis window.
- Compute deltas between current week and baseline.
- Identify rising lifts and watchlist lifts.
- Identify simple plateau or slowdown conditions.
- Produce a compact, AI-ready snapshot.

Inputs:

- Projected history facts from `CompletedSetFact`.
- Existing metrics helpers from `WorkoutMetricsService`.
- Canonical profile settings when relevant, using the existing profile selection rules.

Outputs:

- A small `WeeklyCoachInsightSnapshot` model containing:
  - target week
  - history revision or freshness key
  - consistency metrics
  - workload deltas
  - top rising signals
  - top watchlist signals
  - short deterministic fallback summary
  - follow-up prompt candidates

Default signal rules for planning:

- A lift is eligible only if it has enough exposure in both windows to avoid one-off noise.
- `rising` should default to a meaningful positive change versus baseline, starting with an implementation target of roughly 3% or greater on the chosen performance metric.
- `watchlist` should default to a meaningful flat or negative change versus baseline with comparable exposure, also starting with an implementation target of roughly 3% in the opposite direction.
- Plateau wording should only appear when the current week is flat or down against baseline and the user still trained that area enough for the comparison to be credible.

### 2. AI narration layer

Add a service such as `AppleCoachNarrativeService`.

Responsibilities:

- Check `SystemLanguageModel` availability.
- Turn `WeeklyCoachInsightSnapshot` into:
  - a short weekly recap
  - concise signal explanations
  - follow-up response copy for predefined prompts
- Keep prompts compact and single-purpose.
- Fall back cleanly when the model is unavailable or not ready.

The main recap should use guided generation so the model returns a small typed structure rather than loose text. Follow-up explanations should default to direct targeted prompting from the compact snapshot in v1, with tool calling reserved only if later implementation evidence shows snapshot prompting is not grounded enough.

### 3. Local cache layer

Store generated recap results in a local-only derived cache.

This cache should not live in cloud-synced user data. It is derived from local history and should be disposable and regenerable. A new local-only SwiftData model in the derived analytics path is acceptable if it keeps refresh cheap and avoids recomputation during routine Profile opens.

Suggested cached shape:

- `CachedCoachNarrative`
  - week identifier
  - input revision key
  - generated recap
  - supporting generated summaries
  - generation timestamp
  - availability mode used

Follow-up explanations should use a separate lightweight cache keyed by week, revision, and follow-up kind so recap refreshes do not force regeneration of every optional explanation.

## Data Flow

### Generation triggers

Generate or refresh insights in these cases:

- After a completed workout is saved and history projections are updated.
- When Profile opens and the relevant week snapshot or narrative is stale.
- When the user opens the deeper sheet and a follow-up explanation is missing.

Do not generate on every small app event.

### Refresh sequence

1. Workout history changes.
2. Deterministic projected facts are already rebuilt through the existing history pipeline.
3. `WeeklyCoachInsightService` computes the latest current-week and baseline-aware snapshot.
4. UI immediately receives deterministic fallback data.
5. If Apple Intelligence is available, `AppleCoachNarrativeService` generates the recap in the background.
6. Cache is updated locally.
7. Widget and sheet refresh to the generated narrative if it arrives successfully.

### Staleness policy

Narrative cache should be invalidated when either:

- the relevant week changes
- the underlying history revision changes
- a chosen freshness timeout expires for profile open

The deterministic insight snapshot may also be cached, but the key requirement is that it remain cheap enough to rebuild quickly from the existing history projection path.

## Performance Strategy

The feature should feel instant at the widget level.

Performance constraints:

- Widget first paint uses cached or deterministic fallback data.
- AI recap generation always happens off the critical path.
- Follow-up explanations are small, targeted requests, not one large session.
- No raw workout history dumping into prompts.

Foundation Models currently documents a 4,096-token per-session context window, so prompts should contain only the compact insight snapshot and the minimum necessary instruction text. Avoid multi-turn conversational sessions for the recap. Use fresh, single-purpose sessions for recap and for each follow-up explainer.

## Fallback Behavior

### Model unavailable

If Apple Intelligence is unavailable because of device eligibility, settings, or model readiness:

- show the widget
- show deterministic summary copy
- keep trend/watchlist visuals functional
- hide or simplify AI-specific wording where needed

### Not enough data

If the user has too little history to compute meaningful weekly analysis:

- render a structured empty state
- explain that coach analysis appears after more completed sessions
- avoid weak or forced AI language

### Errors

If generation fails:

- keep the deterministic snapshot visible
- do not surface loud blocking errors in Profile
- optionally log diagnostics in debug or settings diagnostics surfaces if the repo already supports them

## UX States

### Widget states

- Loading cached data.
- Deterministic summary ready, AI pending.
- AI recap ready.
- Not enough data yet.

### Sheet states

- Cached recap and signals already ready.
- Deterministic details ready while follow-up explanation loads.
- Follow-up explanation loaded inline.
- Follow-up explanation unavailable, with deterministic facts still visible.

## Data Models

The concrete names may change during implementation, but the design assumes these new presentation-friendly models:

- `WeeklyCoachInsightSnapshot`
- `WeeklyCoachTrendSignal`
- `WeeklyCoachWatchSignal`
- `CoachNarrativeSummary`
- `CoachFollowUpKind`
- `CachedCoachNarrative`

These should stay narrow and presentation-safe. They are not a new general-purpose analytics domain.

## UI Integration Plan

### Profile integration

- Add a new `ProfileWidgetKind` case for the coach widget.
- Extend `ProfileWidgetRepository` defaults and persistence handling.
- Add the widget to `ProfileWidgetManagerView` for enable or disable and reorder.
- Extract dedicated UI instead of widening `ProfileView.swift` further:
  - `ProfileCoachBriefWidgetView`
  - `ProfileCoachAnalysisSheet`
  - small subviews for signal rows and follow-up prompt chips

### History integration

V1 should not make History the primary entry point. However, the deeper sheet may eventually link to recent sessions or relevant trend visuals already grounded in history data. Keep that extension path open, but do not expand scope for the first implementation.

## Testing Strategy

### Unit tests

Add `WGJTests` coverage for:

- baseline window calculations
- rising signal detection
- watchlist or plateau detection
- fallback summary generation
- staleness decisions
- generation trigger decisions
- no-data and sparse-data behavior
- canonical profile usage if any profile-backed settings are involved

### UI tests

Add `WGJUITests` coverage for:

- enabling the coach widget from the profile widget manager
- seeing the coach widget in Profile
- opening the deeper sheet
- rendering deterministic fallback when AI is unavailable in tests
- follow-up prompt tap behavior where feasible

### Manual verification

- Confirm workout completion updates the snapshot without blocking the completion flow.
- Confirm profile open is instant with cached or deterministic content.
- Confirm the feature works in local-only mode and makes no CloudKit assumptions.
- Confirm unsupported AI environments still show a useful deterministic widget.

## Rollout Plan

### Phase 1

- Deterministic weekly snapshot.
- Profile widget and deeper sheet.
- One AI weekly recap.
- Two or three tappable follow-up explanations.
- Deterministic fallback everywhere.

### Phase 2

- More nuanced follow-up prompts.
- Better signal taxonomy.
- Optional per-lift explanation expansion from the deeper sheet.

### Future Phase

- Optional Core ML prediction inputs for plateau risk or momentum scoring.
- Additional AI surfaces in History if the Profile feature proves valuable.

## Risks And Mitigations

### Risk: prompts become too large or slow

Mitigation:

- Keep snapshot compact.
- Use one-turn sessions.
- Split follow-ups into separate small requests.

### Risk: AI wording overstates confidence

Mitigation:

- Constrain output shape.
- Keep recommendations broad.
- Ground every generated statement in deterministic signals.

### Risk: Profile screen gets heavier

Mitigation:

- Render cached or deterministic data first.
- Extract dedicated subviews and services.
- Keep generation off the main path.

### Risk: feature drifts into prescriptive coaching

Mitigation:

- Lock prompt instructions to explanation, recap, and broad focus only.
- Keep suggested actions at the "watch this area next week" level in v1.

## Final Recommendation

Build an in-app Profile coach widget that leads with an AI-written weekly recap, backed by deterministic local analytics and a local cache. Use Foundation Models for concise recap and explanation only. Keep the analysis baseline-aware, broad in its coaching language, and fully useful even when the AI layer is unavailable.
