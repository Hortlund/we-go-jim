# Exercise Catalog Stability and Progress Timeline Design

Date: 2026-08-14
Status: Approved

## Objective

Make the exercise catalog feel stable and responsive while scrolling, searching, filtering, and navigating to and from exercise details. Expand each exercise detail with a combined, selectable long-term progress timeline built entirely from completed local workout history.

The work preserves the current visual identity and local-first architecture. It does not introduce interaction-path CloudKit work, persistence churn, or a wholesale replacement of the catalog with a different UI.

## Scope

This design covers:

- Catalog scrolling and collapsing-header stability.
- Ranked, forgiving, deterministic search.
- Filter and sort integration with the same search projection pipeline.
- Smooth native push and pop navigation between catalog and exercise detail.
- Preservation of catalog query, filters, and scroll position after returning from detail.
- Six selectable exercise metrics across five selectable time ranges.
- Period summaries, a progress chart, and a chronological milestone timeline.
- Focused automated and Simulator verification.

This design does not cover:

- A visual redesign of the full exercise catalog.
- Editing completed workout history from exercise detail.
- Persisting derived analytics records.
- Network or CloudKit synchronization during catalog or statistics interactions.
- General changes to workout, template, history, or profile navigation.

## Current-State Findings

The catalog already uses stable exercise UUIDs for row identity and builds SwiftData-independent snapshots for rendering. Those are sound foundations.

The likely instability comes from three concentrated areas:

1. The pinned header continuously changes its own height from the scroll offset. That height change affects scroll layout while the offset is being measured, creating avoidable layout feedback and broad view invalidation.
2. Search, filtering, grouping, and sorting synchronously mutate the full catalog snapshot on the main actor. Even with a short debounce, rapid typing or filter changes can compete with scrolling and animation work.
3. Exercise detail loads statistics after navigation and currently requests only eight points. The late insertion changes page height during the transition and cannot represent long-term progress.

## Catalog Architecture

### Stable layout

The catalog retains a pinned search and filter region, but scroll progress must not continuously change the height of the container that participates in the same scroll layout.

The revised header uses a stable reserved height for its current presentation mode. Scroll progress may drive bounded visual properties such as opacity and translation inside that reserved region. The transition between expanded and compact presentation uses a threshold with hysteresis or an equivalent stable state transition so small offset changes near the boundary cannot oscillate the layout.

When search is focused or a filter menu is open, the expanded controls remain stable. Reduced Motion removes nonessential translation and uses immediate or opacity-only state changes.

### Search projection

Live text remains local to the search field so typing feedback is immediate. Meaningful search inputs produce a cancellable projection request containing:

- Normalized query tokens.
- Selected muscle, equipment, category, and visibility filters.
- Sort direction.
- A monotonically increasing request generation.

Search work executes away from the main render path over immutable, sendable catalog index values. Completion publishes one ready-made result snapshot on the main actor. A result is accepted only when its generation is still current, preventing an older slow search from replacing newer results.

Filtering, grouping, and sorting use the same projection pipeline. No filtering or sorting occurs in SwiftUI view bodies.

### Search ranking

Search uses restrained intent ranking in this order:

1. Exact normalized exercise-name match.
2. Exercise-name prefix match.
3. All query tokens matched in the exercise name, regardless of token order.
4. Known alias or abbreviation match.
5. Category, primary or secondary muscle, and equipment match.
6. Conservative typo fallback when stronger results are scarce.

Typo matching must use a bounded edit-distance policy appropriate to token length. It must not elevate weak fuzzy matches above exact, prefix, token, or alias matches. It may be omitted for very short tokens where fuzzy matching would create noise.

Within an equal rank, localized alphabetical order and stable UUID provide deterministic tie-breaking. Matching name fragments receive subtle highlight treatment without changing row height.

### Catalog rendering and state preservation

Rows continue to use exercise UUIDs as stable identity. The catalog view observes the narrowest possible presentation state and receives complete immutable result sections rather than mutating a broad snapshot repeatedly.

Query, filters, sort direction, and scroll position are owned for the lifetime of the catalog destination. Opening an exercise detail does not clear or reload them. Returning from detail restores the same rendered snapshot and scroll position. The catalog reloads only after an exercise is created, edited, deleted, or an explicit catalog bootstrap or retry changes its source data.

## Navigation and Detail Loading

Catalog-to-detail navigation uses the existing native `NavigationStack` push and pop behavior. The route carries a stable exercise UUID plus a lightweight immutable display snapshot sufficient for the first detail frame. It does not carry SwiftData model objects or full catalog arrays.

The detail destination uses the display snapshot immediately, then resolves any mutable catalog data it needs by UUID. The statistics region reserves a stable frame with skeleton placeholders while its immutable analytics snapshot is built in the background. Loading completion replaces placeholder content in place rather than inserting a large section and shifting the entire page during the navigation animation.

Navigation must not trigger catalog reconstruction. Detail edits and deletions explicitly invalidate and reload the catalog after the mutation boundary succeeds.

## Exercise Progress Timeline

### Metric selector

The combined progress section supports six metric definitions:

- Estimated one-repetition maximum.
- Heaviest weight.
- Best-set repetitions.
- Session volume.
- Total repetitions.
- Workout frequency.

All six remain discoverable. A metric that is not meaningful for the exercise or has no compatible history is disabled and includes a concise explanation. For example, a pure bodyweight exercise may not provide heaviest weight or estimated one-repetition maximum.

### Time-range selector

The section supports:

- 1 month.
- 3 months.
- 6 months.
- 1 year.
- All time.

