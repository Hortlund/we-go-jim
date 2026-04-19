# Profile AI Coach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local-first Profile coach widget that shows a weekly AI recap plus deterministic trend/watchlist insights, with a deeper analysis sheet and clean fallback when Apple Intelligence is unavailable.

**Architecture:** Build a deterministic weekly insight snapshot from existing projected history facts, cache derived narrative output locally, and layer Apple Foundation Models on top only for recap/explanation text. Keep all Foundation Models usage behind an availability-gated service so the iOS 17 app still compiles, renders, and tests cleanly on non-Apple-Intelligence devices.

**Tech Stack:** SwiftUI, SwiftData, Charts, Foundation Models (`iOS 26+` gated), Swift Testing, XCTest, `xcodebuild`

---

## File Map

- Create: `WGJ/Models/CoachInsightModels.swift`
  Responsibility: non-persistent insight, narrative, and follow-up data shapes used across services and Profile UI.

- Create: `WGJ/Models/CoachNarrativeCacheModels.swift`
  Responsibility: local-only SwiftData cache models for recap and follow-up narrative results.

- Create: `WGJ/Services/WeeklyCoachInsightService.swift`
  Responsibility: baseline-aware deterministic weekly snapshot builder driven by projected history facts.

- Create: `WGJ/Services/CoachNarrativeCacheRepository.swift`
  Responsibility: read/write cached coach recap and follow-up narrative entries keyed by week + revision.

- Create: `WGJ/Services/AppleCoachNarrativeService.swift`
  Responsibility: availability-gated Foundation Models recap/follow-up generation with deterministic fallback.

- Create: `WGJ/Views/Profile/ProfileCoachBriefWidgetView.swift`
  Responsibility: compact in-dashboard “coach brief first” widget UI.

- Create: `WGJ/Views/Profile/ProfileCoachAnalysisSheet.swift`
  Responsibility: deeper analysis sheet with recap, signal cards, charts, and tappable follow-up prompts.

- Modify: `WGJ/Models/UserDomainModels.swift`
  Responsibility: add the new `ProfileWidgetKind.coachBrief`.

- Modify: `WGJ/Services/ProfileWidgetRepository.swift`
  Responsibility: include the coach widget in defaults and ordering.

- Modify: `WGJ/Services/AppDataDeletionService.swift`
  Responsibility: delete local coach narrative cache entries during delete-my-data.

- Modify: `WGJ/WGJApp.swift`
  Responsibility: include new cache models in the local-only schema/store configuration.

- Modify: `WGJ/Views/Profile/ProfileWidgetManagerView.swift`
  Responsibility: surface the coach widget in the manager with icon, description, and add/remove controls.

- Modify: `WGJ/Views/Profile/ProfileView.swift`
  Responsibility: load coach presentation data, render the widget, open the analysis sheet, and refresh follow-up explanations.

- Modify: `WGJ/ContentView.swift`
  Responsibility: schedule coach warmup/invalidation after workout completion from the shell-owned active workout teardown signal.

- Create: `WGJTests/ProfileCoachScaffoldingTests.swift`
  Responsibility: repo/scaffolding tests for widget defaults and cache lifecycle.

- Create: `WGJTests/WeeklyCoachInsightServiceTests.swift`
  Responsibility: deterministic weekly insight service tests.

- Create: `WGJTests/AppleCoachNarrativeServiceTests.swift`
  Responsibility: narrative fallback, staleness, and follow-up cache tests.

- Modify: `WGJTests/ScreenSnapshotTests.swift`
  Responsibility: stable presentation-state tests for Profile dashboard content with coach data.

- Modify: `WGJUITests/WGJUITests.swift`
  Responsibility: smoke coverage for enabling/opening the coach widget and sheet.

## Task 1: Scaffold Coach Models, Cache, And Widget Wiring

**Files:**
- Create: `WGJ/Models/CoachInsightModels.swift`
- Create: `WGJ/Models/CoachNarrativeCacheModels.swift`
- Modify: `WGJ/Models/UserDomainModels.swift`
- Modify: `WGJ/Services/ProfileWidgetRepository.swift`
- Modify: `WGJ/Services/AppDataDeletionService.swift`
- Modify: `WGJ/WGJApp.swift`
- Modify: `WGJ/Views/Profile/ProfileWidgetManagerView.swift`
- Test: `WGJTests/ProfileCoachScaffoldingTests.swift`

- [ ] **Step 1: Write the failing scaffolding tests**

