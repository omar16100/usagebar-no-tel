import XCTest
@testable import OpenUsage

/// While Anthropic rate-limits the usage endpoint, the card serves the last-good meters. A meter whose
/// reset time has passed describes a window that no longer exists, so it must not be shown as current:
/// a "Session 7%" row with a reset time in the past hid a 5-hour limit that was already used up.
@MainActor
final class ClaudeStaleWindowTests: XCTestCase {
    private nonisolated static let start = OpenUsageISO8601.date(from: "2026-11-16T05:00:00.000Z")!
    private nonisolated static let sessionReset = "2026-11-16T05:10:00.000Z"
    private nonisolated static let weeklyReset = "2099-01-01T00:00:00.000Z"
    private let path = "/tmp/claude/.credentials.json"

    func testRateLimitDropsLastGoodSessionWhoseResetHasPassed() async {
        let fixture = makeFixture()
        let live = await fixture.provider.refresh()
        XCTAssertEqual(progressUsed(live.lines, "Session"), 7)

        fixture.clock.value = Self.start.addingTimeInterval(11 * 60)
        fixture.limited.value = true
        let limited = await fixture.provider.refresh()

        XCTAssertNil(progressUsed(limited.lines, "Session"), "the elapsed 5-hour window must not read as current")
        XCTAssertEqual(progressUsed(limited.lines, "Weekly"), 16)
        XCTAssertEqual(limited.lines.filter { $0.label == "Note" }.count, 1)
        XCTAssertEqual(limited.warning?.hasPrefix("Updates blocked by Anthropic"), true)
    }

    func testCooldownServingAlsoDropsAnElapsedWindow() async {
        let fixture = makeFixture()
        _ = await fixture.provider.refresh()
        fixture.limited.value = true
        fixture.clock.value = Self.start.addingTimeInterval(5 * 60)
        let first = await fixture.provider.refresh()
        XCTAssertEqual(progressUsed(first.lines, "Session"), 7, "the window is still open at this point")

        // Still inside the 600 second cooldown, so no live call is made, but the window has now elapsed.
        fixture.clock.value = Self.start.addingTimeInterval(11 * 60 - 1)
        let cooled = await fixture.provider.refresh()

        XCTAssertNil(progressUsed(cooled.lines, "Session"))
        XCTAssertEqual(progressUsed(cooled.lines, "Weekly"), 16)
    }

    func testRateLimitKeepsLastGoodWindowThatHasNotReset() async {
        let fixture = makeFixture()
        _ = await fixture.provider.refresh()

        fixture.clock.value = Self.start.addingTimeInterval(5 * 60)
        fixture.limited.value = true
        let limited = await fixture.provider.refresh()

        XCTAssertEqual(progressUsed(limited.lines, "Session"), 7)
        XCTAssertEqual(progressUsed(limited.lines, "Weekly"), 16)
    }

    // MARK: - Helpers

    private struct Fixture {
        let provider: ClaudeProvider
        let clock: StaleWindowBox<Date>
        let limited: StaleWindowBox<Bool>
    }

    private func makeFixture() -> Fixture {
        let clock = StaleWindowBox(Self.start)
        let limited = StaleWindowBox(false)
        let files = FakeFiles([path: Self.credentials])
        let authStore = ClaudeAuthStore(
            environment: FakeEnvironment(["CLAUDE_CONFIG_DIR": "/tmp/claude"]),
            files: files,
            keychain: FakeKeychain(),
            expectedIdentityKey: nil,
            now: { clock.value }
        )
        let http = RoutingHTTPClient { request in
            switch request.url.path {
            case "/api/oauth/usage":
                return limited.value ? Self.rateLimited : Self.usage
            default:
                return HTTPResponse(statusCode: 404, headers: [:], body: Data())
            }
        }
        let provider = ClaudeProvider(
            authStore: authStore,
            usageClient: ClaudeUsageClient(httpClient: http),
            logUsageScanner: ClaudeLogFixture.scanner(home: nil),
            now: { clock.value },
            pricing: { TestPricing.bundled }
        )
        return Fixture(provider: provider, clock: clock, limited: limited)
    }

    private nonisolated static let credentials =
        #"{"claudeAiOauth":{"accessToken":"token-a","refreshToken":"refresh-a","expiresAt":4102444800000,"subscriptionType":"max","rateLimitTier":"default_claude_max_5x","scopes":["user:profile"]}}"#

    private nonisolated static let rateLimited = HTTPResponse(
        statusCode: 429, headers: ["retry-after": "600"], body: Data()
    )

    private nonisolated static let usage = HTTPResponse(
        statusCode: 200, headers: [:],
        body: Data(
            #"{"five_hour":{"utilization":7,"resets_at":"\#(sessionReset)"},"seven_day":{"utilization":16,"resets_at":"\#(weeklyReset)"}}"#
                .utf8
        )
    )

    private func progressUsed(_ lines: [MetricLine]?, _ label: String) -> Double? {
        guard case .progress(_, let used, _, _, _, _, _) = lines?.first(where: { $0.label == label }) else {
            return nil
        }
        return used
    }
}

private final class StaleWindowBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}
