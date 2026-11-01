import XCTest
@testable import OpenUsage

/// Anthropic renamed Max 5x to Max and Max 20x to Ultra on Oct 30, 2026 (upstream #1497, #1499).
/// Adapted from upstream: this fork's `formatLivePlan` also takes the stored login.
final class ClaudePlanTests: XCTestCase {
    private func plan(_ organizationType: String, _ rateLimitTier: String?) throws -> String? {
        let tier = rateLimitTier.map { #","rate_limit_tier":"\#($0)""# } ?? ""
        let json = #"{"account":{"uuid":"acc-1"},"organization":{"uuid":"org-1","organization_type":"\#(organizationType)"\#(tier)}}"#
        let profile = try JSONDecoder().decode(ClaudeAccountProfile.self, from: Data(json.utf8))
        return ClaudeUsageMapper.formatLivePlan(
            profile: profile, credentials: ClaudeOAuth(subscriptionType: nil, rateLimitTier: nil)
        )
    }

    func testMaxTiersReadUnderAnthropicsNewPlanNames() throws {
        XCTAssertEqual(try plan("claude_max", "default_claude_max_5x"), "Max")
        XCTAssertEqual(try plan("claude_max", "default_claude_max_20x"), "Ultra")
        XCTAssertEqual(try plan("claude_max", nil), "Max")
    }

    func testAnUltraTierOrOrganizationReadsUltra() throws {
        XCTAssertEqual(try plan("claude_max", "default_claude_ultra"), "Ultra")
        XCTAssertEqual(try plan("claude_ultra", "default_claude_ultra"), "Ultra")
        XCTAssertEqual(try plan("claude_ultra", "default_claude_max_20x"), "Ultra")
    }

    func testOtherPlansKeepTheirNames() throws {
        XCTAssertEqual(try plan("claude_pro", "default_claude_ai"), "Pro")
        XCTAssertEqual(try plan("claude_team", "default_claude_max_5x"), "Team 5x")
        XCTAssertEqual(try plan("claude_enterprise", nil), "Enterprise")
    }

    /// Before the hourly profile read, the badge comes from the plan saved with the login.
    func testStoredLoginPlanUsesTheNewNames() {
        XCTAssertEqual(ClaudeUsageMapper.formatPlan(subscriptionType: "max", rateLimitTier: "default_claude_max_20x"), "Ultra")
        XCTAssertEqual(ClaudeUsageMapper.formatPlan(subscriptionType: "max", rateLimitTier: "default_claude_max_5x"), "Max")
        XCTAssertEqual(ClaudeUsageMapper.formatPlan(subscriptionType: "team", rateLimitTier: "default_claude_max_5x"), "Team 5x")
    }

    /// A verified Ultra account gets no 5-hour window, so its card has no Session row.
    func testAUsageResponseWithNoFiveHourWindowHasNoSessionRow() throws {
        let credentials = ClaudeOAuth(subscriptionType: "max", rateLimitTier: "default_claude_max_20x")
        for body in [#"{"five_hour":null,"seven_day":{"utilization":40,"resets_at":"2099-01-01T00:00:00.000Z"}}"#,
                     #"{"seven_day":{"utilization":40,"resets_at":"2099-01-01T00:00:00.000Z"}}"#] {
            let mapped = try ClaudeUsageMapper.mapUsageResponse(
                HTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8)), credentials: credentials
            )
            XCTAssertNil(mapped.lines.first { $0.label == "Session" }, body)
            XCTAssertNotNil(mapped.lines.first { $0.label == "Weekly" }, body)
            XCTAssertEqual(mapped.plan, "Ultra", body)
        }
    }
}