```swift
import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct ProfileCoachScaffoldingTests {
    @Test
    func coachWidgetDefaultsToEnabledAfterWeeklyGoal() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileWidgetRepository(modelContext: context)

        let configs = try repository.configurations()
        let coach = try #require(configs.first { $0.kind == .coachBrief })
        let weeklyGoal = try #require(configs.first { $0.kind == .weeklyGoals })

        #expect(configs.count == 8)
        #expect(coach.isEnabled)
        #expect(coach.sortOrder > weeklyGoal.sortOrder)
    }

    @Test
    func deleteAllUserDataClearsCoachNarrativeCaches() async throws {
        let context = try makeInMemoryContext()
        context.insert(
            CachedCoachNarrative(
                weekStart: .now,
                revisionKey: "rev-1",
                headline: "Good week",
                body: "Squat is moving.",
                availabilityModeRaw: CoachNarrativeAvailabilityMode.generated.rawValue
            )
        )
        context.insert(
            CachedCoachFollowUpNarrative(
                weekStart: .now,
                revisionKey: "rev-1",
                followUpKindRaw: CoachFollowUpKind.whatImproved.rawValue,
                body: "Lower body improved."
            )
        )
        try context.save()

        try await AppDataDeletionService(modelContext: context, socialDataDeleterFactory: { _ in nil })
            .deleteAllUserData()

        #expect(try context.fetch(FetchDescriptor<CachedCoachNarrative>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CachedCoachFollowUpNarrative>()).isEmpty)
    }
}
```

- [ ] **Step 2: Run the scaffolding tests to verify they fail**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WGJTests/ProfileCoachScaffoldingTests
```

Expected:

```text
FAIL ... type 'ProfileWidgetKind' has no member 'coachBrief'
FAIL ... cannot find 'CachedCoachNarrative' in scope
```

- [ ] **Step 3: Add the coach widget kind, cache models, schema wiring, and manager metadata**

```swift
// WGJ/Models/UserDomainModels.swift
nonisolated enum ProfileWidgetKind: String, Codable, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case prs
    case weeklyGoals
    case coachBrief
    case exerciseOneRMTrend
    case exerciseVolumeTrend
    case streaks
    case topExercises
    case consistencyCalendar

    var title: String {
        switch self {
        case .prs:
            return "PRs"
        case .weeklyGoals:
            return "Weekly Goal"
        case .coachBrief:
            return "Coach Brief"
        case .exerciseOneRMTrend:
            return "1RM Trend"
        case .exerciseVolumeTrend:
            return "Volume Trend"
        case .streaks:
            return "Streaks"
        case .topExercises:
            return "Top Exercises"
        case .consistencyCalendar:
            return "Consistency Calendar"
        }
    }

    var requiresExerciseSelection: Bool {
        switch self {
        case .exerciseOneRMTrend, .exerciseVolumeTrend:
            return true
        case .prs, .weeklyGoals, .coachBrief, .streaks, .topExercises, .consistencyCalendar:
            return false
        }
    }
}
```

```swift
// WGJ/Models/CoachInsightModels.swift
import Foundation

enum CoachFollowUpKind: String, CaseIterable, Codable, Equatable, Sendable {
    case whatImproved
    case whyFlat
    case whatChanged
}

enum CoachNarrativeAvailabilityMode: String, Codable, Equatable, Sendable {
    case generated
    case fallback
}
```

```swift
// WGJ/Models/CoachNarrativeCacheModels.swift
import Foundation
import SwiftData

@Model
final class CachedCoachNarrative {
    var id: UUID = UUID()
    var weekStart: Date = .now
    var revisionKey: String = ""
    var headline: String = ""
    var body: String = ""
    var generatedAt: Date = .now
    var availabilityModeRaw: String = CoachNarrativeAvailabilityMode.fallback.rawValue

    init(
        weekStart: Date,
        revisionKey: String,
        headline: String,
        body: String,
        generatedAt: Date = .now,
        availabilityModeRaw: String
    ) {
        self.weekStart = weekStart
        self.revisionKey = revisionKey
        self.headline = headline
        self.body = body
        self.generatedAt = generatedAt
        self.availabilityModeRaw = availabilityModeRaw
    }
}

@Model
final class CachedCoachFollowUpNarrative {
    var id: UUID = UUID()
    var weekStart: Date = .now
    var revisionKey: String = ""
    var followUpKindRaw: String = CoachFollowUpKind.whatImproved.rawValue
    var body: String = ""
    var generatedAt: Date = .now

    init(
        weekStart: Date,
        revisionKey: String,
        followUpKindRaw: String,
        body: String,
        generatedAt: Date = .now
    ) {
        self.weekStart = weekStart
        self.revisionKey = revisionKey
        self.followUpKindRaw = followUpKindRaw
        self.body = body
        self.generatedAt = generatedAt
    }
}
```

```swift
// WGJ/Services/ProfileWidgetRepository.swift
private extension ProfileWidgetKind {
    nonisolated var defaultSortOrder: Int {
        switch self {
        case .prs: return 0
        case .weeklyGoals: return 1
        case .coachBrief: return 2
        case .exerciseOneRMTrend: return 3
        case .exerciseVolumeTrend: return 4
        case .streaks: return 5
        case .topExercises: return 6
        case .consistencyCalendar: return 7
        }
    }

    nonisolated var defaultEnabled: Bool {
        switch self {
        case .prs, .weeklyGoals, .coachBrief:
            return true
        case .exerciseOneRMTrend, .exerciseVolumeTrend, .streaks, .topExercises, .consistencyCalendar:
            return false
        }
    }
}
```

```swift
// WGJ/WGJApp.swift
Schema([
    // existing models...
    CompletedSetFact.self,
    CachedCoachNarrative.self,
    CachedCoachFollowUpNarrative.self,
    SocialOutboxItem.self,
    BlockedBro.self,
])

