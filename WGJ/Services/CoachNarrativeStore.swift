import Foundation
import SwiftData

nonisolated protocol CoachNarrativeCaching: Sendable {
    func recap(weekStart: Date, revisionKey: String) async throws -> CoachNarrativeSummary?
    func needsRecapRefresh(
        weekStart: Date,
        revisionKey: String,
        now: Date,
        maxAge: TimeInterval
    ) async throws -> Bool
    func saveRecap(
        _ summary: CoachNarrativeSummary,
        weekStart: Date,
        revisionKey: String
    ) async throws
    func followUp(
        kind: CoachFollowUpKind,
        weekStart: Date,
        revisionKey: String
    ) async throws -> CoachNarrativeSummary?
    func saveFollowUp(
        _ summary: CoachNarrativeSummary,
        kind: CoachFollowUpKind,
        weekStart: Date,
        revisionKey: String
    ) async throws
}

@ModelActor
actor CoachNarrativeStore: CoachNarrativeCaching {
    func recap(weekStart: Date, revisionKey: String) throws -> CoachNarrativeSummary? {
        try CoachNarrativeCacheRepository(modelContext: modelContext)
            .recap(forWeekStart: weekStart, revisionKey: revisionKey)
    }

    func needsRecapRefresh(
        weekStart: Date,
        revisionKey: String,
        now: Date,
        maxAge: TimeInterval
    ) throws -> Bool {
        try CoachNarrativeCacheRepository(modelContext: modelContext).needsRecapRefresh(
            weekStart: weekStart,
            revisionKey: revisionKey,
            now: now,
            maxAge: maxAge
        )
    }

    func saveRecap(
        _ summary: CoachNarrativeSummary,
        weekStart: Date,
        revisionKey: String
    ) throws {
        try CoachNarrativeCacheRepository(modelContext: modelContext).saveRecap(
            summary,
            weekStart: weekStart,
            revisionKey: revisionKey
        )
    }

    func followUp(
        kind: CoachFollowUpKind,
        weekStart: Date,
        revisionKey: String
    ) throws -> CoachNarrativeSummary? {
        try CoachNarrativeCacheRepository(modelContext: modelContext).followUp(
            kind: kind,
            weekStart: weekStart,
            revisionKey: revisionKey
        )
    }

    func saveFollowUp(
        _ summary: CoachNarrativeSummary,
        kind: CoachFollowUpKind,
        weekStart: Date,
        revisionKey: String
    ) throws {
        try CoachNarrativeCacheRepository(modelContext: modelContext).saveFollowUp(
            summary,
            kind: kind,
            weekStart: weekStart,
            revisionKey: revisionKey
        )
    }
}
