import XCTest
@testable import OpenUsage

/// Crash reporting remains mandatory even when optional provider analytics are disabled.
final class TelemetrySinkTests: XCTestCase {
    func testErrorAutocaptureStaysEnabledRegardlessOfOptionalAnalytics() {
        XCTAssertTrue(
            PostHogTelemetrySink.errorAutocaptureEnabled(optionalAnalyticsEnabled: true),
            "crash autocapture must stay on when optional analytics are enabled"
        )
        XCTAssertTrue(
            PostHogTelemetrySink.errorAutocaptureEnabled(optionalAnalyticsEnabled: false),
            "crash autocapture must stay on when optional analytics are disabled"
        )
    }

    /// This build must ship no PostHog project token. `PostHogTelemetrySink.init` guards on
    /// `token != placeholderToken`, so a placeholder token leaves the sink inert: `PostHogSDK.setup()`
    /// is never called, and `capture`/`flush`/`setOptionalAnalyticsEnabled` all early-return. That is
    /// what makes this a no-network build, including the otherwise-mandatory daily ping and crash
    /// autocapture.
    func testNoRealProjectTokenIsBakedIntoTheBuild() {
        XCTAssertEqual(
            TelemetryConfig.token,
            TelemetryConfig.placeholderToken,
            "a real phc_ token would arm the sink and let it phone home"
        )
    }

    /// The environment override is removed too, so nothing can re-arm telemetry at runtime.
    func testEnvironmentCannotSupplyAProjectToken() {
        setenv("OPENUSAGE_POSTHOG_TOKEN", "phc_should_be_ignored", 1)
        defer { unsetenv("OPENUSAGE_POSTHOG_TOKEN") }

        XCTAssertEqual(
            TelemetryConfig.token,
            TelemetryConfig.placeholderToken,
            "OPENUSAGE_POSTHOG_TOKEN must not be able to arm telemetry in this build"
        )
    }
}