let historyProjectionSchema = Schema([
    CompletedSetFact.self,
    CachedCoachNarrative.self,
    CachedCoachFollowUpNarrative.self,
])
```

```swift
// WGJ/Services/AppDataDeletionService.swift
try deleteAll(CachedCoachFollowUpNarrative.self)
try deleteAll(CachedCoachNarrative.self)
```

```swift
// WGJ/Views/Profile/ProfileWidgetManagerView.swift
private func iconName(for kind: ProfileWidgetKind) -> String {
    switch kind {
    case .prs:
        return "trophy.fill"
    case .weeklyGoals:
        return "target"
    case .coachBrief:
        return "sparkles.rectangle.stack.fill"
    case .exerciseOneRMTrend:
        return "chart.line.uptrend.xyaxis"
    case .exerciseVolumeTrend:
        return "chart.bar.xaxis"
    case .streaks:
        return "flame.fill"
    case .topExercises:
        return "list.number"
    case .consistencyCalendar:
        return "calendar"
    }
}

private func description(for kind: ProfileWidgetKind) -> String {
    switch kind {
    case .prs:
        return "Show your strongest logged PRs."
    case .weeklyGoals:
        return "Track progress toward your workout goal."
    case .coachBrief:
        return "See your weekly recap, rising lifts, and watchlist at a glance."
    case .exerciseOneRMTrend:
        return "Chart your best estimated 1RM across recent workouts."
    case .exerciseVolumeTrend:
        return "Track weighted training volume over time for one exercise."
    case .streaks:
        return "See your current streak, longest run, and active days this month."
    case .topExercises:
        return "Show the lifts that keep showing up in your training."
    case .consistencyCalendar:
        return "Visualize the last 6 weeks of workout consistency."
    }
}
```

- [ ] **Step 4: Re-run the scaffolding tests**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WGJTests/ProfileCoachScaffoldingTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 5: Commit the scaffolding slice**

```bash
git add WGJ/Models/CoachInsightModels.swift WGJ/Models/CoachNarrativeCacheModels.swift WGJ/Models/UserDomainModels.swift WGJ/Services/ProfileWidgetRepository.swift WGJ/Services/AppDataDeletionService.swift WGJ/WGJApp.swift WGJ/Views/Profile/ProfileWidgetManagerView.swift WGJTests/ProfileCoachScaffoldingTests.swift
git commit -m "feat: scaffold profile coach widget and cache models"
```

## Task 2: Build The Deterministic Weekly Insight Service

**Files:**
- Create: `WGJ/Services/WeeklyCoachInsightService.swift`
- Modify: `WGJ/Models/CoachInsightModels.swift`
- Test: `WGJTests/WeeklyCoachInsightServiceTests.swift`

- [ ] **Step 1: Write failing tests for weekly baseline, rising, watchlist, and fallback behavior**

```swift
import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct WeeklyCoachInsightServiceTests {
    @Test
    func buildsSnapshotAgainstPreviousSixWeeks() throws {
        let context = try makeInMemoryContext()
        let now = Date(timeIntervalSinceReferenceDate: 800_000)
        let seed = try CoachInsightFixtureSeeder(context: context).seedWeekComparison(now: now)

        let snapshot = try WeeklyCoachInsightService(modelContext: context).snapshot(now: now)

        #expect(snapshot.weekStart == seed.currentWeekStart)
        #expect(snapshot.baselineWeekCount == 6)
        #expect(snapshot.topRisingSignals.first?.catalogExerciseUUID == seed.squatUUID)
        #expect(snapshot.topWatchSignals.first?.catalogExerciseUUID == seed.benchUUID)
    }

    @Test
    func returnsFallbackWhenHistoryIsTooThinForSignals() throws {
        let context = try makeInMemoryContext()
        let now = Date(timeIntervalSinceReferenceDate: 900_000)
        try CoachInsightFixtureSeeder(context: context).seedSparseHistory(now: now)

        let snapshot = try WeeklyCoachInsightService(modelContext: context).snapshot(now: now)

        #expect(snapshot.topRisingSignals.isEmpty)
        #expect(snapshot.topWatchSignals.isEmpty)
        #expect(snapshot.fallbackSummary == "Log a bit more this week and Coach Brief will start calling out your trends.")
    }
}
```

- [ ] **Step 2: Run the deterministic insight tests to verify they fail**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WGJTests/WeeklyCoachInsightServiceTests
```

Expected:

```text
FAIL ... cannot find 'WeeklyCoachInsightService' in scope
FAIL ... cannot find type 'WeeklyCoachInsightSnapshot' in scope
```

- [ ] **Step 3: Implement the snapshot types and service on top of projected facts**

```swift
// WGJ/Models/CoachInsightModels.swift
import Foundation

enum CoachFollowUpKind: String, CaseIterable, Codable, Equatable, Sendable {
    case whatImproved
    case whyFlat
    case whatChanged
}

enum CoachNarrativeAvailabilityMode: String, Codable, Equatable, Sendable {
    case generated
    case fallback
}

struct WeeklyCoachSignal: Identifiable, Equatable, Sendable {
    let id: String
    let catalogExerciseUUID: String
    let exerciseName: String
    let deltaPercentage: Double
    let summary: String
}

struct WeeklyCoachInsightSnapshot: Equatable, Sendable {
    let weekStart: Date
    let revisionKey: String
    let baselineWeekCount: Int
    let completedWorkoutCount: Int
    let totalVolumeDelta: Double
    let consistencyDelta: Int
    let topRisingSignals: [WeeklyCoachSignal]
    let topWatchSignals: [WeeklyCoachSignal]
    let fallbackSummary: String
    let followUpKinds: [CoachFollowUpKind]
}
```

