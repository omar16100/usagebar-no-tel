import XCTest
@testable import OpenUsage

/// Free-tier accounts get a 403 `SUBSCRIPTION_REQUIRED` from the quota summary RPC, while the legacy
/// endpoints still answer with the same token. That 403 is a license answer for one RPC, not a rejected
/// token, so it must not read as "sign-in expired".
final class AntigravitySubscriptionRequiredTests: XCTestCase {
    private func used(_ line: MetricLine?) -> Double? {
        guard case .progress(_, let used, _, _, _, _, _)? = line else { return nil }
        return used
    }

    /// The body Cloud Code returned on 1 Nov 2026 for a free-tier account (both hosts).
    static let subscriptionRequiredBody = #"""
    {"error":{"code":403,"message":"You do not have a valid license of this product. Please contact your administrator to request a license. (#3501)","status":"PERMISSION_DENIED","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"SUBSCRIPTION_REQUIRED","domain":"cloudaicompanion.googleapis.com","metadata":{"uiMessage":"true","error_number":"1001"}},{"@type":"type.googleapis.com/google.rpc.Help","links":[{"description":"Learn more","url":"https://cloud.google.com/gemini/docs/codeassist/request-license"}]}]}}
    """#

    static let modelsJSON = """
    {"models":{
      "p":{"model":"MODEL_P","displayName":"Gemini 3.1 Pro (High)","quotaInfo":{"remainingFraction":0.4,"resetTime":"2026-06-26T09:37:05Z"}},
      "c":{"model":"MODEL_C","displayName":"Claude Opus 4.6 (Thinking)","quotaInfo":{"remainingFraction":0.7,"resetTime":"2026-06-26T09:44:00Z"}}
    }}
    """

    @MainActor
    private func makeCloudCodeProvider(routing: RoutingHTTPClient) -> AntigravityProvider {
        let inner = #"{"token":{"access_token":"ya29.kc","refresh_token":"1//r","expiry":"2099-01-01T00:00:00Z"}}"#
        let wrapped = "go-keyring-base64:" + Data(inner.utf8).base64EncodedString()
        return AntigravityProvider(
            authStore: AntigravityAuthStore(keychain: FakeKeychain(wrapped), files: FakeFiles()),
            usageClient: AntigravityUsageClient(lsHTTP: routing, http: routing),
            discovery: LanguageServerDiscovery(processRunner: EmptyProcessRunner()),
            dbUsageScanner: AntigravityDbUsageScanner(conversationsDirectories: { ["/nonexistent-antigravity-tests"] })
        )
    }

    @MainActor
    func testSummarySubscriptionRequiredFallsBackToLegacyModels() async {
        let body = Self.subscriptionRequiredBody
        let models = Self.modelsJSON
        let routing = RoutingHTTPClient { request in
            let path = request.url.path
            if path == AntigravityUsageClient.quotaSummaryPath {
                return HTTPResponse(statusCode: 403, headers: [:], body: Data(body.utf8))
            }
            if path == AntigravityUsageClient.fetchModelsPath {
                return HTTPResponse(statusCode: 200, headers: [:], body: Data(models.utf8))
            }
            if path == AntigravityUsageClient.loadCodeAssistPath {
                return HTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"currentTier":{"id":"free-tier","name":"Antigravity"}}"#.utf8))
            }
            if request.url.host == "oauth2.googleapis.com" {
                return HTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"access_token":"ya29.new","expires_in":3599}"#.utf8))
            }
            return HTTPResponse(statusCode: 404, headers: [:], body: Data())
        }
        let provider = makeCloudCodeProvider(routing: routing)

        let snapshot = await provider.refresh()

        XCTAssertNil(snapshot.errorCategory)
        XCTAssertEqual(snapshot.lines.map(\.label), ["Session", "Claude"])
        XCTAssertEqual(used(snapshot.lines.first), 60)
        XCTAssertTrue(routing.requests.contains { $0.url.path == AntigravityUsageClient.fetchModelsPath })
    }

    /// Guard: any other 403 on the summary still rejects the token, so a dead refresh reads as expired.
    @MainActor
    func testSummaryOtherForbiddenReasonStillReportsAuthExpired() async {
        let body = #"{"error":{"code":403,"status":"PERMISSION_DENIED","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}}"#
        let routing = RoutingHTTPClient { request in
            if request.url.path == AntigravityUsageClient.quotaSummaryPath {
                return HTTPResponse(statusCode: 403, headers: [:], body: Data(body.utf8))
            }
            if request.url.host == "oauth2.googleapis.com" {
                return HTTPResponse(statusCode: 400, headers: [:], body: Data(#"{"error":"invalid_grant"}"#.utf8))
            }
            return HTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8))
        }
        let provider = makeCloudCodeProvider(routing: routing)

        let snapshot = await provider.refresh()

        XCTAssertEqual(snapshot.errorCategory, .authExpired)
        XCTAssertFalse(routing.requests.contains { $0.url.path == AntigravityUsageClient.fetchModelsPath })
    }
}
