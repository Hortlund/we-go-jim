# Workout Completion Celebration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Center workout-completion confetti and add a punchy, PR-aware hero celebration without blocking persistence, navigation, or interaction.

**Architecture:** Keep persistence and snapshot construction unchanged. Extend the existing deterministic celebration policy with variants, centered origin calculation, bounded palette/count choices, Reduced Motion values, and phase projections; then wire those values into WorkoutCompletionSummaryView using one local phase and the existing single-burst 30 FPS Canvas renderer.

**Tech Stack:** Swift 6, SwiftUI, UIKit haptics, XCTest, SwiftData, XcodeBuildMCP, iOS 17+

## Global Constraints

- Standard automatic completion uses one 38-piece burst.
- Personal-record automatic completion uses one 46-piece burst with stronger gold emphasis.
- Manual replay uses one 18-piece burst from the supplied tap origin.
- Keep Canvas at 30 FPS, generate particle values once per burst, and create no per-particle tasks.
- Hero spring lasts at most 600 milliseconds; glow finishes within 900 milliseconds.
- Reduced Motion keeps haptic/static highlight but skips confetti, spring, animated glow, and icon pop.
- Do not touch workout commit, summary fetch, CloudKit scheduling, or navigation boundaries.
- View History remains enabled throughout.
- Preserve the user's existing change in WGJ/WidgetShared/Localizable.xcstrings.

## File Structure

- Modify WGJ/Views/Workout/WorkoutCompletionSummaryView.swift: deterministic policy, existing renderer inputs, one local phase, and hero presentation.
- Modify WGJTests/WorkoutCompletionConfettiTests.swift: origin, variants, palette, Reduced Motion, and phase projections.
- Add no view model or service; celebration remains presentation-only local state.

---

### Task 1: Define the Centered, PR-Aware Policy

**Files:**
- Modify: WGJTests/WorkoutCompletionConfettiTests.swift
- Modify: WGJ/Views/Workout/WorkoutCompletionSummaryView.swift:5-89, 900-1090

**Interfaces:**
- Consumes: existing confetti descriptor, burst initializer, piece generator, and Canvas renderer.
- Produces: WorkoutCompletionCelebrationVariant, WorkoutCompletionConfettiColorRole, WorkoutCompletionCelebrationPresentation, the centered defaultOrigin API, and variant-aware burstDescriptors.

- [ ] **Step 1: Write failing centered-origin and variant tests**

