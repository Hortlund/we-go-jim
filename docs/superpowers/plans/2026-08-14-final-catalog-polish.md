# Final Catalog Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix accented section identity, first-projection loading presentation, and punctuation-aware search highlighting without broadening the exercise feature.

**Architecture:** Keep sorting, grouping, and token matching in `ExerciseCatalogProjector`. Add one pure catalog-content presentation policy for the loading decision, while SwiftUI only renders projector/controller state.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, Xcode 26.

## Global Constraints

- No visual redesign.
- No additional statistics or search behavior.
- No CloudKit or SwiftData changes.
- No worktree.
- No further broad review pass after these validated findings are fixed and verified.

---

### Task 1: Stable alphabetical grouping and punctuation-aware highlighting

**Files:**
- Modify: `WGJTests/ExerciseCatalogProjectionTests.swift`
- Modify: `WGJ/Models/ExerciseCatalogProjection.swift`
- Modify: `WGJ/Views/Exercises/ExercisesCatalogView.swift:2306-2318`

**Interfaces:**
- Consumes: `ExerciseCatalogProjector.project(documents:input:)` and projected `matchedNameTokens`.
- Produces: `ExerciseCatalogProjector.shouldHighlight(displaySegment:matchedNameTokens:) -> Bool` plus diacritic-folded, uniquely keyed alphabetical sections.

- [ ] **Step 1: Write failing projector tests**

Add one test that projects `Aardvark`, `á Fly`, `Ångström Raise`, `Apple Press`, and `Ärm Curl` with an empty query and asserts there is exactly one section with ID `A` containing all five rows. Add a second test asserting `shouldHighlight(displaySegment: "T-Bar", matchedNameTokens: ["bar"])` and the equivalent `Pull-Up`/`up` case are true.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -quiet -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C' -only-testing:WGJTests/ExerciseCatalogProjectionTests
```

Expected: the accented grouping assertion fails and the highlight helper is missing.

- [ ] **Step 3: Implement minimal projector behavior**

Fold case and diacritics when deriving `ExerciseCatalogSearchDocument.indexKey`. Replace adjacency-based section assembly with first-seen key order plus a `[String: [ExerciseCatalogProjectedRow]]` accumulator. Implement `shouldHighlight` by normalizing the displayed segment, tokenizing it, and checking whether any segment token begins with a normalized matched token.

- [ ] **Step 4: Use the projector helper in the row view**

Replace the view's direct `normalizedWord.hasPrefix` test with `ExerciseCatalogProjector.shouldHighlight(displaySegment:matchedNameTokens:)`; preserve the existing displayed text and styling.

- [ ] **Step 5: Verify GREEN and commit**

Run the focused test command from Step 2 and expect all `ExerciseCatalogProjectionTests` to pass. Commit with:

```bash
git commit -m "fix(exercises): stabilize catalog grouping and highlights"
```

### Task 2: Honest initial projection loading

**Files:**
- Modify: `WGJTests/ExercisesCatalogHeaderPerformanceTests.swift`
- Modify: `WGJ/Views/Exercises/ExercisesCatalogHeaderPresentation.swift`
- Modify: `WGJ/Views/Exercises/ExercisesCatalogView.swift:177-179,779-833`

**Interfaces:**
- Consumes: whether projected sections exist, `ExercisesCatalogProjectionController.isProjecting`, catalog load state, and bootstrap state.
- Produces: `ExercisesCatalogContentPresentationPolicy.showsLoadingPlaceholder(hasProjectedSections:isProjecting:isCatalogLoading:isBootstrapping:) -> Bool`.

- [ ] **Step 1: Write the failing presentation-policy test**

Assert the policy returns true when projected sections are empty and `isProjecting` is true, false when projection is finished empty, and false when results already exist during a replacement projection.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -quiet -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C' -only-testing:WGJTests/ExercisesCatalogHeaderPerformanceTests
```

Expected: compilation fails because `ExercisesCatalogContentPresentationPolicy` does not exist.

- [ ] **Step 3: Implement the pure loading policy**

Return true for explicit catalog loading, bootstrap loading, or an empty active projection. Do not return true when existing projected sections remain visible during replacement work.

- [ ] **Step 4: Render the policy in the catalog view**

Add one private computed loading flag. Use it for the empty-state title/message/icon and show `ProgressView` before clear/retry actions while the first projection is active.

- [ ] **Step 5: Verify GREEN and commit**

Run the focused test command from Step 2 and expect all header presentation tests to pass. Commit with:

```bash
git commit -m "fix(exercises): show loading during initial projection"
```

### Task 3: Final verification

**Files:**
- Verify only; no planned production edits.

**Interfaces:**
- Consumes: tasks 1 and 2.
- Produces: a clean branch with evidence for the exact fixes.

- [ ] Run `git diff --check`.
- [ ] Run the complete `WGJTests` suite on simulator `7324C7C7-F241-4CE6-888A-84BF8096DD4C` and confirm zero failures.
- [ ] Build the `WGJ` scheme in Release for the same simulator and confirm exit code zero.
- [ ] Confirm `git status --short --branch` is clean and inspect `git diff --stat main...HEAD` for unintended scope.
