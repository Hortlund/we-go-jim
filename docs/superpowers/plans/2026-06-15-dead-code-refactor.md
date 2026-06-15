# Dead Code Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove private Swift code that is no longer referenced, without changing app behavior.

**Architecture:** This cleanup is intentionally conservative. Only private/fileprivate declarations with no references outside their own declaration are removed, so the compiler is the main safety net.

**Tech Stack:** Swift, SwiftUI, WidgetKit, SwiftData, XcodeBuildMCP.

---

### Task 1: Remove Dead Private Declarations

**Files:**
- Modify: `WGJ/Theme/WGJTheme.swift`
- Modify: `WGJ/Services/WeeklyCoachInsightService.swift`
- Modify: `WGJ/Services/WorkoutMetricsService.swift`
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift`
- Modify: `WGJ/Views/Workout/StartWorkoutHomeView.swift`
- Modify: `WGJWidgetExtension/WeeklyGoalWidget.swift`

- [ ] **Step 1: Confirm references before editing**

Run:

```bash
rg -n "setCycleCompletionStates|refreshGuidanceCache|allExercisesCompleted|focusCancelSection|ActiveWorkoutSessionMetaSnapshot|optionalNotes|mediumStatus|weekRange|stablePercentageString|completedWorkingSetMetrics|priorSetMetricPeaks|glassTint" WGJ WGJWidgetExtension WGJTests
```

Expected: each symbol appears only at its declaration, except helper names that are substrings of used longer helpers.

- [ ] **Step 2: Remove unused declarations**

Remove the following declarations:

```text
WGJ/Theme/WGJTheme.swift: private var glassTint
WGJ/Services/WeeklyCoachInsightService.swift: private func stablePercentageString(_:)
WGJ/Services/WorkoutMetricsService.swift: private func completedWorkingSetMetrics(for:)
WGJ/Services/WorkoutMetricsService.swift: private func priorSetMetricPeaks(for:before:excludingSessionID:)
WGJ/Views/Workout/ActiveWorkoutView.swift: private func setCycleCompletionStates(for:)
WGJ/Views/Workout/ActiveWorkoutView.swift: private func refreshGuidanceCache()
WGJ/Views/Workout/ActiveWorkoutView.swift: private func allExercisesCompleted(from:draftsByExerciseID:)
WGJ/Views/Workout/ActiveWorkoutView.swift: private func focusCancelSection(using:)
WGJ/Views/Workout/ActiveWorkoutView.swift: private struct ActiveWorkoutSessionMetaSnapshot
WGJ/Views/Workout/StartWorkoutHomeView.swift: private func optionalNotes(for:)
WGJWidgetExtension/WeeklyGoalWidget.swift: private func mediumStatus(_:)
WGJWidgetExtension/WeeklyGoalWidget.swift: private func weekRange(_:)
```

- [ ] **Step 3: Re-run the reference scan**

Run:

```bash
rg -n "setCycleCompletionStates|refreshGuidanceCache|allExercisesCompleted|focusCancelSection|ActiveWorkoutSessionMetaSnapshot|optionalNotes|mediumStatus|weekRange|stablePercentageString|completedWorkingSetMetrics|priorSetMetricPeaks\\(|glassTint" WGJ WGJWidgetExtension WGJTests
```

Expected: no matches for removed symbols.

- [ ] **Step 4: Build and test**

Run:

```text
XcodeBuildMCP build_sim with scheme WGJ on iPhone 16 Pro
XcodeBuildMCP test_sim with scheme WGJ on iPhone 16 Pro
```

Expected: build succeeds. Unit tests should pass; the baseline full scheme currently has a pre-existing `WGJUITests` bundle loading failure.

### Task 2: Remove Unused Internal Helper Types

**Files:**
- Delete: `WGJ/Services/SupportContactService.swift`
- Delete: `WGJ/Services/UserProfileSelection.swift`
- Modify: `WGJ/Models/UserDomainModels.swift`
- Modify: `WGJ/Models/AppRuntimeConfig.swift`
- Modify: `WGJ/Services/AppWarmupState.swift`
- Modify: `WGJ/Views/Profile/ProfileView.swift`

- [ ] **Step 1: Confirm no external references**

Run:

```bash
rg -n "CustomExerciseCloudMuscleSnapshot|ActiveWorkoutMinimizeScrollRestorePolicy|SupportContactService|SupportContactDraft|ProfileInitialLoadPolicy|FirstFrameTabContentPolicy|FirstFrameTabPresentation|UserProfileSelection|ProfileDashboardTrendSeriesBuilder" WGJ WGJTests WGJWidgetExtension
```

Expected: each type appears only in its own declaration block, or only inside a declaration block being removed.

- [ ] **Step 2: Remove unused helper types**

Remove:

```text
WGJ/Services/SupportContactService.swift
WGJ/Services/UserProfileSelection.swift
WGJ/Models/UserDomainModels.swift: CustomExerciseCloudMuscleSnapshot
WGJ/Models/AppRuntimeConfig.swift: ActiveWorkoutMinimizeScrollRestorePolicy
WGJ/Services/AppWarmupState.swift: ProfileInitialLoadPolicy
WGJ/Services/AppWarmupState.swift: FirstFrameTabPresentation
WGJ/Services/AppWarmupState.swift: FirstFrameTabContentPolicy
WGJ/Views/Profile/ProfileView.swift: ProfileDashboardTrendSeriesBuilder
```

- [ ] **Step 3: Re-run the reference scan**

Run:

```bash
rg -n "CustomExerciseCloudMuscleSnapshot|ActiveWorkoutMinimizeScrollRestorePolicy|SupportContactService|SupportContactDraft|ProfileInitialLoadPolicy|FirstFrameTabContentPolicy|FirstFrameTabPresentation|UserProfileSelection|ProfileDashboardTrendSeriesBuilder" WGJ WGJTests WGJWidgetExtension
```

Expected: no matches for removed symbols.

- [ ] **Step 4: Build and test**

Run:

```text
XcodeBuildMCP build_sim with scheme WGJ on iPhone 16 Pro
XcodeBuildMCP test_sim with -only-testing:WGJTests
```

Expected: build succeeds and all selected unit tests pass.
