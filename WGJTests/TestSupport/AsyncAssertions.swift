import XCTest

/// Polls observable state while yielding the main actor, and reports the caller's location.
@MainActor
func assertEventually(
    timeout: Duration = .seconds(1),
    file: StaticString = #filePath,
    line: UInt = #line,
    _ predicate: @escaping @MainActor () -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !predicate() {
        guard ContinuousClock.now < deadline else {
            XCTFail("Condition did not become true before the deadline", file: file, line: line)
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(5))
        } catch {
            XCTFail("Wait was canceled", file: file, line: line)
            return
        }
    }
}
