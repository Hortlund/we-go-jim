# Multiple Exercise Trend Widgets Design

## Goal

Allow the Profile dashboard to show multiple exercise trend widgets at the same time. Each added trend widget tracks one exercise and one metric so a user can keep separate cards such as Bench Press 1RM, Squat 1RM, Deadlift Volume, or Pull Up Max Reps.

## Product Behavior

- Fixed dashboard widgets such as PRs, Weekly Goal, Muscle Heatmap, Coach Brief, Streaks, Top Exercises, and Consistency Calendar remain one widget per kind.
- Exercise trend widgets become instance-based. A user can add more than one trend card, including multiple cards using the same metric for different exercises.
- Each exercise trend card stores:
  - selected exercise UUID
  - selected exercise name snapshot
  - trend metric
  - enabled state
  - dashboard sort order
- Supported trend metrics:
  - 1RM: estimated one-rep max per completed workout for the exercise
  - Max Weight: best logged weighted load per completed workout for the exercise
  - Volume: weighted training volume per completed workout for the exercise
  - Max Reps: best completed reps per completed workout for the exercise
- Bodyweight-only history can support Max Reps, but 1RM, Max Weight, and Volume require weighted history.
- Existing users with a configured 1RM or Volume trend keep their current card.

## Architecture

Use the existing `ProfileWidgetConfig` SwiftData model instead of adding a new model. Add a metric field such as `exerciseTrendMetricRaw` and keep the existing selected exercise fields. The current `.exerciseOneRMTrend` and `.exerciseVolumeTrend` widget kinds become legacy-compatible trend container kinds; new trend cards should be represented consistently through the metric field.

`ProfileWidgetRepository` will keep singleton normalization for non-trend widget kinds, but it must allow multiple exercise trend configs. Repository APIs that currently address widgets only by `ProfileWidgetKind` need config-id variants for trend instances, including enable/remove, update exercise selection, update metric, and reorder.

`ProfileDashboardContent` and `ProfileViewController` will key loaded trend series by widget config ID, not by `ProfileWidgetKind`, because kind is no longer unique for trends. The existing delayed/background loading path remains in place so Profile first render stays light.

`WorkoutMetricsService` will expose one metric-series entry point for exercise trend metrics. Existing 1RM and Volume trend methods can stay as focused helpers, while Max Weight and Max Reps add matching logic over the already-projected exercise history.

## UI Flow

`ProfileWidgetManagerView` keeps the enabled and available sections. The available section gets an Add Exercise Trend action. Adding a trend asks for metric and exercise, then creates a new enabled trend config. Enabled trend rows display the exercise and metric together, for example `Bench Press - 1RM`, and their remove/change actions apply to that specific config.

Dashboard rendering keeps the current card style. Trend cards derive their title, subtitle, accent, empty message, and value formatting from the stored metric. Accessibility identifiers should include the config ID or another stable per-instance token so UI tests can target individual trend widgets.

## Data Flow

1. Manage Widgets creates or edits a `ProfileWidgetConfig` for one exercise trend instance.
2. Profile dashboard loads enabled widget snapshots through `ProfileWidgetRepository`.
3. Trend loading filters enabled widgets that require exercise trend data.
4. For each trend config, `WorkoutMetricsService` builds a metric series for that config's exercise and metric.
5. The dashboard stores the result by config ID and renders each enabled widget in sort order.

## Compatibility And Local-First Behavior

The change is additive to local SwiftData state and does not require CloudKit to use the core Profile dashboard. Existing fixed widgets continue to normalize to one config per kind. Existing `.exerciseOneRMTrend` and `.exerciseVolumeTrend` configs should receive default metrics when loaded if the new metric field is empty.

Cloud-backed stores may sync the new optional field like other profile widget config data, but CloudKit availability must not block local dashboard use.

## Error Handling

- Enabling or creating a weighted trend without a selected exercise should fail with a user-facing repository error.
- If no compatible exercise history exists, the add flow should explain that the user needs matching logged history first.
- If a configured trend has no points after loading, render the existing empty card state with a metric-specific message instead of failing the dashboard.
- Unknown metric raw values should default to 1RM for legacy safety.

## Testing

- `WGJTests` repository coverage:
  - fixed widgets still normalize to one config per kind
  - multiple exercise trend configs can coexist
  - removing/updating one trend config does not mutate another
  - existing 1RM and Volume configs load with the expected default metric
- `WGJTests` metrics coverage:
  - Max Weight trend returns recent workout points oldest-to-newest
  - Max Reps trend supports bodyweight and weighted completed sets
  - metric-series dispatch returns the same values as existing 1RM and Volume helpers
- `WGJTests` dashboard/controller coverage:
  - two enabled trend configs produce two series keyed by config ID
  - same metric with two exercises and two metrics for the same exercise both work
- `WGJUITests` smoke coverage if UI behavior changes enough:
  - add two trend widgets from Manage Widgets and confirm both appear on Profile

## Out Of Scope

- No CloudKit-specific behavior changes.
- No new charts beyond the existing exercise trend card presentation.
- No custom dashboard layout editor beyond the existing enabled-widget ordering.
- No aggregate multi-exercise comparison chart in a single card.