Range boundaries are calendar-aware and anchored to the current date. A completed workout is included when its completion date is on or after the calendar date produced by subtracting the selected number of months or years; the current date is inclusive. All time has no lower bound. The default selection is 6 months, balancing recent readability with enough history to show a meaningful trend.

### Aggregation rules

Each completed workout contributes at most one point per exercise and metric where appropriate:

- Estimated 1RM: the best estimated 1RM achieved in that workout.
- Heaviest weight: the greatest compatible logged load in that workout.
- Best-set reps: the highest repetitions in one completed set for that workout.
- Session volume: the sum of compatible weighted set load multiplied by repetitions for that workout.
- Total reps: the sum of completed repetitions for that workout.
- Workout frequency: the count of completed workouts containing the exercise, grouped by calendar week.

Mixed load units normalize for comparison and aggregate consistently, then convert to the exercise history's display unit. Bodyweight-only work does not fabricate external load or estimated 1RM values.

### Chart behavior

The chart occupies a stable frame and updates in place when metric or range changes. Axes and formatting adapt to the metric while retaining consistent visual structure. A selection interaction exposes the nearest point's date and exact value. Reduced Motion disables nonessential chart transitions.

All-time projections include complete local history. When a series is too dense for meaningful display, a deterministic downsampling policy preserves the first point, last point, extrema, and personal-record milestones while reducing ordinary intermediate points. Raw values remain available to summaries and the milestone timeline.

### Summary and milestones

The selected metric and range produce compact summary values:

- Change from the first to the latest compatible value, including absolute and percentage change where meaningful.
- Best value and date.
- Completed session count.
- Total completed sets and repetitions.
- First and latest performance dates in the selected period.

Below the chart, a chronological milestone timeline shows meaningful sessions and personal records. It prioritizes PRs, first performances, and material changes so a large history does not become an unbounded list of visually identical entries. Each milestone includes its date, metric value, and PR or change context.

## Data Boundaries

`ExercisesCatalogView` stays focused on composition, user input, and presentation. Catalog indexing, ranking, filtering, grouping, and stale-result protection belong in a dedicated projection or controller layer operating on immutable snapshot values.

`WorkoutMetricsService` remains the source of workout-history calculations. The service gains exercise analytics projection types for:

- Metric availability.
- Metric series.
- Range-filtered summaries.
- Milestone entries.
- Chart downsampling.

No derived analytics values are persisted. They are reconstructed from completed local workouts. Catalog browsing, search, chart selection, and navigation perform no CloudKit operations and no SwiftData saves.

## Loading and Error Handling

Catalog bootstrap and reload retain a recoverable loading or empty state. A failed search projection does not destroy the most recent valid snapshot; it exposes a small recoverable state only if user action is required.

A statistics loading failure appears inline inside the progress section with a retry action. It does not present a navigation-blocking alert. Missing history produces a clear empty state that explains that completed workouts will populate progress.

Cancellation is expected during rapid typing, filter changes, navigation, or range changes and is not presented as an error.

## Accessibility

- Search results expose full exercise names and match context without requiring visual highlight perception.
- Metric and range selectors expose selected state, disabled state, and disabled reasons.
- Chart values have accessible summaries and point descriptions.
- Timeline entries read in chronological order with explicit dates and units.
- Dynamic Type does not change row identity or introduce horizontal scrolling for primary controls.
- Reduce Motion is respected for header, chart, and navigation-adjacent animations.

## Verification Strategy

### Automated tests

Focused tests cover:

- Exact, prefix, token-order-independent, alias, metadata, and typo-fallback ranking.
- Deterministic tie ordering.
- Query normalization and short-token fuzzy-search suppression.
- Projection cancellation and rejection of stale generations.
- Combined search, filters, and sort behavior.
- Calendar range boundaries for all five ranges.
- All six metric aggregation rules.
- Mixed-unit normalization and display conversion.
- Unsupported-metric availability reasons.
- Summary change calculations and empty or single-point behavior.
- PR and milestone selection.
- Downsampling preservation of endpoints, extrema, and PRs.
- Header collapse-state hysteresis or equivalent stable threshold behavior.

### Build and runtime verification

Verification includes:

- Focused unit tests for new projection and analytics behavior.
- A full app build for the relevant Simulator destination.
- Simulator smoke tests covering rapid typing, query clearing, repeated filter changes, long-list scrolling, index navigation where available, repeated push and pop navigation, preserved return position, metric switching, and all time ranges.
- Accessibility checks for selector labels, disabled reasons, and chart summaries.
- Code-first review for observation fan-out, stable identity, render-path work, and layout feedback.
- Runtime inspection with SwiftUI Instruments or an equivalent trace if Simulator behavior remains inconclusive, comparing the same scroll and search interactions before and after.

## Acceptance Criteria

The work is complete when:

- Long catalog scrolling no longer visibly oscillates or snaps the pinned header.
- Rapid search typing remains responsive and stale searches never replace newer results.
- Search ordering follows the approved intent ranking and remains stable for equal-ranked results.
- Filters and sorting do not cause navigation state loss or unnecessary catalog reloads.
- Opening and closing exercise detail uses a smooth native transition without large content jumps.
- Returning from detail preserves query, filters, and scroll position.
- Exercise detail offers all six metrics and all five time ranges, with accurate unavailable states.
- All-time history can communicate long-term progress through the chart, summary, and milestone timeline.
- Interaction paths remain local-first and cause no CloudKit work or no-op saves.
- Focused tests and the app build pass, and Simulator verification covers the stated flows.
