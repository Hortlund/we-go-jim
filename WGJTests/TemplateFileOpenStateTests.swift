import Foundation
import Testing
@testable import WGJ

@MainActor
struct TemplateFileOpenStateTests {
    @Test
    func enqueueIfSupportedQueuesTemplateFilesAndReplacesOlderRequest() {
        let state = TemplateFileOpenState()
        let firstURL = URL(fileURLWithPath: "/tmp/first.\(TemplateTransferFileFormat.filenameExtension)")
        let secondURL = URL(fileURLWithPath: "/tmp/second.\(TemplateTransferFileFormat.filenameExtension)")

        #expect(state.enqueueIfSupported(url: firstURL))
        let firstRequest = state.pendingRequest

        #expect(state.enqueueIfSupported(url: secondURL))
        let replacedRequest = state.pendingRequest

        #expect(firstRequest?.fileURL == firstURL)
        #expect(replacedRequest?.fileURL == secondURL)
        #expect(replacedRequest?.requestID != firstRequest?.requestID)
    }

    @Test
    func enqueueIfSupportedIgnoresNonTemplateURLs() {
        let state = TemplateFileOpenState()
        let webURL = URL(string: "https://wegojim.app/template")!
        let textFileURL = URL(fileURLWithPath: "/tmp/template.txt")

        #expect(state.enqueueIfSupported(url: webURL) == false)
        #expect(state.pendingRequest == nil)

        #expect(state.enqueueIfSupported(url: textFileURL) == false)
        #expect(state.pendingRequest == nil)
    }

    @Test
    func routePendingRequestWaitsUntilMainPhase() {
        let state = TemplateFileOpenState()
        let tabState = AppTabState()
        tabState.selectedTab = .history

        let fileURL = URL(fileURLWithPath: "/tmp/import.\(TemplateTransferFileFormat.filenameExtension)")
        #expect(state.enqueueIfSupported(url: fileURL))

        state.routePendingRequestIfNeeded(appPhase: .splash, tabState: tabState)
        #expect(tabState.selectedTab == .history)
        #expect(state.pendingRequest?.fileURL == fileURL)

        state.routePendingRequestIfNeeded(appPhase: .login, tabState: tabState)
        #expect(tabState.selectedTab == .history)
        #expect(state.pendingRequest?.fileURL == fileURL)

        state.routePendingRequestIfNeeded(appPhase: .main, tabState: tabState)
        #expect(tabState.selectedTab == .startWorkout)
        #expect(state.pendingRequest?.fileURL == fileURL)
    }

    @Test
    func clearConsumesOnlyMatchingPendingRequest() throws {
        let state = TemplateFileOpenState()
        let firstURL = URL(fileURLWithPath: "/tmp/import-a.\(TemplateTransferFileFormat.filenameExtension)")
        let secondURL = URL(fileURLWithPath: "/tmp/import-b.\(TemplateTransferFileFormat.filenameExtension)")

        #expect(state.enqueueIfSupported(url: firstURL))
        let firstRequestID = try #require(state.pendingRequest?.requestID)

        #expect(state.enqueueIfSupported(url: secondURL))
        let secondRequest = try #require(state.pendingRequest)

        state.clear(requestID: firstRequestID)
        #expect(state.pendingRequest == secondRequest)

        state.clear(requestID: secondRequest.requestID)
        #expect(state.pendingRequest == nil)
    }
}
