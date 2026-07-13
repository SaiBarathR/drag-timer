import XCTest
@testable import DragTimer

final class UpdateCheckerTests: XCTestCase {
    func testReleaseVersionComparisonAndValidation() {
        XCTAssertEqual(ReleaseVersion("v1.2"), ReleaseVersion("1.2.0"))
        XCTAssertLessThan(ReleaseVersion("1.2.9")!, ReleaseVersion("1.3")!)
        XCTAssertLessThan(ReleaseVersion("1.9")!, ReleaseVersion("2.0")!)
        XCTAssertNil(ReleaseVersion("1.2-beta"))
        XCTAssertNil(ReleaseVersion("1..2"))
        XCTAssertNil(ReleaseVersion("1.2.3.4.5"))
        XCTAssertNil(ReleaseVersion("9999999999.1"))
    }

    func testNewerTrustedReleaseBecomesAvailableAndAutomaticChecksThrottle() async throws {
        let fixture = makeSettings()
        defer { fixture.cleanup() }
        let clock = TestClock(Date(timeIntervalSinceReferenceDate: 1_000))
        let transport = MockTransport(data: releaseJSON(tag: "v1.3.0"))
        let checker = UpdateChecker(
            settings: fixture.settings,
            transport: transport,
            currentVersionString: "1.2.0",
            now: { clock.date }
        )

        await checker.checkIfNeeded()
        await checker.checkIfNeeded()

        XCTAssertEqual(checker.availableRelease?.tagName, "v1.3.0")
        XCTAssertEqual(transport.callCount, 1)
        clock.date.addTimeInterval(24 * 60 * 60 + 1)
        await checker.checkIfNeeded()
        XCTAssertEqual(transport.callCount, 2)
    }

    func testCurrentReleaseHasNoBannerAndUntrustedLinkFailsClosed() async {
        let currentFixture = makeSettings()
        defer { currentFixture.cleanup() }
        let current = UpdateChecker(
            settings: currentFixture.settings,
            transport: MockTransport(data: releaseJSON(tag: "v1.2.0")),
            currentVersionString: "1.2.0"
        )
        await current.check(manual: true)
        XCTAssertEqual(current.state, .current)
        XCTAssertNil(current.availableRelease)

        let badFixture = makeSettings()
        defer { badFixture.cleanup() }
        let bad = UpdateChecker(
            settings: badFixture.settings,
            transport: MockTransport(data: releaseJSON(tag: "v2.0.0", url: "https://example.com/release")),
            currentVersionString: "1.2.0"
        )
        await bad.check(manual: true)
        XCTAssertEqual(bad.state, .failed("Could not check for updates."))
        XCTAssertNil(bad.availableRelease)
    }

    func testSilentAutomaticFailureKeepsCachedAvailableReleaseVisible() async {
        let fixture = makeSettings()
        defer { fixture.cleanup() }
        fixture.settings.cachedUpdateTag = "v1.3.0"
        fixture.settings.cachedUpdateURLString = "https://github.com/SaiBarathR/drag-timer/releases/tag/v1.3.0"
        let checker = UpdateChecker(
            settings: fixture.settings,
            transport: FailingTransport(),
            currentVersionString: "1.2.0"
        )
        XCTAssertEqual(checker.availableRelease?.tagName, "v1.3.0")

        await checker.check(manual: false)

        XCTAssertEqual(checker.availableRelease?.tagName, "v1.3.0")
    }

    private func releaseJSON(
        tag: String,
        url: String = "https://github.com/SaiBarathR/drag-timer/releases/tag/v1.3.0"
    ) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "tag_name": tag,
            "html_url": url,
            "name": "Drag Timer \(tag)",
            "published_at": "2026-07-13T17:30:14Z"
        ])
    }

    private func makeSettings() -> (settings: AppSettings, cleanup: () -> Void) {
        let suite = "DragTimerUpdateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppSettings(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
    }

    private final class MockTransport: UpdateTransport {
        let data: Data
        private(set) var callCount = 0
        init(data: Data) { self.data = data }

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            callCount += 1
            return (
                data,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
    }

    private final class TestClock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    private struct FailingTransport: UpdateTransport {
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            throw URLError(.notConnectedToInternet)
        }
    }
}
