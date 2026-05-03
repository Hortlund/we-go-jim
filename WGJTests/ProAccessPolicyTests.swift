import Testing
@testable import WGJ

struct ProAccessPolicyTests {
    @Test
    func freeTemplateCreationAllowsOnlyFirstFourTemplates() {
        #expect(ProAccessPolicy.canCreateTemplate(currentTemplateCount: 3, isPro: false))
        #expect(!ProAccessPolicy.canCreateTemplate(currentTemplateCount: 4, isPro: false))
        #expect(ProAccessPolicy.canCreateTemplate(currentTemplateCount: 40, isPro: true))
    }

    @Test
    func freeTemplateImportsMustFitWithinFourTemplateCap() {
        #expect(ProAccessPolicy.canImportTemplates(currentTemplateCount: 2, importingCount: 2, isPro: false))
        #expect(!ProAccessPolicy.canImportTemplates(currentTemplateCount: 3, importingCount: 2, isPro: false))
        #expect(ProAccessPolicy.canImportTemplates(currentTemplateCount: 10, importingCount: 10, isPro: true))
    }

    @Test
    func existingTemplatesStayUsableEvenAboveFreeCap() {
        #expect(ProAccessPolicy.canUseExistingTemplate(isPro: false))
        #expect(ProAccessPolicy.canUseExistingTemplate(isPro: true))
    }

    @Test
    func templateExportRequiresPro() {
        #expect(!ProAccessPolicy.canExportTemplates(isPro: false))
        #expect(ProAccessPolicy.canExportTemplates(isPro: true))
    }

    @Test
    func muscleMapRequiresPro() {
        #expect(!ProAccessPolicy.canShowMuscleMap(isPro: false))
        #expect(ProAccessPolicy.canShowMuscleMap(isPro: true))
    }

    @Test
    func freeBrosMemberLimitIsTwoAndProUsesSocialRuleMaximum() {
        #expect(ProAccessPolicy.maximumBrosMemberLimit(isPro: false) == 2)
        #expect(ProAccessPolicy.maximumBrosMemberLimit(isPro: true) == BrosSocialRules.maxMemberLimit)
        #expect(ProAccessPolicy.canUseBrosCircle(memberCount: 2, memberLimit: 2, isPro: false))
        #expect(!ProAccessPolicy.canUseBrosCircle(memberCount: 3, memberLimit: 3, isPro: false))
        #expect(ProAccessPolicy.canUseBrosCircle(memberCount: 3, memberLimit: 3, isPro: true))
    }

    @Test
    func freeUsersCannotSetBrosMemberLimitAboveTwo() {
        #expect(ProAccessPolicy.canSetBrosMemberLimit(2, currentMemberCount: 2, isPro: false))
        #expect(!ProAccessPolicy.canSetBrosMemberLimit(3, currentMemberCount: 2, isPro: false))
        #expect(!ProAccessPolicy.canSetBrosMemberLimit(2, currentMemberCount: 3, isPro: false))
        #expect(ProAccessPolicy.canSetBrosMemberLimit(3, currentMemberCount: 2, isPro: true))
        #expect(!ProAccessPolicy.canSetBrosMemberLimit(1, currentMemberCount: 1, isPro: true))
    }

    @Test
    func advancedProfileWidgetsRequirePro() {
        #expect(!ProAccessPolicy.requiresPro(.prs))
        #expect(!ProAccessPolicy.requiresPro(.weeklyGoals))
        #expect(ProAccessPolicy.requiresPro(.weeklyMuscleHeatmap))
        #expect(ProAccessPolicy.requiresPro(.coachBrief))
        #expect(ProAccessPolicy.requiresPro(.exerciseOneRMTrend))
        #expect(ProAccessPolicy.requiresPro(.exerciseVolumeTrend))
        #expect(ProAccessPolicy.requiresPro(.streaks))
        #expect(ProAccessPolicy.requiresPro(.topExercises))
        #expect(ProAccessPolicy.requiresPro(.consistencyCalendar))
    }
}
