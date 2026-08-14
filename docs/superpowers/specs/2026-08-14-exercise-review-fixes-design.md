# Exercise Review Fixes Design

## Goal

Correct the three issues found in the exercise catalog and progress review without redesigning the UI or expanding feature scope.

## Behavior

- Search normalization treats punctuation and symbols as token boundaries. A query such as `t bar row` matches `T-Bar Row`, while existing case- and diacritic-insensitive ranking remains unchanged.
- Workout-frequency projections include zero-valued calendar weeks between the first relevant week and the current/range-ending week. This makes inactive gaps visible instead of connecting only active weeks.
- Superseded catalog projections stop consuming CPU. Cancellation reaches the actual background projection work, and catalog reload paths request one projection for the final current input.

## Boundaries

- Keep search and progress computation in their existing model/service projectors.
- Keep SwiftUI view structure and visual presentation unchanged.
- Do not add persistence, network, or CloudKit work.
- Do not refactor unrelated catalog or metrics code.

## Verification

Use test-driven fixes:

1. Add a search regression test for punctuation-equivalent tokens.
2. Add a progress regression test proving inactive weeks appear as zeroes.
3. Add a controller regression test proving superseded projection work observes cancellation.
4. Run the focused tests, the broader WGJ unit suite, and a Release simulator build.