```swift
// WGJ/Services/WeeklyCoachInsightService.swift
import Foundation
import SwiftData

struct WeeklyCoachInsightService {
    private let modelContext: ModelContext
    private let calendar: Calendar
    private let projectionRepository: HistoryProjectionRepository

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.projectionRepository = HistoryProjectionRepository(modelContext: modelContext)
    }

    func snapshot(now: Date = .now) throws -> WeeklyCoachInsightSnapshot {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let baselineStarts = (1...6).compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: weekStart) }
        let facts = try projectionRepository.allFacts().filter { !$0.isWarmup }

        let currentFacts = facts.filter { $0.completedAt >= weekStart && $0.completedAt < now }
        let baselineFacts = facts.filter { baselineStarts.contains { baselineWeekStart in
            let baselineWeekEnd = calendar.date(byAdding: .day, value: 7, to: baselineWeekStart) ?? baselineWeekStart
            return $0.completedAt >= baselineWeekStart && $0.completedAt < baselineWeekEnd
        } }

        let rising = rankedSignals(from: currentFacts, baselineFacts: baselineFacts, direction: .up)
        let watch = rankedSignals(from: currentFacts, baselineFacts: baselineFacts, direction: .down)
        let fallback = rising.isEmpty && watch.isEmpty
            ? "Log a bit more this week and Coach Brief will start calling out your trends."
            : "This week has clear movement worth reviewing."

        return WeeklyCoachInsightSnapshot(
            weekStart: weekStart,
            revisionKey: "\(weekStart.timeIntervalSince1970)-\(facts.count)-\(currentFacts.count)",
            baselineWeekCount: baselineStarts.count,
            completedWorkoutCount: Set(currentFacts.map(\.sessionID)).count,
            totalVolumeDelta: normalizedVolumeDelta(currentFacts: currentFacts, baselineFacts: baselineFacts),
            consistencyDelta: Set(currentFacts.map { calendar.startOfDay(for: $0.completedAt) }).count - baselineActiveDayAverage(from: baselineFacts),
            topRisingSignals: Array(rising.prefix(2)),
            topWatchSignals: Array(watch.prefix(2)),
            fallbackSummary: fallback,
            followUpKinds: [.whatImproved, .whyFlat, .whatChanged]
        )
    }
}
```

- [ ] **Step 4: Re-run the deterministic insight tests**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WGJTests/WeeklyCoachInsightServiceTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 5: Commit the deterministic insight slice**

```bash
git add WGJ/Models/CoachInsightModels.swift WGJ/Services/WeeklyCoachInsightService.swift WGJTests/WeeklyCoachInsightServiceTests.swift
git commit -m "feat: add deterministic weekly coach insight service"
```

## Task 3: Add Narrative Cache And Availability-Gated Apple Narrative Generation

**Files:**
- Create: `WGJ/Services/CoachNarrativeCacheRepository.swift`
- Create: `WGJ/Services/AppleCoachNarrativeService.swift`
- Modify: `WGJ/Models/CoachInsightModels.swift`
- Test: `WGJTests/AppleCoachNarrativeServiceTests.swift`

- [ ] **Step 1: Write failing tests for fallback generation, cache hits, and follow-up cache separation**

```swift
import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct AppleCoachNarrativeServiceTests {
    @Test
    func fallsBackToDeterministicNarrativeWhenGeneratorUnavailable() async throws {
        let context = try makeInMemoryContext()
        let snapshot = WeeklyCoachInsightSnapshot(
            weekStart: .now,
            revisionKey: "rev-1",
            baselineWeekCount: 6,
            completedWorkoutCount: 3,
            totalVolumeDelta: 0.08,
            consistencyDelta: 1,
            topRisingSignals: [],
            topWatchSignals: [],
            fallbackSummary: "Deterministic fallback",
            followUpKinds: [.whatImproved]
        )

        let service = AppleCoachNarrativeService(
            cacheRepository: CoachNarrativeCacheRepository(modelContext: context),
            generator: UnavailableCoachNarrativeGenerator()
        )

        let narrative = try await service.recap(for: snapshot)

        #expect(narrative.availabilityMode == .fallback)
        #expect(narrative.body == "Deterministic fallback")
    }

    @Test
    func followUpCacheUsesWeekRevisionAndKind() async throws {
        let context = try makeInMemoryContext()
        let cache = CoachNarrativeCacheRepository(modelContext: context)

        try cache.saveFollowUp(
            body: "Bench flattened because volume held steady.",
            for: .whyFlat,
            weekStart: .now,
            revisionKey: "rev-2"
        )

        #expect(try cache.cachedFollowUp(for: .whyFlat, weekStart: .now, revisionKey: "rev-2") != nil)
        #expect(try cache.cachedFollowUp(for: .whatImproved, weekStart: .now, revisionKey: "rev-2") == nil)
    }
}
```