Replace the first three tests in WorkoutCompletionConfettiTests with:

    func testStandardCompletionUsesOneCenteredBoundedBurst() {
        let origin = WorkoutCompletionConfettiOrigin.defaultOrigin(
            containerFrameInGlobalSpace: CGRect(x: 12, y: 48, width: 390, height: 780),
            fallbackContainerSize: .zero
        )
        let bursts = WorkoutCompletionConfettiPolicy.burstDescriptors(
            origin: origin,
            intensity: .completedWorkout,
            variant: .standard
        )

        XCTAssertEqual(origin, CGPoint(x: 207, y: 438))
        XCTAssertEqual(bursts.count, 1)
        XCTAssertEqual(bursts.first?.pieceCount, 38)
        XCTAssertEqual(bursts.first?.variant, .standard)
        XCTAssertEqual(bursts.first?.delay, 0)
    }

    func testPersonalRecordCompletionIsStrongerButBounded() {
        let bursts = WorkoutCompletionConfettiPolicy.burstDescriptors(
            origin: CGPoint(x: 195, y: 390),
            intensity: .completedWorkout,
            variant: .personalRecord
        )

        XCTAssertEqual(bursts.count, 1)
        XCTAssertEqual(bursts.first?.pieceCount, 46)
        XCTAssertEqual(bursts.first?.variant, .personalRecord)
        XCTAssertGreaterThan(
            WorkoutCompletionConfettiPolicy.colorRoles(for: .personalRecord)
                .filter { $0 == .gold }.count,
            WorkoutCompletionConfettiPolicy.colorRoles(for: .standard)
                .filter { $0 == .gold }.count
        )
    }

    func testManualReplayRetainsTapOriginAndLightCount() {
        let origin = CGPoint(x: 120, y: 220)
        let bursts = WorkoutCompletionConfettiPolicy.burstDescriptors(
            origin: origin,
            intensity: .manualTap,
            variant: .personalRecord
        )

        XCTAssertEqual(bursts.count, 1)
        XCTAssertEqual(bursts.first?.origin, origin)
        XCTAssertEqual(bursts.first?.pieceCount, 18)
    }

    func testAutomaticOriginUsesLocalMidpointThenLastResort() {
        XCTAssertEqual(
            WorkoutCompletionConfettiOrigin.defaultOrigin(
                containerFrameInGlobalSpace: CGRect(x: 0, y: 20, width: 440, height: 880),
                fallbackContainerSize: .zero
            ),
            CGPoint(x: 220, y: 460)
        )
        XCTAssertEqual(
            WorkoutCompletionConfettiOrigin.defaultOrigin(
                containerFrameInGlobalSpace: .zero,
                fallbackContainerSize: CGSize(width: 320, height: 568)
            ),
            CGPoint(x: 160, y: 284)
        )
        XCTAssertEqual(
            WorkoutCompletionConfettiOrigin.defaultOrigin(
                containerFrameInGlobalSpace: .zero,
                fallbackContainerSize: CGSize(width: 390, height: 0)
            ),
            CGPoint(x: 195, y: 360)
        )
    }

    func testReducedMotionUsesStaticPresentationWithoutParticles() {
        let reduced = WorkoutCompletionCelebrationPresentation.make(
            variant: .standard,
            reduceMotion: true
        )
        let pr = WorkoutCompletionCelebrationPresentation.make(
            variant: .personalRecord,
            reduceMotion: false
        )

        XCTAssertFalse(reduced.showsConfetti)
        XCTAssertEqual(reduced.initialHeroScale, 1)
        XCTAssertEqual(reduced.initialIconScale, 1)
        XCTAssertEqual(reduced.peakIconScale, 1)
        XCTAssertEqual(reduced.peakGlowOpacity, reduced.settledGlowOpacity)

        XCTAssertTrue(pr.showsConfetti)
        XCTAssertEqual(pr.initialHeroScale, 0.96)
        XCTAssertLessThan(pr.initialIconScale, 1)
        XCTAssertGreaterThan(pr.peakIconScale, 1)
        XCTAssertGreaterThan(pr.peakGlowOpacity, pr.settledGlowOpacity)
    }

Update every existing WorkoutCompletionConfettiPiece.random test call to pass variant: .standard after count:.

- [ ] **Step 2: Run RED**

Use XcodeBuildMCP session_show_defaults. If unset, configure /Users/hortlund/git/WGJ/WGJ.xcodeproj, scheme WGJ, and an available iPhone simulator. Call test_sim with:

    {
      "extraArgs": ["-only-testing:WGJTests/WorkoutCompletionConfettiTests"],
      "progress": true
    }

Expected: FAIL because the variant, presentation, new origin signature, palette, and descriptor property do not exist.

- [ ] **Step 3: Implement the deterministic policy**

At the top of WorkoutCompletionSummaryView.swift, add:

    nonisolated enum WorkoutCompletionCelebrationVariant: Equatable, Sendable {
        case standard
        case personalRecord

        static func make(hasPersonalRecords: Bool) -> Self {
            hasPersonalRecords ? .personalRecord : .standard
        }
    }

    nonisolated enum WorkoutCompletionConfettiColorRole: Equatable, Sendable {
        case blue, gold, success, cyan, purple, warning
    }

Replace defaultOrigin with:

    static func defaultOrigin(
        containerFrameInGlobalSpace frame: CGRect,
        fallbackContainerSize: CGSize
    ) -> CGPoint {
        if frame.width > 0, frame.height > 0 {
            return CGPoint(x: frame.midX, y: frame.midY)
        }

        let width = max(fallbackContainerSize.width, 0)
        if fallbackContainerSize.height > 0 {
            return CGPoint(x: width / 2, y: fallbackContainerSize.height / 2)
        }

        return CGPoint(x: width / 2, y: 360)
    }

Add variant to WorkoutCompletionConfettiBurstDescriptor:

    let variant: WorkoutCompletionCelebrationVariant

