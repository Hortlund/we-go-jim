import Testing
@testable import WGJ

@MainActor
struct AppNotificationRouterTests {
    @Test
    func requestBrosRefreshDoesNotChangeRequestedTab() {
        let router = AppNotificationRouter.makeTestingInstance()

        router.requestBrosRefresh()

        #expect(router.requestedTab == nil)
        #expect(router.routeRequestID == nil)
        #expect(router.brosRefreshRequestID != nil)
    }

    @Test
    func openBrosKeepsRefreshRequestPendingAfterTabConsumption() {
        let router = AppNotificationRouter.makeTestingInstance()

        router.openBros()
        let refreshRequestID = router.brosRefreshRequestID

        router.consumeRequestedTab()

        #expect(router.requestedTab == nil)
        #expect(router.routeRequestID != nil)
        #expect(router.brosRefreshRequestID == refreshRequestID)
    }

    @Test
    func consumeBrosRefreshRequestClearsOnlyRefreshRequest() {
        let router = AppNotificationRouter.makeTestingInstance()

        router.openBros()

        #expect(router.requestedTab == AppMainTab.bros)
        #expect(router.brosRefreshRequestID != nil)

        router.consumeBrosRefreshRequest()

        #expect(router.requestedTab == AppMainTab.bros)
        #expect(router.brosRefreshRequestID == nil)
    }
}
