# Final Catalog Polish Design

## Goal

Resolve the three remaining validated exercise-catalog review findings without changing the approved catalog, detail, timeline, navigation, or persistence architecture.

## Scope

1. Alphabetical sections fold diacritics into their base letter and group rows by key rather than relying on adjacent localized-sort results. Names beginning with `A`, `Á`, `Ä`, or `Å` therefore share one stable `A` section and one section identity.
2. An empty projection is presented as loading while the projection controller is actively computing. “No exercises match” appears only after projection work finishes with no rows.
3. Search-result highlighting tokenizes each displayed name segment with the same punctuation and diacritic normalization used by search. A query such as `bar` highlights the `T-Bar` segment, and `up` highlights `Pull-Up`.

## Architecture

Keep projection rules in `ExerciseCatalogProjector` and keep SwiftUI limited to rendering projector/controller state. Add a small pure empty-state policy for the loading decision so it can be tested without UI automation. Do not add a new view model, persistence path, dependency, background task, or navigation mechanism.

## Verification

Add focused regression coverage for accented section grouping, punctuation-aware highlighting, and initial projection loading. Run the affected unit tests, the complete `WGJTests` suite, a Release simulator build, `git diff --check`, and a clean working-tree audit.

## Non-goals

- No visual redesign.
- No additional statistics or search behavior.
- No CloudKit or SwiftData changes.
- No worktree.
- No further broad review pass after these validated findings are fixed and verified.