Add the presentation value type:

    nonisolated struct WorkoutCompletionCelebrationPresentation: Equatable, Sendable {
        let showsConfetti: Bool
        let initialHeroScale: CGFloat
        let initialIconScale: CGFloat
        let peakIconScale: CGFloat
        let peakGlowOpacity: Double
        let settledGlowOpacity: Double

        static func make(
            variant: WorkoutCompletionCelebrationVariant,
            reduceMotion: Bool
        ) -> Self {
            if reduceMotion {
                let glow = variant == .personalRecord ? 0.18 : 0.12
                return Self(
                    showsConfetti: false,
                    initialHeroScale: 1,
                    initialIconScale: 1,
                    peakIconScale: 1,
                    peakGlowOpacity: glow,
                    settledGlowOpacity: glow
                )
            }

            return Self(
                showsConfetti: true,
                initialHeroScale: 0.96,
                initialIconScale: variant == .personalRecord ? 0.74 : 0.84,
                peakIconScale: variant == .personalRecord ? 1.18 : 1.08,
                peakGlowOpacity: variant == .personalRecord ? 0.46 : 0.30,
                settledGlowOpacity: variant == .personalRecord ? 0.18 : 0.12
            )
        }
    }

Replace pieceCount and burstDescriptors with:

    static func pieceCount(
        for intensity: WorkoutCompletionConfettiIntensity,
        variant: WorkoutCompletionCelebrationVariant
    ) -> Int {
        switch intensity {
        case .completedWorkout:
            variant == .personalRecord ? 46 : 38
        case .manualTap:
            18
        }
    }

    static func burstDescriptors(
        origin: CGPoint,
        intensity: WorkoutCompletionConfettiIntensity,
        variant: WorkoutCompletionCelebrationVariant
    ) -> [WorkoutCompletionConfettiBurstDescriptor] {
        [
            WorkoutCompletionConfettiBurstDescriptor(
                origin: origin,
                role: .centralThrow,
                pieceCount: pieceCount(for: intensity, variant: variant),
                delay: 0,
                variant: variant
            ),
        ]
    }

    static func colorRoles(
        for variant: WorkoutCompletionCelebrationVariant
    ) -> [WorkoutCompletionConfettiColorRole] {
        switch variant {
        case .standard:
            [.blue, .gold, .success, .cyan, .purple, .warning]
        case .personalRecord:
            [.gold, .blue, .gold, .success, .gold, .cyan, .purple, .warning]
        }
    }

Preserve automaticCelebrationDelay, burstLifetime, spread, and motion-scale methods exactly.

Change WorkoutCompletionConfettiPiece.random to accept variant, replace its local colors array with:

    let colorRoles = WorkoutCompletionConfettiPolicy.colorRoles(for: variant)

Keep its complete size, spread, drift, delay, duration, and rotation calculations unchanged. Replace only the initializer's color argument:

    color: color(for: colorRoles[index % colorRoles.count])

Add:

    private static func color(for role: WorkoutCompletionConfettiColorRole) -> Color {
        switch role {
        case .blue: WGJTheme.accentBlue
        case .gold: WGJTheme.accentGold
        case .success: WGJTheme.success
        case .cyan: WGJTheme.accentCyan
        case .purple: WGJTheme.accentPurple
        case .warning: WGJTheme.warning
        }
    }

Pass descriptor.variant from WorkoutCompletionConfettiBurst.init into random. Do not alter Canvas or particle motion.

- [ ] **Step 4: Run GREEN**

Call test_sim with the Step 2 arguments.

Expected: PASS for every WorkoutCompletionConfettiTests case.

- [ ] **Step 5: Commit**

    git add WGJ/Views/Workout/WorkoutCompletionSummaryView.swift WGJTests/WorkoutCompletionConfettiTests.swift
    git commit -m "feat(workout): add centered PR celebration policy"

---

### Task 2: Wire One-Phase Hero Choreography

**Files:**
- Modify: WGJTests/WorkoutCompletionConfettiTests.swift
- Modify: WGJ/Views/Workout/WorkoutCompletionSummaryView.swift:91-331, 419-505

**Interfaces:**
- Consumes: Task 1 presentation values, variant-aware descriptors, automaticCelebrationTask, and WorkoutFeedbackCenter.
- Produces: WorkoutCompletionCelebrationPhase and one local celebrationPhase driving hero scale, icon scale, and glow.

- [ ] **Step 1: Write the failing phase-projection test**