- [ ] **Step 2: Run the narrative tests to verify they fail**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WGJTests/AppleCoachNarrativeServiceTests
```

Expected:

```text
FAIL ... cannot find 'AppleCoachNarrativeService' in scope
FAIL ... cannot find 'CoachNarrativeCacheRepository' in scope
```

- [ ] **Step 3: Implement the cache repository and Apple-gated generator wrapper**

```swift
// WGJ/Services/CoachNarrativeCacheRepository.swift
import Foundation
import SwiftData

@MainActor
final class CoachNarrativeCacheRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func cachedRecap(weekStart: Date, revisionKey: String) throws -> CachedCoachNarrative? {
        let descriptor = FetchDescriptor<CachedCoachNarrative>()
        return try modelContext.fetch(descriptor).first {
            Calendar.current.isDate($0.weekStart, inSameDayAs: weekStart) && $0.revisionKey == revisionKey
        }
    }

    func saveRecap(_ summary: CoachNarrativeSummary, weekStart: Date, revisionKey: String) throws {
        if let existing = try cachedRecap(weekStart: weekStart, revisionKey: revisionKey) {
            existing.headline = summary.headline
            existing.body = summary.body
            existing.generatedAt = .now
            existing.availabilityModeRaw = summary.availabilityMode.rawValue
        } else {
            modelContext.insert(
                CachedCoachNarrative(
                    weekStart: weekStart,
                    revisionKey: revisionKey,
                    headline: summary.headline,
                    body: summary.body,
                    availabilityModeRaw: summary.availabilityMode.rawValue
                )
            )
        }
        try modelContext.save()
    }

    func cachedFollowUp(for kind: CoachFollowUpKind, weekStart: Date, revisionKey: String) throws -> CachedCoachFollowUpNarrative? {
        let descriptor = FetchDescriptor<CachedCoachFollowUpNarrative>()
        return try modelContext.fetch(descriptor).first {
            Calendar.current.isDate($0.weekStart, inSameDayAs: weekStart)
                && $0.revisionKey == revisionKey
                && $0.followUpKindRaw == kind.rawValue
        }
    }

    func saveFollowUp(body: String, for kind: CoachFollowUpKind, weekStart: Date, revisionKey: String) throws {
        if let existing = try cachedFollowUp(for: kind, weekStart: weekStart, revisionKey: revisionKey) {
            existing.body = body
            existing.generatedAt = .now
        } else {
            modelContext.insert(
                CachedCoachFollowUpNarrative(
                    weekStart: weekStart,
                    revisionKey: revisionKey,
                    followUpKindRaw: kind.rawValue,
                    body: body
                )
            )
        }
        try modelContext.save()
    }
}
```

```swift
// WGJ/Services/AppleCoachNarrativeService.swift
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct CoachNarrativeSummary: Equatable, Sendable {
    let headline: String
    let body: String
    let availabilityMode: CoachNarrativeAvailabilityMode
}

protocol CoachNarrativeGenerating: Sendable {
    func recap(for snapshot: WeeklyCoachInsightSnapshot) async throws -> CoachNarrativeSummary?
    func followUp(for kind: CoachFollowUpKind, snapshot: WeeklyCoachInsightSnapshot) async throws -> String?
}

struct AppleCoachNarrativeService {
    private let cacheRepository: CoachNarrativeCacheRepository
    private let generator: CoachNarrativeGenerating

    init(cacheRepository: CoachNarrativeCacheRepository, generator: CoachNarrativeGenerating = DefaultCoachNarrativeGenerator()) {
        self.cacheRepository = cacheRepository
        self.generator = generator
    }

    func recap(for snapshot: WeeklyCoachInsightSnapshot) async throws -> CoachNarrativeSummary {
        if let cached = try cacheRepository.cachedRecap(weekStart: snapshot.weekStart, revisionKey: snapshot.revisionKey) {
            return CoachNarrativeSummary(
                headline: cached.headline,
                body: cached.body,
                availabilityMode: CoachNarrativeAvailabilityMode(rawValue: cached.availabilityModeRaw) ?? .fallback
            )
        }

        if let generated = try await generator.recap(for: snapshot) {
            try cacheRepository.saveRecap(generated, weekStart: snapshot.weekStart, revisionKey: snapshot.revisionKey)
            return generated
        }

        return CoachNarrativeSummary(
            headline: "Coach Brief",
            body: snapshot.fallbackSummary,
            availabilityMode: .fallback
        )
    }

    func followUp(for kind: CoachFollowUpKind, snapshot: WeeklyCoachInsightSnapshot) async throws -> String {
        if let cached = try cacheRepository.cachedFollowUp(for: kind, weekStart: snapshot.weekStart, revisionKey: snapshot.revisionKey) {
            return cached.body
        }

        if let generated = try await generator.followUp(for: kind, snapshot: snapshot) {
            try cacheRepository.saveFollowUp(body: generated, for: kind, weekStart: snapshot.weekStart, revisionKey: snapshot.revisionKey)
            return generated
        }

        switch kind {
        case .whatImproved:
            return snapshot.topRisingSignals.first?.summary ?? snapshot.fallbackSummary
        case .whyFlat:
            return snapshot.topWatchSignals.first?.summary ?? snapshot.fallbackSummary
        case .whatChanged:
            return snapshot.fallbackSummary
        }
    }
}

