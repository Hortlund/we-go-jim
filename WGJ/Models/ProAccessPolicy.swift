import Foundation

nonisolated enum ProAccessPolicy {
    static let freeTemplateLimit = 4
    static let freeBrosMemberLimit = 2

    static func canCreateTemplate(currentTemplateCount: Int, isPro: Bool) -> Bool {
        isPro || currentTemplateCount < freeTemplateLimit
    }

    static func canImportTemplates(currentTemplateCount: Int, importingCount: Int, isPro: Bool) -> Bool {
        isPro || currentTemplateCount + importingCount <= freeTemplateLimit
    }

    static func canUseExistingTemplate(isPro: Bool) -> Bool {
        true
    }

    static func canExportTemplates(isPro: Bool) -> Bool {
        isPro
    }

    static func requiresPro(_ widgetKind: ProfileWidgetKind) -> Bool {
        switch widgetKind {
        case .prs, .weeklyGoals:
            false
        case .weeklyMuscleHeatmap,
             .coachBrief,
             .exerciseOneRMTrend,
             .exerciseVolumeTrend,
             .streaks,
             .topExercises,
             .consistencyCalendar:
            true
        }
    }

    static func canShowMuscleMap(isPro: Bool) -> Bool {
        isPro
    }

    static func maximumBrosMemberLimit(isPro: Bool) -> Int {
        isPro ? BrosSocialRules.maxMemberLimit : freeBrosMemberLimit
    }

    static func canUseBrosCircle(memberCount: Int, memberLimit: Int, isPro: Bool) -> Bool {
        isPro || (memberCount <= freeBrosMemberLimit && memberLimit <= freeBrosMemberLimit)
    }

    static func canSetBrosMemberLimit(_ memberLimit: Int, currentMemberCount: Int, isPro: Bool) -> Bool {
        guard BrosSocialRules.canSetMemberLimit(memberLimit, currentMemberCount: currentMemberCount) else {
            return false
        }

        return isPro || memberLimit <= freeBrosMemberLimit
    }
}