Append:

    func testCelebrationPhaseProjectsOneHeroChoreography() {
        let presentation = WorkoutCompletionCelebrationPresentation.make(
            variant: .personalRecord,
            reduceMotion: false
        )

        XCTAssertEqual(WorkoutCompletionCelebrationPhase.prepared.heroScale(using: presentation), 0.96)
        XCTAssertEqual(WorkoutCompletionCelebrationPhase.peak.iconScale(using: presentation), 1.18)
        XCTAssertEqual(WorkoutCompletionCelebrationPhase.peak.glowOpacity(using: presentation), 0.46)
        XCTAssertEqual(WorkoutCompletionCelebrationPhase.settled.heroScale(using: presentation), 1)
        XCTAssertEqual(WorkoutCompletionCelebrationPhase.settled.iconScale(using: presentation), 1)
        XCTAssertEqual(WorkoutCompletionCelebrationPhase.settled.glowOpacity(using: presentation), 0.18)
    }

- [ ] **Step 2: Run RED**

Call test_sim for only WGJTests/WorkoutCompletionConfettiTests/testCelebrationPhaseProjectsOneHeroChoreography.

Expected: FAIL because WorkoutCompletionCelebrationPhase does not exist.

- [ ] **Step 3: Implement the phase projection**

Add beside WorkoutCompletionCelebrationPresentation:

    nonisolated enum WorkoutCompletionCelebrationPhase: Equatable, Sendable {
        case prepared
        case peak
        case settled

        func heroScale(using presentation: WorkoutCompletionCelebrationPresentation) -> CGFloat {
            self == .prepared ? presentation.initialHeroScale : 1
        }

        func iconScale(using presentation: WorkoutCompletionCelebrationPresentation) -> CGFloat {
            switch self {
            case .prepared: presentation.initialIconScale
            case .peak: presentation.peakIconScale
            case .settled: 1
            }
        }

        func glowOpacity(using presentation: WorkoutCompletionCelebrationPresentation) -> Double {
            switch self {
            case .prepared: 0
            case .peak: presentation.peakGlowOpacity
            case .settled: presentation.settledGlowOpacity
            }
        }
    }

- [ ] **Step 4: Run GREEN**

Repeat Step 2. Expected: PASS.

- [ ] **Step 5: Add one local phase and policy helpers**

Add state:

    @State private var celebrationPhase = WorkoutCompletionCelebrationPhase.prepared

Add helpers:

    private var celebrationVariant: WorkoutCompletionCelebrationVariant {
        .make(hasPersonalRecords: !(snapshot?.personalRecords.isEmpty ?? true))
    }

    private var celebrationPresentation: WorkoutCompletionCelebrationPresentation {
        .make(variant: celebrationVariant, reduceMotion: reduceMotion)
    }

Apply these three modifiers in heroCard:

    // Seal/trophy ZStack
    .scaleEffect(celebrationPhase.iconScale(using: celebrationPresentation))

    // Final hero-card RoundedRectangle overlay
    .overlay {
        RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
            .fill(
                LinearGradient(
                    colors: celebrationVariant == .personalRecord
                        ? [WGJTheme.accentGold.opacity(0.34), Color.clear]
                        : [WGJTheme.accentCyan.opacity(0.22), Color.clear],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            )
            .opacity(celebrationPhase.glowOpacity(using: celebrationPresentation))
    }

    // Complete hero Button
    .scaleEffect(celebrationPhase.heroScale(using: celebrationPresentation))

Do not animate the summary list or bottom action and do not add blur.

- [ ] **Step 6: Replace the automatic lifecycle with bounded choreography**

Replace scheduleAutomaticCelebrationIfReady with:

    private func scheduleAutomaticCelebrationIfReady() {
        guard snapshot != nil, !hasTriggeredCelebration else { return }
        hasTriggeredCelebration = true

        if reduceMotion {
            celebrationPhase = .settled
        }

        automaticCelebrationTask?.cancel()
        automaticCelebrationTask = Task { @MainActor in
            try? await Task.sleep(for: WorkoutCompletionConfettiPolicy.automaticCelebrationDelay)
            guard !Task.isCancelled, snapshot != nil else { return }

            if !reduceMotion {
                withAnimation(.spring(duration: 0.52, bounce: 0.30)) {
                    celebrationPhase = .peak
                }
            }

            triggerCelebration(
                origin: defaultConfettiOrigin(),
                intensity: .completedWorkout,
                variant: celebrationVariant
            )

            guard !reduceMotion else {
                automaticCelebrationTask = nil
                return
            }

            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.20)) {
                celebrationPhase = .settled
            }
            automaticCelebrationTask = nil
        }
    }

