# Workout Completion Celebration Design

## Goal

Make workout completion feel punchy and rewarding while keeping the summary responsive and preserving the local-first completion flow. Confetti should read as centered on the visible screen, and workouts with personal records should receive a stronger gold-and-trophy treatment than ordinary completions.

## Scope

- Center the automatic confetti celebration in the visible completion container.
- Add a short hero-card entrance, one glow bloom, and a trophy or seal pop.
- Give personal-record completions a stronger but explicitly bounded celebration than standard completions.
- Preserve tap-originated manual confetti replay.
- Preserve Reduced Motion behavior and immediate interaction with the summary and History action.

The workout commit path, summary snapshot construction, navigation flow, CloudKit backup scheduling, and summary content are unchanged.

## Celebration Variants

The presentation derives one variant from the completed-workout snapshot:

- **Standard:** the existing blue, cyan, success, purple, warning, and gold palette; one centered 38-piece burst; checkmark-seal emphasis.
- **Personal record:** stronger gold emphasis, a trophy pop, and one centered 46-piece burst. It uses the same bounded lifetime and renderer as the standard variant.

Manual replay remains an 18-piece burst and starts at the user's tap location.

## Presentation Sequence

Celebration begins only after the summary snapshot has loaded:

1. The hero card appears at 96% scale.
2. A spring lasting no longer than 600 milliseconds settles the card to its normal scale while the seal or trophy pops.
3. The hero border or background glow blooms once and fades within 900 milliseconds.
4. One confetti burst begins from the center of the visible completion container.
5. Haptic completion feedback fires without delaying any visual or navigation work.

The History action remains enabled throughout. Leaving the screen cancels pending presentation and cleanup work.

## State and Component Boundaries

Celebration state remains local to `WorkoutCompletionSummaryView`. A small deterministic policy describes:

- the standard or personal-record variant;
- automatic and manual particle counts;
- the automatic origin for a given container frame;
- animation timing and emphasis values.

The policy contains no persistence or service work and can be tested without rendering SwiftUI. The existing confetti burst remains responsible for generating its pieces once. The overlay remains responsible only for drawing those pieces.

The hero choreography is implemented as a focused view modifier or subview driven by one short-lived presentation phase. It must not introduce a view model, per-particle state, or per-particle tasks.

## Centering

The automatic origin uses the midpoint of the tracked completion container in global coordinates. If the global frame is unavailable but container dimensions are known, the fallback uses the local midpoint. If height is also unavailable, the last-resort origin is half the available width and 360 points from the top, keeping the launch near the visual center of compact and standard phones instead of the hero card's lower edge.

Manual replay continues to use the tap location. The overlay converts global origins into its local coordinate space before drawing.

## Performance Guardrails

- Keep one automatic confetti burst and one `Canvas` renderer timeline per active burst.
- Keep the timeline bounded at 30 FPS.
- Generate particle properties once when a burst is created.
- Bound automatic particle counts at 38 for standard completions and 46 for personal-record completions; manual replay remains 18.
- Use one animation phase for hero scale, glow, and icon emphasis instead of independent repeating animations or timers.
- Do not add blur-heavy full-screen layers, particle views, geometry work per particle, or synchronous persistence work.
- Confetti and optional animation work must never block workout commit, first summary presentation, dismissal, navigation, or backup scheduling.
- Consolidate cleanup at burst or presentation level and cancel it when the view disappears.

## Accessibility

With Reduce Motion enabled, the app skips confetti, spring movement, animated glow, and icon pop. Completion haptics and a static highlighted hero state remain. Existing accessibility labels, replay action, burst count, and hints remain meaningful.

The celebration does not intercept touches, move focus, or prevent VoiceOver users from activating View History.

## Failure and Cancellation

Celebration is best-effort presentation work. A cancelled animation or cleanup task cannot affect the saved workout or summary. If the snapshot cannot be loaded, the existing fallback to History remains unchanged. If the container frame is unavailable, the deterministic fallback origin keeps the burst visible.

## Verification

Add deterministic tests before production changes for:

- the centered automatic origin across compact and large phone containers;
- fallback centering before layout is available;
- standard and personal-record variants selecting different bounded particle counts and emphasis;
- manual replay retaining its lighter count and supplied origin;
- Reduced Motion selecting the static, non-particle presentation.

Run the focused confetti and celebration policy tests, then build the app for an iOS Simulator. Inspect the completion screen for centered placement, immediate button interaction, one-shot hero choreography, correct PR differentiation, and cancellation when dismissed. Confirm the implementation still uses pre-generated pieces, a 30 FPS `Canvas`, and no per-particle tasks.