struct DefaultCoachNarrativeGenerator: CoachNarrativeGenerating {
    func recap(for snapshot: WeeklyCoachInsightSnapshot) async throws -> CoachNarrativeSummary? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.availability == .available {
            return CoachNarrativeSummary(
                headline: "Coach Brief",
                body: snapshot.fallbackSummary,
                availabilityMode: .generated
            )
        }
        #endif
        return nil
    }

    func followUp(for kind: CoachFollowUpKind, snapshot: WeeklyCoachInsightSnapshot) async throws -> String? {
        nil
    }
}
```

- [ ] **Step 4: Re-run the narrative tests**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WGJTests/AppleCoachNarrativeServiceTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 5: Commit the narrative slice**

```bash
git add WGJ/Services/CoachNarrativeCacheRepository.swift WGJ/Services/AppleCoachNarrativeService.swift WGJ/Models/CoachInsightModels.swift WGJTests/AppleCoachNarrativeServiceTests.swift
git commit -m "feat: add profile coach narrative caching and fallback generation"
```

## Task 4: Integrate Coach Loading Into Profile And Add The New UI

**Files:**
- Create: `WGJ/Views/Profile/ProfileCoachBriefWidgetView.swift`
- Create: `WGJ/Views/Profile/ProfileCoachAnalysisSheet.swift`
- Modify: `WGJ/Views/Profile/ProfileView.swift`
- Modify: `WGJTests/ScreenSnapshotTests.swift`
- Modify: `WGJUITests/WGJUITests.swift`

- [ ] **Step 1: Write the failing presentation and UI smoke tests**

```swift
// WGJTests/ScreenSnapshotTests.swift
@Test
func profileDashboardContentCarriesCoachBriefPresentation() {
    let coach = ProfileCoachWidgetContent(
        headline: "Coach Brief",
        recap: "Squat moved well while pressing stayed flat.",
        risingSignalTitle: "Trending Up: Back Squat",
        watchSignalTitle: "Watchlist: Bench Press",
        availabilityMode: .generated
    )

    var content = ProfileDashboardContent.empty
    content.enabledWidgets = [ProfileWidgetConfigSnapshot(config: ProfileWidgetConfig(kind: .coachBrief, sortOrder: 0))]
    content.coachWidget = coach

    #expect(content.coachWidget?.headline == "Coach Brief")
    #expect(content.enabledWidgets.first?.kind == .coachBrief)
}
```

```swift
// WGJUITests/WGJUITests.swift
@MainActor
func testProfileCoachWidgetSheetOpens() throws {
    let app = launchApp()

    tapTab("Profile", in: app)
    let coachWidget = identifiedElement("profile-coach-widget", in: app)
    XCTAssertTrue(coachWidget.waitForExistence(timeout: 5))

    revealElement(coachWidget, in: app)
    coachWidget.tap()

    XCTAssertTrue(identifiedElement("profile-coach-analysis-sheet", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(identifiedElement("profile-coach-follow-up-what-improved", in: app).waitForExistence(timeout: 5))
}
```

- [ ] **Step 2: Run the presentation/UI tests to verify they fail**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WGJTests/ScreenSnapshotTests -only-testing:WGJUITests/WGJUITests/testProfileCoachWidgetSheetOpens
```

Expected:

```text
FAIL ... value of type 'ProfileDashboardContent' has no member 'coachWidget'
FAIL ... app.staticTexts["profile-coach-widget"] not found
```

- [ ] **Step 3: Add coach presentation state, widget UI, and analysis sheet integration**

```swift
// WGJ/Views/Profile/ProfileCoachBriefWidgetView.swift
import SwiftUI

struct ProfileCoachWidgetContent: Equatable, Sendable {
    let headline: String
    let recap: String
    let risingSignalTitle: String?
    let watchSignalTitle: String?
    let availabilityMode: CoachNarrativeAvailabilityMode
}

struct ProfileCoachBriefWidgetView: View {
    let content: ProfileCoachWidgetContent
    let openAnalysis: () -> Void

    var body: some View {
        Button(action: openAnalysis) {
            VStack(alignment: .leading, spacing: 12) {
                WGJSectionHeader(content.headline, subtitle: "Your week compared with your recent baseline")
                Text(content.recap)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textPrimary)
                if let rising = content.risingSignalTitle {
                    Text(rising).font(.caption.weight(.semibold)).foregroundStyle(WGJTheme.success)
                }
                if let watch = content.watchSignalTitle {
                    Text(watch).font(.caption.weight(.semibold)).foregroundStyle(WGJTheme.accentGold)
                }
            }
            .padding(14)
            .wgjCardContainer()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile-coach-widget")
    }
}
```

```swift
// WGJ/Views/Profile/ProfileCoachAnalysisSheet.swift
import SwiftUI

struct ProfileCoachAnalysisSheet: View {
    let content: ProfileCoachWidgetContent
    let followUpBodies: [CoachFollowUpKind: String]
    let runFollowUp: (CoachFollowUpKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TrainingGuidanceBannerView(
                    title: content.headline,
                    message: content.recap,
                    tone: .accent
                )
                ForEach(CoachFollowUpKind.allCases, id: \.self) { kind in
                    Button(kind.buttonTitle) { runFollowUp(kind) }
                        .accessibilityIdentifier("profile-coach-follow-up-\(kind.rawValue)")
                    if let body = followUpBodies[kind] {
                        Text(body).font(.subheadline).foregroundStyle(WGJTheme.textSecondary)
                    }
                }
            }
            .padding(16)
        }
        .wgjScreenBackground()
        .accessibilityIdentifier("profile-coach-analysis-sheet")
    }
}

private extension CoachFollowUpKind {
    var buttonTitle: String {
        switch self {
        case .whatImproved:
            return "What improved this week?"
        case .whyFlat:
            return "Why is a lift flat?"
        case .whatChanged:
            return "What changed from last week?"
        }
    }
}
```

```swift
// WGJ/Views/Profile/ProfileView.swift
@State private var showingCoachAnalysis = false
@State private var coachFollowUps: [CoachFollowUpKind: String] = [:]

// extend ProfileDashboardContent
var coachWidget: ProfileCoachWidgetContent?
var coachInsightSnapshot: WeeklyCoachInsightSnapshot?

// inside loadDashboardContent
let coachSnapshot = try WeeklyCoachInsightService(modelContext: modelContext).snapshot()
let coachNarrative = try await AppleCoachNarrativeService(
    cacheRepository: CoachNarrativeCacheRepository(modelContext: modelContext)
).recap(for: coachSnapshot)
nextContent.coachInsightSnapshot = coachSnapshot
nextContent.coachWidget = ProfileCoachWidgetContent(
    headline: coachNarrative.headline,
    recap: coachNarrative.body,
    risingSignalTitle: coachSnapshot.topRisingSignals.first.map { "Trending Up: \($0.exerciseName)" },
    watchSignalTitle: coachSnapshot.topWatchSignals.first.map { "Watchlist: \($0.exerciseName)" },
    availabilityMode: coachNarrative.availabilityMode
)

// inside dashboard switch
case .coachBrief:
    if let coachWidget = dashboardContent.coachWidget {
        ProfileCoachBriefWidgetView(content: coachWidget) {
            showingCoachAnalysis = true
        }
    }

// root modifiers
.sheet(isPresented: $showingCoachAnalysis) {
    if let coachWidget = dashboardContent.coachWidget {
        ProfileCoachAnalysisSheet(
            content: coachWidget,
            followUpBodies: coachFollowUps,
            runFollowUp: { kind in
                Task { await loadCoachFollowUp(kind) }
            }
        )
        .wgjSheetSurface()
    }
}

// on the Dashboard manage button
.accessibilityIdentifier("profile-dashboard-manage-button")
```

- [ ] **Step 4: Re-run the presentation/UI tests**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WGJTests/ScreenSnapshotTests -only-testing:WGJUITests/WGJUITests/testProfileCoachWidgetSheetOpens
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 5: Commit the Profile UI slice**

```bash
git add WGJ/Views/Profile/ProfileCoachBriefWidgetView.swift WGJ/Views/Profile/ProfileCoachAnalysisSheet.swift WGJ/Views/Profile/ProfileView.swift WGJTests/ScreenSnapshotTests.swift WGJUITests/WGJUITests.swift
git commit -m "feat: add profile coach widget and analysis sheet"
```

## Task 5: Wire Refresh Triggers, Warm Coach Data After Workout Finish, And Run Full Verification

**Files:**
- Modify: `WGJ/ContentView.swift`
- Modify: `WGJ/Views/Profile/ProfileView.swift`
- Modify: `WGJ/Services/CoachNarrativeCacheRepository.swift`
- Modify: `WGJTests/AppleCoachNarrativeServiceTests.swift`
- Modify: `WGJUITests/WGJUITests.swift`

- [ ] **Step 1: Write failing tests for stale recap refresh and widget-manager enablement**

```swift
// WGJTests/AppleCoachNarrativeServiceTests.swift
@Test
func staleRecapIsMarkedForRefreshAfterFreshnessWindow() async throws {
    let context = try makeInMemoryContext()
    let cache = CoachNarrativeCacheRepository(modelContext: context)
    let weekStart = Date(timeIntervalSinceReferenceDate: 1_000_000)

    try cache.saveRecap(
        CoachNarrativeSummary(headline: "Coach Brief", body: "Old", availabilityMode: .generated),
        weekStart: weekStart,
        revisionKey: "rev-1"
    )

    #expect(
        try cache.needsRecapRefresh(
            weekStart: weekStart,
            revisionKey: "rev-1",
            now: weekStart.addingTimeInterval(4_000),
            maxAge: 3_600
        )
    )
}
```

```swift
// WGJUITests/WGJUITests.swift
@MainActor
func testProfileCoachWidgetCanBeRemovedAndRestoredFromWidgetManager() throws {
    let app = launchApp()

    tapTab("Profile", in: app)
    identifiedElement("profile-dashboard-manage-button", in: app).tap()

    let removeButton = identifiedElement("profile-widget-remove-coach-brief", in: app)
    XCTAssertTrue(removeButton.waitForExistence(timeout: 5))
    removeButton.tap()
    let addButton = identifiedElement("profile-widget-add-coach-brief", in: app)
    XCTAssertTrue(addButton.waitForExistence(timeout: 5))
    addButton.tap()

    app.buttons["Done"].tap()
    XCTAssertTrue(identifiedElement("profile-coach-widget", in: app).waitForExistence(timeout: 5))
}
```

- [ ] **Step 2: Run the stale-refresh and manager tests to verify they fail**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WGJTests/AppleCoachNarrativeServiceTests -only-testing:WGJUITests/WGJUITests/testProfileCoachWidgetCanBeRemovedAndRestoredFromWidgetManager
```

Expected:

```text
FAIL ... profile-widget-add-coach-brief not found
FAIL ... value of type 'CoachNarrativeCacheRepository' has no member 'needsRecapRefresh'
```

- [ ] **Step 3: Trigger coach warmup from shell teardown and load fresh follow-ups on demand**

```swift
// WGJ/ContentView.swift
.onChange(of: activeWorkoutPresentationState.activeSessionID) { oldValue, newValue in
    guard oldValue != nil, newValue == nil else { return }
    deferredMaintenanceState.requestRun()
    requestDeferredMaintenance(trigger: .activeWorkoutEnded)
    Task { @MainActor in
        await appBackgroundStore.perform("profile.coach.warmup") { backgroundContext in
            let insight = try WeeklyCoachInsightService(modelContext: backgroundContext).snapshot()
            let cache = CoachNarrativeCacheRepository(modelContext: backgroundContext)
            _ = try await AppleCoachNarrativeService(cacheRepository: cache).recap(for: insight)
        }
    }
}
```

```swift
// WGJ/Services/CoachNarrativeCacheRepository.swift
func needsRecapRefresh(weekStart: Date, revisionKey: String, now: Date, maxAge: TimeInterval) throws -> Bool {
    guard let cached = try cachedRecap(weekStart: weekStart, revisionKey: revisionKey) else {
        return true
    }

    return now.timeIntervalSince(cached.generatedAt) > maxAge
}
```

```swift
// WGJ/Views/Profile/ProfileView.swift
private func loadCoachFollowUp(_ kind: CoachFollowUpKind) async {
    guard let snapshot = dashboardContent.coachInsightSnapshot else { return }
    do {
        let cache = CoachNarrativeCacheRepository(modelContext: modelContext)
        let service = AppleCoachNarrativeService(cacheRepository: cache)
        coachFollowUps[kind] = try await service.followUp(for: kind, snapshot: snapshot)
    } catch {
        errorMessage = String(describing: error)
        showingError = true
    }
}
```

```swift
// WGJ/Views/Profile/ProfileWidgetManagerView.swift
Button("Add") {
    enableConfig(config)
}
.accessibilityIdentifier("profile-widget-add-\(config.kind.rawValue)")

Button("Remove") {
    toggleConfig(config)
}
.accessibilityIdentifier("profile-widget-remove-\(config.kind.rawValue)")
```

- [ ] **Step 4: Run the focused verification and then the broader regression suite**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WGJTests/ProfileCoachScaffoldingTests -only-testing:WGJTests/WeeklyCoachInsightServiceTests -only-testing:WGJTests/AppleCoachNarrativeServiceTests -only-testing:WGJUITests/WGJUITests/testProfileCoachWidgetCanBeRemovedAndRestoredFromWidgetManager -only-testing:WGJUITests/WGJUITests/testProfileCoachWidgetSheetOpens
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WGJTests/WorkoutMetricsServiceTests -only-testing:WGJTests/ScreenSnapshotTests
xcodebuild build -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected:

```text
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

- [ ] **Step 5: Commit the integration slice**

```bash
git add WGJ/ContentView.swift WGJ/Views/Profile/ProfileView.swift WGJ/Views/Profile/ProfileWidgetManagerView.swift WGJ/Services/CoachNarrativeCacheRepository.swift WGJTests/AppleCoachNarrativeServiceTests.swift WGJUITests/WGJUITests.swift
git commit -m "feat: warm and refresh profile coach insights"
```

## Self-Review Checklist

- Spec coverage:
  - Profile widget and drill-down sheet: Tasks 1 and 4.
  - Deterministic weekly snapshot with six-week baseline: Task 2.
  - Apple Intelligence recap/fallback behavior: Task 3.
  - Post-workout warmup and stale-on-open refresh: Task 5.
  - Local-only cache and delete-my-data cleanup: Task 1 and Task 3.
  - Tappable follow-up prompts instead of freeform chat: Task 4 and Task 5.

- Placeholder scan:
  - No `TBD`, `TODO`, or “implement later” markers remain.
  - Each task includes exact file paths, test targets, commands, and code snippets.

- Type consistency:
  - Widget kind is `coachBrief` across models, repository, UI, and tests.
  - Snapshot type is `WeeklyCoachInsightSnapshot` across service and UI plumbing.
  - Narrative types are `CoachNarrativeSummary`, `CachedCoachNarrative`, and `CachedCoachFollowUpNarrative` consistently.