Add variant to triggerCelebration, keep the haptic before the guard, and use:

    guard celebrationPresentation.showsConfetti else { return }

    for descriptor in WorkoutCompletionConfettiPolicy.burstDescriptors(
        origin: origin,
        intensity: intensity,
        variant: variant ?? celebrationVariant
    ) {
        let burst = WorkoutCompletionConfettiBurst(descriptor: descriptor)
        confettiBursts.append(burst)
        confettiDismissTasks[burst.id]?.cancel()
        confettiDismissTasks[burst.id] = Task.detached(priority: .utility) {
            try? await Task.sleep(for: WorkoutCompletionConfettiPolicy.burstLifetime)
            guard !Task.isCancelled else { return }
            await self.removeConfettiBurstAfterDelayIfStillNeeded(id: burst.id)
        }
    }

Replace defaultConfettiOrigin with:

    private func defaultConfettiOrigin() -> CGPoint {
        WorkoutCompletionConfettiOrigin.defaultOrigin(
            containerFrameInGlobalSpace: completionContainerFrame,
            fallbackContainerSize: completionContainerFrame.size
        )
    }

Manual tap and accessibility replay continue calling triggerCelebration without variant; the loaded snapshot supplies it and policy holds count at 18. onDisappear continues cancelling the automatic and burst cleanup tasks.

- [ ] **Step 7: Run focused regression tests**

Call test_sim with:

    {
      "extraArgs": [
        "-only-testing:WGJTests/WorkoutCompletionConfettiTests",
        "-only-testing:WGJTests/ActiveWorkoutCoordinatorTests",
        "-only-testing:WGJTests/UserDataCloudBackupServiceTests"
      ],
      "progress": true
    }

Expected: PASS. Celebration, commit coordination, first-frame boundaries, and deferred backup remain green.

- [ ] **Step 8: Build and launch**

Call XcodeBuildMCP build_run_sim with empty arguments after confirming defaults.

Expected: build, install, and launch succeed without compiler errors or crash.

- [ ] **Step 9: Verify performance structure and interaction**

Run:

    rg -n 'TimelineView|Canvas|Task\.detached|WorkoutCompletionConfettiPiece\.random|celebrationPhase|withAnimation' WGJ/Views/Workout/WorkoutCompletionSummaryView.swift

Expected:
- TimelineView remains minimumInterval: 1.0 / 30.0.
- Pieces are generated only in the burst initializer.
- Cleanup remains one task per burst, never per piece.
- Hero work uses one celebrationPhase and the existing automatic task.
- Confetti retains allowsHitTesting(false), and View History has no disabled state.

On Simulator, complete one standard workout and one PR workout through the existing local flow. Confirm centered launch, stronger gold PR treatment, light tap replay, immediate View History interaction, and Reduced Motion behavior. If local data cannot produce both variants, record the unverified variant; do not add test-only routing or persistence.

- [ ] **Step 10: Commit**

    git add WGJ/Views/Workout/WorkoutCompletionSummaryView.swift WGJTests/WorkoutCompletionConfettiTests.swift
    git commit -m "feat(workout): add punchy completion choreography"

---

### Task 3: Final Regression and Scope Verification

**Files:**
- Verify: WGJ/Views/Workout/WorkoutCompletionSummaryView.swift
- Verify: WGJTests/WorkoutCompletionConfettiTests.swift
- Preserve: WGJ/WidgetShared/Localizable.xcstrings

**Interfaces:**
- Consumes: the two feature commits.
- Produces: final build/test evidence and proof that unrelated work remains untouched.

- [ ] **Step 1: Run the complete unit-test target**

Call XcodeBuildMCP test_sim with:

    {
      "extraArgs": ["-only-testing:WGJTests"],
      "progress": true
    }

Expected: PASS for WGJTests.

- [ ] **Step 2: Run a clean final simulator build**

Call XcodeBuildMCP build_sim with empty arguments.

Expected: build succeeds.

- [ ] **Step 3: Check diff scope and formatting**

    git diff --check HEAD~2..HEAD
    git diff --stat HEAD~2..HEAD
    git status --short

Expected: no whitespace errors; feature commits contain only the completion view and confetti tests; WGJ/WidgetShared/Localizable.xcstrings remains a separate pre-existing unstaged modification.
