import Foundation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

nonisolated final class AppleCoachNarrativeService {
    struct RecapGenerationInput: Equatable, Sendable {
        let snapshot: WeeklyCoachInsightSnapshot
    }

    struct FollowUpGenerationInput: Equatable, Sendable {
        let kind: CoachFollowUpKind
        let snapshot: WeeklyCoachInsightSnapshot
    }

    typealias RecapGenerator = @Sendable (RecapGenerationInput) throws -> CoachNarrativeSummary?
    typealias FollowUpGenerator = @Sendable (FollowUpGenerationInput) throws -> CoachNarrativeSummary?

    private let cacheRepository: CoachNarrativeCacheRepository
    private let availabilityProvider: @Sendable () -> Bool
    private let recapGenerator: RecapGenerator
    private let followUpGenerator: FollowUpGenerator

    init(
        modelContext: ModelContext,
        availabilityProvider: (@Sendable () -> Bool)? = nil,
        recapGenerator: RecapGenerator? = nil,
        followUpGenerator: FollowUpGenerator? = nil
    ) {
        self.cacheRepository = CoachNarrativeCacheRepository(modelContext: modelContext)
        self.availabilityProvider = availabilityProvider ?? AppleCoachNarrativeService.foundationModelsAvailable
        self.recapGenerator = recapGenerator ?? AppleCoachNarrativeService.defaultRecapGenerator
        self.followUpGenerator = followUpGenerator ?? AppleCoachNarrativeService.defaultFollowUpGenerator
    }

    func recapSummary(for snapshot: WeeklyCoachInsightSnapshot) throws -> CoachNarrativeSummary {
        if let cached = try cacheRepository.recap(
            forWeekStart: snapshot.weekStart,
            revisionKey: snapshot.revisionKey
        ) {
            return cached
        }

        if let generated = try generatedRecap(for: snapshot) {
            try cacheRepository.saveRecap(
                generated,
                weekStart: snapshot.weekStart,
                revisionKey: snapshot.revisionKey
            )
            return generated
        }

        let fallback = fallbackRecap(for: snapshot)
        try cacheRepository.saveRecap(
            fallback,
            weekStart: snapshot.weekStart,
            revisionKey: snapshot.revisionKey
        )
        return fallback
    }

    func followUpSummary(
        for kind: CoachFollowUpKind,
        snapshot: WeeklyCoachInsightSnapshot
    ) throws -> CoachNarrativeSummary {
        if let cached = try cacheRepository.followUp(
            kind: kind,
            weekStart: snapshot.weekStart,
            revisionKey: snapshot.revisionKey
        ) {
            return cached
        }

        if let generated = try generatedFollowUp(for: kind, snapshot: snapshot) {
            try cacheRepository.saveFollowUp(
                generated,
                kind: kind,
                weekStart: snapshot.weekStart,
                revisionKey: snapshot.revisionKey
            )
            return generated
        }

        let fallback = fallbackFollowUp(for: kind, snapshot: snapshot)
        try cacheRepository.saveFollowUp(
            fallback,
            kind: kind,
            weekStart: snapshot.weekStart,
            revisionKey: snapshot.revisionKey
        )
        return fallback
    }

    private func generatedRecap(
        for snapshot: WeeklyCoachInsightSnapshot
    ) throws -> CoachNarrativeSummary? {
        guard availabilityProvider() else {
            return nil
        }

        guard let summary = try recapGenerator(RecapGenerationInput(snapshot: snapshot)) else {
            return nil
        }

        return normalized(summary, fallback: fallbackRecap(for: snapshot))
    }

    private func generatedFollowUp(
        for kind: CoachFollowUpKind,
        snapshot: WeeklyCoachInsightSnapshot
    ) throws -> CoachNarrativeSummary? {
        guard availabilityProvider() else {
            return nil
        }

        guard let summary = try followUpGenerator(
            FollowUpGenerationInput(kind: kind, snapshot: snapshot)
        ) else {
            return nil
        }

        return normalized(
            summary,
            fallback: fallbackFollowUp(for: kind, snapshot: snapshot)
        )
    }

    private func normalized(
        _ summary: CoachNarrativeSummary,
        fallback: CoachNarrativeSummary
    ) -> CoachNarrativeSummary {
        let trimmedBody = summary.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            return fallback
        }

        return CoachNarrativeSummary(
            body: trimmedBody,
            availabilityMode: summary.availabilityMode
        )
    }

    private func fallbackRecap(for snapshot: WeeklyCoachInsightSnapshot) -> CoachNarrativeSummary {
        if !snapshot.fallbackSummary.isEmpty {
            return CoachNarrativeSummary(
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
            body: body,
            availabilityMode: .fallback
        )
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

    private static func defaultRecapGenerator(
        _ input: RecapGenerationInput
    ) throws -> CoachNarrativeSummary? {
        try generateWithFoundationModels(
            prompt: recapPrompt(for: input.snapshot)
        )
    }

    private static func defaultFollowUpGenerator(
        _ input: FollowUpGenerationInput
    ) throws -> CoachNarrativeSummary? {
        try generateWithFoundationModels(
            prompt: followUpPrompt(for: input.kind, snapshot: input.snapshot)
        )
    }

    private static func recapPrompt(for snapshot: WeeklyCoachInsightSnapshot) -> String {
        """
        Write a short weekly training recap.
        Completed workouts: \(snapshot.completedWorkoutCount)
        Volume delta: \(snapshot.totalVolumeDelta)
        Consistency delta: \(snapshot.consistencyDelta)
        Rising signals: \(snapshot.topRisingSignals.map(\.summary).joined(separator: " | "))
        Watch signals: \(snapshot.topWatchSignals.map(\.summary).joined(separator: " | "))
        Fallback summary: \(snapshot.fallbackSummary)
        """
    }

    private static func followUpPrompt(
        for kind: CoachFollowUpKind,
        snapshot: WeeklyCoachInsightSnapshot
    ) -> String {
        """
        Write a short weekly follow-up about \(kind.rawValue).
        Completed workouts: \(snapshot.completedWorkoutCount)
        Volume delta: \(snapshot.totalVolumeDelta)
        Consistency delta: \(snapshot.consistencyDelta)
        Rising signals: \(snapshot.topRisingSignals.map(\.summary).joined(separator: " | "))
        Watch signals: \(snapshot.topWatchSignals.map(\.summary).joined(separator: " | "))
        Fallback summary: \(snapshot.fallbackSummary)
        """
    }

    private static func foundationModelsAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif

        return false
    }

    private static func generateWithFoundationModels(
        prompt: String
    ) throws -> CoachNarrativeSummary? {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return nil
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else {
                return nil
            }

            // Real prompting stays additive and can be expanded later without changing cache/fallback behavior.
            return nil
        }
        #endif

        return nil
    }
}
