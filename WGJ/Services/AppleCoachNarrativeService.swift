import Foundation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class AppleCoachNarrativeService {
    nonisolated static let recapRefreshMaxAge: TimeInterval = 60 * 60

    nonisolated struct RecapGenerationInput: Equatable, Sendable {
        let snapshot: WeeklyCoachInsightSnapshot
    }

    nonisolated struct FollowUpGenerationInput: Equatable, Sendable {
        let kind: CoachFollowUpKind
        let snapshot: WeeklyCoachInsightSnapshot
    }

    typealias RecapGenerator = @Sendable (RecapGenerationInput) async throws -> CoachNarrativeSummary?
    typealias FollowUpGenerator = @Sendable (FollowUpGenerationInput) async throws -> CoachNarrativeSummary?

    private let cacheRepository: CoachNarrativeCacheRepository
    private let availabilityProvider: @Sendable () -> Bool
    private let recapGenerator: RecapGenerator
    private let followUpGenerator: FollowUpGenerator
    private var inFlightRequests: [String: Task<CoachNarrativeSummary, Error>] = [:]
    private var inFlightWaiters: [String: Set<UUID>] = [:]

    init(
        cacheRepository: CoachNarrativeCacheRepository,
        availabilityProvider: (@Sendable () -> Bool)? = nil,
        recapGenerator: RecapGenerator? = nil,
        followUpGenerator: FollowUpGenerator? = nil
    ) {
        self.cacheRepository = cacheRepository
        self.availabilityProvider = availabilityProvider ?? AppleCoachNarrativeService.foundationModelsAvailable
        self.recapGenerator = recapGenerator ?? AppleCoachNarrativeService.defaultRecapGenerator
        self.followUpGenerator = followUpGenerator ?? AppleCoachNarrativeService.defaultFollowUpGenerator
    }

    convenience init(
        modelContext: ModelContext,
        availabilityProvider: (@Sendable () -> Bool)? = nil,
        recapGenerator: RecapGenerator? = nil,
        followUpGenerator: FollowUpGenerator? = nil
    ) {
        self.init(
            cacheRepository: CoachNarrativeCacheRepository(modelContext: modelContext),
            availabilityProvider: availabilityProvider,
            recapGenerator: recapGenerator,
            followUpGenerator: followUpGenerator
        )
    }

    func recap(for snapshot: WeeklyCoachInsightSnapshot) async throws -> CoachNarrativeSummary {
        try await resolveRecap(for: snapshot, forceRefresh: false)
    }

    func recapForDisplay(
        for snapshot: WeeklyCoachInsightSnapshot,
        now: Date = .now,
        maxAge: TimeInterval = AppleCoachNarrativeService.recapRefreshMaxAge
    ) async throws -> CoachNarrativeSummary {
        let cached = try cacheRepository.recap(
            forWeekStart: snapshot.weekStart,
            revisionKey: snapshot.revisionKey
        )
        let shouldRefresh = try cacheRepository.needsRecapRefresh(
            weekStart: snapshot.weekStart,
            revisionKey: snapshot.revisionKey,
            now: now,
            maxAge: maxAge
        )

        if shouldRefresh, let cached {
            scheduleRecapRefresh(for: snapshot)
            return cached
        }

        return try await resolveRecap(for: snapshot, forceRefresh: shouldRefresh)
    }

    func refreshRecapIfNeeded(
        for snapshot: WeeklyCoachInsightSnapshot,
        now: Date = .now,
        maxAge: TimeInterval = AppleCoachNarrativeService.recapRefreshMaxAge
    ) async throws -> CoachNarrativeSummary {
        let shouldRefresh = try cacheRepository.needsRecapRefresh(
            weekStart: snapshot.weekStart,
            revisionKey: snapshot.revisionKey,
            now: now,
            maxAge: maxAge
        )
        return try await resolveRecap(for: snapshot, forceRefresh: shouldRefresh)
    }

    private func scheduleRecapRefresh(for snapshot: WeeklyCoachInsightSnapshot) {
        let cacheKey = CachedCoachNarrative.makeCacheKey(
            weekStart: snapshot.weekStart,
            revisionKey: snapshot.revisionKey
        )
        guard inFlightRequests[cacheKey] == nil else { return }

        Task { @MainActor in
            _ = try? await resolveRecap(for: snapshot, forceRefresh: true)
        }
    }

    private func resolveRecap(
        for snapshot: WeeklyCoachInsightSnapshot,
        forceRefresh: Bool
    ) async throws -> CoachNarrativeSummary {
        let cacheKey = CachedCoachNarrative.makeCacheKey(
            weekStart: snapshot.weekStart,
            revisionKey: snapshot.revisionKey
        )
        let fallbackSummary = fallbackRecap(for: snapshot)
        let availabilityProvider = self.availabilityProvider
        let cached = try cacheRepository.recap(
            forWeekStart: snapshot.weekStart,
            revisionKey: snapshot.revisionKey
        )
        if !forceRefresh, let cached, cached.availabilityMode != .fallback {
            return cached
        }

        return try await resolveSummary(
            cacheKey: cacheKey,
            cachedFallback: cached,
            fallback: fallbackSummary,
            generate: { [recapGenerator, availabilityProvider] in
                try await Self.generatedSummary(
                    using: recapGenerator,
                    input: RecapGenerationInput(snapshot: snapshot),
                    isAvailable: availabilityProvider,
                    fallback: fallbackSummary
                )
            },
            persist: { [cacheRepository] summary in
                try cacheRepository.saveRecap(
                    summary,
                    weekStart: snapshot.weekStart,
                    revisionKey: snapshot.revisionKey
                )
            }
        )
    }

    func followUp(
        for kind: CoachFollowUpKind,
        snapshot: WeeklyCoachInsightSnapshot
    ) async throws -> CoachNarrativeSummary {
        let cacheKey = CachedCoachFollowUpNarrative.makeCacheKey(
            weekStart: snapshot.weekStart,
            revisionKey: snapshot.revisionKey,
            followUpKind: kind
        )
        let fallbackSummary = fallbackFollowUp(for: kind, snapshot: snapshot)
        let availabilityProvider = self.availabilityProvider
        let cached = try cacheRepository.followUp(
            kind: kind,
            weekStart: snapshot.weekStart,
            revisionKey: snapshot.revisionKey
        )
        if let cached, cached.availabilityMode != .fallback {
            return cached
        }

        return try await resolveSummary(
            cacheKey: cacheKey,
            cachedFallback: cached,
            fallback: fallbackSummary,
            generate: { [followUpGenerator, availabilityProvider] in
                try await Self.generatedSummary(
                    using: followUpGenerator,
                    input: FollowUpGenerationInput(kind: kind, snapshot: snapshot),
                    isAvailable: availabilityProvider,
                    fallback: fallbackSummary
                )
            },
            persist: { [cacheRepository] summary in
                try cacheRepository.saveFollowUp(
                    summary,
                    kind: kind,
                    weekStart: snapshot.weekStart,
                    revisionKey: snapshot.revisionKey
                )
            }
        )
    }

    private func resolveSummary(
        cacheKey: String,
        cachedFallback: CoachNarrativeSummary?,
        fallback: @autoclosure @escaping () -> CoachNarrativeSummary,
        generate: @escaping @Sendable () async throws -> CoachNarrativeSummary?,
        persist: @escaping @Sendable (CoachNarrativeSummary) throws -> Void
    ) async throws -> CoachNarrativeSummary {
        if let task = inFlightRequests[cacheKey] {
            return try await awaitSharedTask(task, cacheKey: cacheKey)
        }

        guard availabilityProvider() else {
            if let cachedFallback {
                return cachedFallback
            }

            let fallbackSummary = fallback()
            try persist(fallbackSummary)
            return fallbackSummary
        }

        let task = Task<CoachNarrativeSummary, Error> { @MainActor in
            defer {
                inFlightRequests[cacheKey] = nil
                inFlightWaiters[cacheKey] = nil
            }

            do {
                if let generated = try await generate() {
                    try persist(generated)
                    return generated
                }
            } catch let cancellation as CancellationError {
                throw cancellation
            }

            if let cachedFallback {
                return cachedFallback
            }

            let fallbackSummary = fallback()
            try persist(fallbackSummary)
            return fallbackSummary
        }
        inFlightRequests[cacheKey] = task
        return try await awaitSharedTask(task, cacheKey: cacheKey)
    }

    private func awaitSharedTask(
        _ task: Task<CoachNarrativeSummary, Error>,
        cacheKey: String
    ) async throws -> CoachNarrativeSummary {
        let waiterID = UUID()
        inFlightWaiters[cacheKey, default: []].insert(waiterID)

        return try await withTaskCancellationHandler {
            defer {
                releaseWaiter(
                    waiterID,
                    for: cacheKey,
                    cancelTaskIfUnobserved: false
                )
            }
            return try await task.value
        } onCancel: { [cacheKey] in
            Task { @MainActor in
                releaseWaiter(
                    waiterID,
                    for: cacheKey,
                    cancelTaskIfUnobserved: true
                )
            }
        }
    }

    private func releaseWaiter(
        _ waiterID: UUID,
        for cacheKey: String,
        cancelTaskIfUnobserved: Bool
    ) {
        guard var waiters = inFlightWaiters[cacheKey] else {
            return
        }

        let removed = waiters.remove(waiterID) != nil
        if waiters.isEmpty {
            inFlightWaiters[cacheKey] = nil
            if removed, cancelTaskIfUnobserved {
                inFlightRequests[cacheKey]?.cancel()
            }
            return
        }

        inFlightWaiters[cacheKey] = waiters
    }

    private static nonisolated func generatedSummary<Input>(
        using generator: @escaping @Sendable (Input) async throws -> CoachNarrativeSummary?,
        input: Input,
        isAvailable: @escaping @Sendable () -> Bool,
        fallback: CoachNarrativeSummary
    ) async throws -> CoachNarrativeSummary? {
        guard isAvailable() else {
            return nil
        }

        let summary: CoachNarrativeSummary?
        do {
            summary = try await generator(input)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            return nil
        }

        guard let summary else {
            return nil
        }

        return normalized(summary, fallback: fallback)
    }

    private static nonisolated func normalized(
        _ summary: CoachNarrativeSummary,
        fallback: CoachNarrativeSummary
    ) -> CoachNarrativeSummary {
        let trimmedHeadline = summary.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = summary.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHeadline.isEmpty, !trimmedBody.isEmpty else {
            return fallback
        }

        return CoachNarrativeSummary(
            headline: trimmedHeadline,
            body: trimmedBody,
            availabilityMode: summary.availabilityMode
        )
    }

    private func fallbackRecap(for snapshot: WeeklyCoachInsightSnapshot) -> CoachNarrativeSummary {
        if !snapshot.fallbackSummary.isEmpty {
            return CoachNarrativeSummary(
                headline: "Weekly Coach Recap",
                body: snapshot.fallbackSummary,
                availabilityMode: .fallback
            )
        }

        var parts: [String] = [
            workoutCountSentence(snapshot.completedWorkoutCount)
        ]

        if let risingSignal = snapshot.topRisingSignals.first {
            parts.append(risingSignal.summary)
        }

        if let watchSignal = snapshot.topWatchSignals.first {
            parts.append(watchSignal.summary)
        } else {
            parts.append(volumeSentence(snapshot.totalVolumeDelta))
        }

        return CoachNarrativeSummary(
            headline: recapHeadline(for: snapshot),
            body: parts.joined(separator: " "),
            availabilityMode: .fallback
        )
    }

    private func fallbackFollowUp(
        for kind: CoachFollowUpKind,
        snapshot: WeeklyCoachInsightSnapshot
    ) -> CoachNarrativeSummary {
        let body: String

        switch kind {
        case .whatImproved:
            if let signal = snapshot.topRisingSignals.first {
                body = signal.summary
            } else if snapshot.totalVolumeDelta > 0 {
                body = "Total training volume is up \(formattedPercent(snapshot.totalVolumeDelta))% vs your recent baseline."
            } else if snapshot.consistencyDelta > 0 {
                body = consistencySentence(snapshot.consistencyDelta, positive: true)
            } else if !snapshot.fallbackSummary.isEmpty {
                body = snapshot.fallbackSummary
            } else {
                body = "This week stayed steady without a standout improvement signal yet."
            }

        case .whatChanged:
            if !snapshot.fallbackSummary.isEmpty {
                body = snapshot.fallbackSummary
            } else if let signal = snapshot.topRisingSignals.first {
                body = "\(workoutCountSentence(snapshot.completedWorkoutCount)) \(signal.summary)"
            } else if let signal = snapshot.topWatchSignals.first {
                body = "\(workoutCountSentence(snapshot.completedWorkoutCount)) \(signal.summary)"
            } else {
                body = "\(workoutCountSentence(snapshot.completedWorkoutCount)) \(volumeSentence(snapshot.totalVolumeDelta))"
            }

        case .whyFlat:
            if let signal = snapshot.topWatchSignals.first {
                body = signal.summary
            } else if snapshot.totalVolumeDelta < 0 {
                body = "Total training volume is down \(formattedPercent(abs(snapshot.totalVolumeDelta)))% vs your recent baseline."
            } else if snapshot.consistencyDelta < 0 {
                body = consistencySentence(abs(snapshot.consistencyDelta), positive: false)
            } else if !snapshot.fallbackSummary.isEmpty {
                body = snapshot.fallbackSummary
            } else {
                body = "There is not a clear drop-off signal in this snapshot yet."
            }
        }

        return CoachNarrativeSummary(
            headline: followUpHeadline(for: kind, snapshot: snapshot),
            body: body,
            availabilityMode: .fallback
        )
    }

    private func recapHeadline(for snapshot: WeeklyCoachInsightSnapshot) -> String {
        if !snapshot.fallbackSummary.isEmpty {
            return "Weekly Coach Recap"
        }
        if let risingSignal = snapshot.topRisingSignals.first {
            return "\(risingSignal.exerciseName) Led The Week"
        }
        if let watchSignal = snapshot.topWatchSignals.first {
            return "\(watchSignal.exerciseName) Needs Attention"
        }
        if snapshot.totalVolumeDelta > 0 {
            return "Volume Moved Up"
        }
        if snapshot.totalVolumeDelta < 0 {
            return "Volume Moved Down"
        }
        return "Weekly Coach Recap"
    }

    private func followUpHeadline(
        for kind: CoachFollowUpKind,
        snapshot: WeeklyCoachInsightSnapshot
    ) -> String {
        switch kind {
        case .whatImproved:
            return snapshot.topRisingSignals.first.map { "\($0.exerciseName) Improved" } ?? "What Improved"
        case .whatChanged:
            return "What Changed"
        case .whyFlat:
            return snapshot.topWatchSignals.first.map { "\($0.exerciseName) To Watch" } ?? "Why It Felt Flat"
        }
    }

    private func workoutCountSentence(_ count: Int) -> String {
        if count == 1 {
            return "You logged 1 workout this week."
        }
        return "You logged \(count) workouts this week."
    }

    private func consistencySentence(_ delta: Int, positive: Bool) -> String {
        let sessionWord = delta == 1 ? "session" : "sessions"
        if positive {
            return "You trained \(delta) more \(sessionWord) than your recent baseline."
        }
        return "You trained \(delta) fewer \(sessionWord) than your recent baseline."
    }

    private func volumeSentence(_ delta: Double) -> String {
        if delta > 0 {
            return "Total training volume is up \(formattedPercent(delta))% vs your recent baseline."
        }
        if delta < 0 {
            return "Total training volume is down \(formattedPercent(abs(delta)))% vs your recent baseline."
        }
        return "Total training volume matched your recent baseline."
    }

    private func formattedPercent(_ value: Double) -> String {
        WGJFormatters.oneDecimalString(value)
    }

    private static nonisolated func defaultRecapGenerator(
        _ input: RecapGenerationInput
    ) async throws -> CoachNarrativeSummary? {
        try await generateWithFoundationModels(
            instructions: "You are WGJ's coach. Return a short headline and a concise body grounded only in the supplied weekly training snapshot.",
            prompt: recapPrompt(for: input.snapshot)
        )
    }

    private static nonisolated func defaultFollowUpGenerator(
        _ input: FollowUpGenerationInput
    ) async throws -> CoachNarrativeSummary? {
        try await generateWithFoundationModels(
            instructions: "You are WGJ's coach. Return a short headline and a concise body grounded only in the supplied weekly training snapshot and requested follow-up angle.",
            prompt: followUpPrompt(for: input.kind, snapshot: input.snapshot)
        )
    }

    private static nonisolated func recapPrompt(for snapshot: WeeklyCoachInsightSnapshot) -> String {
        """
        recap
        workouts=\(snapshot.completedWorkoutCount)
        volumeDelta=\(WGJFormatters.oneDecimalString(snapshot.totalVolumeDelta))
        consistencyDelta=\(snapshot.consistencyDelta)
        rising=\(snapshot.topRisingSignals.map(\.summary).joined(separator: " | "))
        watch=\(snapshot.topWatchSignals.map(\.summary).joined(separator: " | "))
        fallback=\(snapshot.fallbackSummary)
        """
    }

    private static nonisolated func followUpPrompt(
        for kind: CoachFollowUpKind,
        snapshot: WeeklyCoachInsightSnapshot
    ) -> String {
        """
        followUp=\(kind.rawValue)
        workouts=\(snapshot.completedWorkoutCount)
        volumeDelta=\(WGJFormatters.oneDecimalString(snapshot.totalVolumeDelta))
        consistencyDelta=\(snapshot.consistencyDelta)
        rising=\(snapshot.topRisingSignals.map(\.summary).joined(separator: " | "))
        watch=\(snapshot.topWatchSignals.map(\.summary).joined(separator: " | "))
        fallback=\(snapshot.fallbackSummary)
        """
    }

    private static nonisolated func foundationModelsAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return foundationModelsAvailability()
        }
        #endif

        return false
    }

    private static nonisolated func generateWithFoundationModels(
        instructions: String,
        prompt: String
    ) async throws -> CoachNarrativeSummary? {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return nil
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            guard foundationModelsAvailability() else {
                return nil
            }

            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: trimmedPrompt,
                generating: GeneratedCoachNarrative.self
            )

            return CoachNarrativeSummary(
                headline: response.content.headline,
                body: response.content.body,
                availabilityMode: .generated
            )
        }
        #endif

        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private static nonisolated func foundationModelsAvailability() -> Bool {
        let model = SystemLanguageModel.default
        return model.availability == .available && model.isAvailable
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    @Generable
    struct GeneratedCoachNarrative {
        let headline: String
        let body: String
    }
    #endif
}
