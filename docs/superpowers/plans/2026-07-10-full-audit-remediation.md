# Full Audit Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute every approved July 2026 WGJ audit remediation through six independently testable plans without losing local-first behavior or omitting a finding.

**Architecture:** Persistence safety lands before runtime ownership; runtime ownership lands before view decomposition. Concurrency reaches a zero-warning Swift 5 checkpoint before Swift 6. Platform and final verification work consume the stable service/view boundaries created earlier.

**Tech Stack:** SwiftUI, SwiftData, CloudKit backup boundaries, Observation, Swift Concurrency/Swift 6, UserNotifications, WidgetKit, XCTest/XCUITest, Instruments, Xcode 26.5.

## Global Constraints

- All 31 traceability rows in `docs/superpowers/specs/2026-07-10-full-audit-remediation-design.md` remain in scope.
- iOS 17 remains the deployment floor.
- Local data is authoritative; CloudKit backup remains best-effort at explicit save boundaries.
- No persistence, CloudKit, or broad background sync is added to typing, scrolling, set completion, or other interaction paths.
- Every production change starts with a failing focused test and ends with a focused verification plus Conventional Commit.
- A booted simulator is required for runtime tests and Instruments; physical-device and signed-archive gates cannot be replaced by simulator evidence.

---

## Detailed Plans

1. `docs/superpowers/plans/2026-07-10-data-integrity-persistence.md`
2. `docs/superpowers/plans/2026-07-10-workout-runtime-race-safety.md`
3. `docs/superpowers/plans/2026-07-10-swiftui-performance-heavy-views.md`
4. `docs/superpowers/plans/2026-07-10-strict-concurrency-swift6.md`
5. `docs/superpowers/plans/2026-07-10-apple-platform-experience.md`
6. `docs/superpowers/plans/2026-07-10-verification-release-confidence.md`

## Dependency-Resolved Execution Order

- [ ] **Stage 1: Establish explicit durable-storage behavior**

Execute Data Integrity Task 3. The app must never expose normal mutation UI after a durable-store open failure.

- [ ] **Stage 2: Fix independent save boundaries**

Execute Data Integrity Task 6, then Task 5. Template saves finalize exactly once; history commands gain one-save derived-data primitives used by restore and completion.

- [ ] **Stage 3: Make destructive/terminal persistence atomic**

Execute Data Integrity Tasks 1, 2, 4, then 7. This delivers staged deletion, validated transactional restore with retryable cleanup, idempotent completion, and the full persistence gate.

- [ ] **Stage 4: Centralize active-workout ownership and async latest-value behavior**

Execute all Runtime and Race Safety tasks in order. No feature view may directly load/modify/save the active snapshot afterward.

- [ ] **Stage 5: Measure, optimize, and decompose heavy SwiftUI screens**

Execute all SwiftUI Performance tasks in order. Tasks 5-7 consume runtime coordinator receipts; heavy-screen extraction follows the deterministic invalidation fixes.

- [ ] **Stage 6: Resolve concurrency foundations in Swift 5 mode**

Execute Strict Concurrency Tasks 1-4. Do not change `SWIFT_VERSION` yet.

- [ ] **Stage 7: Land the notification client shared by platform and concurrency work**

Execute Apple Platform Task 1, then Strict Concurrency Task 5.

- [ ] **Stage 8: Reach zero warnings and enable Swift 6**

Execute Strict Concurrency Task 6. Both Swift 5 complete checking and Swift 6 all-target builds must have zero concurrency warnings.

- [ ] **Stage 9: Complete Apple platform experience work**

Execute Apple Platform Tasks 2-8 in order: window geometry, adaptive iPad, accessibility/Dynamic Type, deep links, capability cleanup, String Catalog, deterministic previews.

- [ ] **Stage 10: Complete regression and release validation**

Execute all Verification and Release Confidence tasks. Record unit/UI/performance/signing/device/manual evidence and map it back to all 31 findings.

## Finding-to-Plan Coverage

| Finding | Detailed task |
| --- | --- |
| 1 Transactional restore | Data Integrity Tasks 1-2 |
| 2 Volatile fallback UX | Data Integrity Task 3 |
| 3 Idempotent completion | Data Integrity Task 4 |
| 4 Atomic history mutation | Data Integrity Task 5 |
| 5 Template save boundary | Data Integrity Task 6 |
| 6 Single-owner workout snapshot | Runtime Tasks 1-3 |
| 7 Scene/idle timer safety | Runtime Task 4 |
| 8 Replacement callback identity | Runtime Task 5 |
| 9 Avatar latest selection | Runtime Task 6 |
| 10 Ordered settings | Runtime Task 7 |
| 11 Measurement strategy | SwiftUI Performance Tasks 1 and 11 |
| 12 Catalog scroll invalidation | SwiftUI Performance Task 2 |
| 13 Grid debounce ownership | SwiftUI Performance Task 3 |
| 14 One render projection per edit | SwiftUI Performance Task 5 |
| 15 Lazy finish model | SwiftUI Performance Task 6 |
| 16 Start Workout refresh/indexing | SwiftUI Performance Task 7 |
| 17 History/grid collection cost | SwiftUI Performance Tasks 4 and 8 |
| 18 Heavy-view decomposition | SwiftUI Performance Tasks 9-10 |
| 19 Strict concurrency/Swift 6 | Strict Concurrency Tasks 1-6 |
| 20 Time-sensitive notifications | Apple Platform Task 1 |
| 21 Resizable iPad/landscape | Apple Platform Task 3 |
| 22 Window-relative geometry | Apple Platform Task 2 |
| 23 Accessibility/Dynamic Type | Apple Platform Task 4 |
| 24 Widget section deep link | Apple Platform Task 5 |
| 25 Capability cleanup | Apple Platform Task 6 |
| 26 String Catalog | Apple Platform Task 7 |
| 27 Deterministic previews | Apple Platform Task 8 |
| 28 Unit/integration suite | Verification Tasks 1-2 |
| 29 UI-test rehabilitation | Verification Tasks 3-4 |
| 30 Performance validation | Verification Task 5 and SwiftUI Performance Task 11 |
| 31 Final validation matrix | Verification Task 6 |

## Program Done Gate

The program is complete only when:

- every checkbox in the six detailed plans is complete or has an evidence-backed decision recorded in the verification report;
- all unit and UI tests pass on the specified phone/iPad destinations;
- Swift 5 complete checking and Swift 6 all-target builds have zero concurrency warnings;
- deterministic performance counters meet their targets and same-condition runtime metrics do not regress;
- signed app/widget entitlements and Info configuration match the platform plan;
- physical notification, iPad resizing, VoiceOver/Inspector, Dynamic Type, contrast, Reduce Motion, and privacy-log checks are recorded;
- `git diff --check` is clean and the final diff contains no unrelated work.
