# Progress Calculation Correctness Design

## Goal

Make Progress, History, completion, and trend calculations mathematically consistent while preserving the current Progress screen structure and workout data semantics.

## Confirmed Problem

Weighted exercise rows currently determine direction from estimated one-repetition maximum (e1RM), but display a signed total-volume delta. A workout can therefore improve in estimated strength while showing an orange/green upward arrow beside a negative kilogram value. The same mismatched value is used to choose and describe the biggest mover.

## Selected Approach

Use one comparison basis per exercise and carry it consistently through direction, signed text, and mover ranking:

- Weighted exercises compare best estimated 1RM, normalized to kilograms.
- Bodyweight or reps-only exercises compare best completed repetitions.
- Workload volume remains visible in the existing Earlier and Later columns and in the session-level Volume card.
- When two sessions do not expose the same exercise metric type, the row is neutral rather than comparing kilograms with repetitions.

The signed weighted delta is labeled `kg e1RM`, making the value distinct from the existing `kg` workload values. Ranking uses the same comparison metric rather than parsing presentation text.

## Shared Calculation Policy

Create one value-only calculation policy for:

- Epley estimated 1RM: `weight * (1 + reps / 30)` for more than one repetition.
- Pounds-to-kilograms normalization using the existing `0.45359237` factor.
- Weighted volume in kilograms: normalized weight multiplied by completed repetitions.

The history projector, workout metrics service, and Progress snapshot builder use this policy. This is a refactor of existing semantics, not a data migration; the workout summary metrics version remains unchanged.

## Progress Presentation Corrections

- Exercise direction, tint, signed delta, and biggest-mover detail all use the same comparison basis.
- Biggest-mover ordering uses relative change so kilogram-based e1RM changes and repetition changes can be ranked without comparing raw units.
- Duration deltas retain seconds when needed (`+45s`, `-1m 15s`) so a visible zero never carries an up/down direction.
- Workload signals distinguish `More work`, `Same work`, and `Less work`.
- PR signals distinguish `New hits`, `Steady`, and `Fewer hits`.
- Signed values are derived from the same rounded/displayed quantity used for direction, preventing `0` from being styled as an increase or decrease.

## Data Rules

- Only completed, non-warmup sets with positive repetitions contribute.
- Only positive weighted loads contribute to e1RM and volume.
- kg and lb loads are normalized before comparison or aggregation.
- Bodyweight work contributes repetitions, not fabricated external-load volume.
- Archived workouts remain excluded.
- Manual selections remain chronologically ordered as Earlier and Later.

## Architecture

Calculation and comparison rules remain outside SwiftUI. `ProgressDashboardView` continues to render immutable snapshot values. The new shared policy is nonisolated, deterministic, and side-effect free, so it can be used by background snapshot loading and focused unit tests.

## Verification

Add regressions for:

- Strength increasing while total volume decreases.
- Strength decreasing while total volume increases.
- Equivalent kg and lb loads.
- Bodyweight repetition changes.
- Mixed metric types becoming neutral.
- Warmup and incomplete-set exclusion.
- Sub-minute duration changes and exact zero.
- Workload and PR positive, neutral, and negative labels.
- Shared e1RM, normalization, and volume calculations.

Run focused Progress/calculation tests, the full WGJ test suite, a clean Release simulator build, and a simulator smoke check of the Progress screen.
