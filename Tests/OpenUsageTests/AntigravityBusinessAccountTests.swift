import XCTest
@testable import OpenUsage

final class AntigravityBusinessAccountTests: XCTestCase {
    private let quota = #"{"groups":[{"displayName":"Gemini Enterprise Quota","buckets":[{"bucketId":"gemini-enterprise-weekly","window":"weekly","remainingFraction":0.75,"resetTime":"2026-11-30T01:37:21Z"}]}]}"#

    private let testBusinessClient = AntigravityUsageClient.BusinessOAuthClient(
        clientID: "test-business-client-id",
        clientSecret: "test-business-client-secret"
    )

    @MainActor
    private func provider(
        http: RoutingHTTPClient,
        expired: Bool = false,
        project: String = "test-project",
        businessClient: AntigravityUsageClient.BusinessOAuthClient? = AntigravityUsageClient.BusinessOAuthClient(
            clientID: "test-business-client-id",
            clientSecret: "test-business-client-secret"
        )
    ) -> AntigravityProvider {
        let expiry = expired ? "2000-01-01T00:00:00Z" : "2099-01-01T00:00:00Z"
        let raw = #"{"auth_method":"gcp","project_id":"\#(project)","region":"global","user_tier":"gcp-ge-plus-tier","token":{"access_token":"test-access","refresh_token":"test-refresh","expiry":"\#(expiry)"}}"#
        return AntigravityProvider(
            authStore: AntigravityAuthStore(keychain: FakeKeychain(raw), files: FakeFiles()),
            usageClient: AntigravityUsageClient(lsHTTP: http, http: http, businessOAuthClient: businessClient),
            discovery: LanguageServerDiscovery(processRunner: EmptyProcessRunner()),
            dbUsageScanner: AntigravityDbUsageScanner(conversationsDirectories: { ["/nonexistent-antigravity-tests"] })
        )
    }

    @MainActor
    func testBusinessAccountUsesProjectQuotaAndPlan() async throws {
        let quota = self.quota
        let http = RoutingHTTPClient { request in
            if request.url.host == "businessaicode.googleapis.com" {
                return HTTPResponse(statusCode: 200, headers: [:], body: Data(quota.utf8))
            }
            return HTTPResponse(statusCode: 403, headers: [:], body: Data())
        }
        let snapshot = await provider(http: http).refresh()
        XCTAssertNil(snapshot.errorCategory)
        XCTAssertEqual(snapshot.plan, "Gemini Enterprise Plus")
        XCTAssertEqual(snapshot.lines.map(\.label), ["Weekly"])
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.host, "businessaicode.googleapis.com")
        XCTAssertEqual(request.url.path, "/v1alpha/projects/test-project/locations/global:fetchQuotaStatus")
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "entitlement.userTier" })?.value, "gcp-ge-plus-tier")
        XCTAssertEqual(http.requests.count, 1)
    }

    @MainActor
    func testExpiredBusinessTokenUsesBusinessOAuthClient() async throws {
        let quota = self.quota
        let http = RoutingHTTPClient { request in
            if request.url.host == "oauth2.googleapis.com" {
                let body = String(data: request.body ?? Data(), encoding: .utf8) ?? ""
                let correctClient = body.contains("client_id=test-business-client-id")
                    && body.contains("client_secret=test-business-client-secret")
                return HTTPResponse(statusCode: correctClient ? 200 : 401, headers: [:], body: Data(
                    (correctClient ? #"{"access_token":"fresh-business-token","expires_in":3600}"# : #"{"error":"unauthorized_client"}"#).utf8
                ))
            }
            if request.url.host == "businessaicode.googleapis.com", request.headers["Authorization"] == "Bearer fresh-business-token" {
                return HTTPResponse(statusCode: 200, headers: [:], body: Data(quota.utf8))
            }
            return HTTPResponse(statusCode: 403, headers: [:], body: Data())
        }
        let snapshot = await provider(http: http, expired: true).refresh()
        XCTAssertNil(snapshot.errorCategory)
        XCTAssertEqual(snapshot.lines.map(\.label), ["Weekly"])
        XCTAssertEqual(http.requests.count, 2)
    }

    func testEnterpriseQuotaUsesWeeklyWindow() throws {
        let lines = try XCTUnwrap(AntigravityUsageMapper.parseQuotaSummary(Data(quota.utf8)))
        XCTAssertEqual(lines.count, 1)
        guard case .progress(let label, let used, let limit, _, let reset, let duration, _)? = lines.first else {
            return XCTFail("The enterprise quota must produce a progress line.")
        }
        XCTAssertEqual(label, "Weekly")
        XCTAssertEqual(used, 25)
        XCTAssertEqual(limit, 100)
        XCTAssertEqual(duration, MetricPeriod.weekMs)
        XCTAssertEqual(reset, OpenUsageISO8601.date(from: "2026-11-30T01:37:21Z"))
    }

    @MainActor
    func testBusinessOutageDoesNotUsePersonalQuota() async {
        let http = RoutingHTTPClient { _ in HTTPResponse(statusCode: 503, headers: [:], body: Data()) }
        let snapshot = await provider(http: http).refresh()
        XCTAssertEqual(snapshot.errorCategory, .network)
        XCTAssertEqual(http.requests.map { $0.url.host }, ["businessaicode.googleapis.com"])
    }

    func testDisabledOrInvalidEnterpriseQuotaDoesNotInventUsage() {
        for fields in [#""window":"weekly","disabled":true,"remainingFraction":1"#, #""window":"weekly","remainingFraction":"invalid""#, #""remainingFraction":1,"window":"daily""#] {
            let body = #"{"groups":[{"buckets":[{"bucketId":"gemini-enterprise-weekly",\#(fields)}]}]}"#
            XCTAssertEqual(AntigravityUsageMapper.parseQuotaSummary(Data(body.utf8))?.count, 0)
        }
    }

    @MainActor
    func testMissingBusinessProjectDoesNotUsePersonalQuota() async {
        let http = RoutingHTTPClient { _ in HTTPResponse(statusCode: 200, headers: [:], body: Data()) }
        let snapshot = await provider(http: http, project: "").refresh()
        XCTAssertEqual(snapshot.errorCategory, .network)
        XCTAssertTrue(http.requests.isEmpty)
    }

    @MainActor
    func testBusinessPermissionRefusalDoesNotRefreshToken() async {
        let http = RoutingHTTPClient { _ in HTTPResponse(statusCode: 403, headers: [:], body: Data()) }
        let snapshot = await provider(http: http).refresh()
        XCTAssertEqual(snapshot.errorCategory, .network)
        XCTAssertEqual(http.requests.map { $0.url.host }, ["businessaicode.googleapis.com"])
    }

    @MainActor
    func testMissingBusinessOAuthClientDoesNotFallbackToConsumerClient() async {
        let http = RoutingHTTPClient { _ in HTTPResponse(statusCode: 200, headers: [:], body: Data()) }
        let snapshot = await provider(http: http, expired: true, businessClient: nil).refresh()
        XCTAssertEqual(snapshot.errorCategory, .network)
        XCTAssertTrue(http.requests.isEmpty)
    }
}
