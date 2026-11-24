import XCTest
@testable import OpenUsage

@MainActor
final class AntigravityProfileAccountsTests: XCTestCase {
    private func makeScratchDefaults() -> UserDefaults {
        let suiteName = "OpenUsageTests.AntigravityProfiles.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private let workKeychainRaw = #"{"auth_method":"gcp","id_token_email":"work@example.test","project_id":"test-project","region":"global","user_tier":"gcp-ge-plus-tier","token":{"access_token":"work-access","refresh_token":"work-refresh","expiry":"2099-01-01T00:00:00Z"}}"#
    private let personalFileRaw = #"{"auth_method":"consumer","id_token_email":"personal@example.test","token":{"access_token":"personal-access","refresh_token":"personal-refresh","expiry":"2099-01-01T00:00:00Z"}}"#

    func testAssemblyCreatesDefaultAndProfileAntigravityCardsWithIsolatedCredentials() async throws {
        let defaults = makeScratchDefaults()
        let store = ProviderAccountsStore(defaults: defaults)
        let files = FakeFiles([
            "/Users/dev/.agy-personal/.gemini/antigravity-cli/antigravity-oauth-token": personalFileRaw
        ])
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment([:]),
            files: files,
            keychain: FakeKeychain(workKeychainRaw),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )

        let assembly = await ProviderAccountAssembly.make(
            observer: observer,
            accountsStore: store,
            families: ["antigravity"],
            antigravityProfileHomes: ["~/.agy-personal", "/Users/dev/.agy-personal/", "~", "~/.agy-missing"]
        )

        XCTAssertEqual(assembly.antigravityCards.count, 2)
        let workCard = try XCTUnwrap(assembly.antigravityCards.first)
        let personalCard = try XCTUnwrap(assembly.antigravityCards.last)

        XCTAssertEqual(workCard.id, "antigravity")
        XCTAssertEqual(workCard.identityKey, "work@example.test|test-project")
        XCTAssertEqual(workCard.displayName, "Antigravity — work@example.test")
        XCTAssertNil(workCard.profileHome)

        let expectedPersonalID = ProviderAccountID.make(family: "antigravity", identityKey: "personal@example.test")
        XCTAssertEqual(personalCard.id, expectedPersonalID)
        XCTAssertEqual(personalCard.identityKey, "personal@example.test")
        XCTAssertEqual(personalCard.displayName, "Antigravity — personal@example.test")
        XCTAssertEqual(personalCard.profileHome, "/Users/dev/.agy-personal")

        XCTAssertEqual(assembly.identityKeysByCard, [
            "antigravity": "work@example.test|test-project",
            expectedPersonalID: "personal@example.test"
        ])
        XCTAssertEqual(store.defaultBadgeHolder(family: "antigravity")?.id, "antigravity")

        let providers = ProviderCatalog.make(defaults: defaults, antigravityCards: assembly.antigravityCards)
            .compactMap { $0 as? AntigravityProvider }
        XCTAssertEqual(providers.map(\.provider.id), ["antigravity", expectedPersonalID])
        XCTAssertEqual(providers.map(\.provider.displayName), [
            "Antigravity — work@example.test",
            "Antigravity — personal@example.test"
        ])
        XCTAssertFalse(providers[0].usesLanguageServer, "multi-account cards must not probe an ambiguous language server")
        XCTAssertFalse(providers[1].usesLanguageServer)
        XCTAssertEqual(providers[0].authStore.credentialSource, .keychain)
        XCTAssertEqual(
            providers[1].authStore.credentialSource,
            .tokenFile("/Users/dev/.agy-personal/.gemini/antigravity-cli/antigravity-oauth-token")
        )
        XCTAssertEqual(providers[0].usageClient.cloudCodeBaseURLs, AntigravityUsageClient.cloudCodeURLs)
        XCTAssertEqual(providers[1].usageClient.cloudCodeBaseURLs, AntigravityUsageClient.cliCloudCodeURLs)
        XCTAssertNotEqual(providers[0].authStore.cachePath, providers[1].authStore.cachePath)

        // Widget descriptor IDs must be prefixed with each card's provider ID.
        XCTAssertTrue(providers[0].widgetDescriptors.contains { $0.id == "antigravity.geminiPro" })
        XCTAssertTrue(providers[1].widgetDescriptors.contains { $0.id == "\(expectedPersonalID).geminiPro" })
        XCTAssertFalse(providers[1].widgetDescriptors.contains { $0.id == "antigravity.geminiPro" })
    }

    func testEmptyProfileHomesLeavesDefaultSingleCardUntouched() async {
        let store = ProviderAccountsStore(defaults: makeScratchDefaults())
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment([:]),
            files: FakeFiles([:]),
            keychain: FakeKeychain(workKeychainRaw),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )

        let assembly = await ProviderAccountAssembly.make(
            observer: observer,
            accountsStore: store,
            families: ["antigravity"],
            antigravityProfileHomes: []
        )

        XCTAssertTrue(assembly.antigravityCards.isEmpty)
        XCTAssertTrue(assembly.identityKeysByCard.isEmpty)
        XCTAssertTrue(store.records.isEmpty)
    }

    func testProfileTokenFileProviderRefreshesWithoutTouchingKeychainOrLanguageServer() async throws {
        let tokenPath = "/Users/dev/.agy-personal/.gemini/antigravity-cli/antigravity-oauth-token"
        let files = FakeFiles([tokenPath: personalFileRaw])
        let authStore = AntigravityAuthStore(
            keychain: FakeKeychain(workKeychainRaw),
            files: files,
            credentialSource: .tokenFile(tokenPath),
            cachePath: "/cache/auth-personal.json"
        )
        let summaryBody = #"{"groups":[{"displayName":"Gemini","buckets":[{"bucketId":"gemini-5h","window":"5h","remainingFraction":0.8},{"bucketId":"gemini-weekly","window":"weekly","remainingFraction":0.9}]},{"displayName":"Claude","buckets":[{"bucketId":"3p-5h","window":"5h","remainingFraction":1.0},{"bucketId":"3p-weekly","window":"weekly","remainingFraction":0.7}]}]}"#
        let loadBody = #"{"paidTier":{"id":"g1-pro-tier","name":"Google AI Pro"}}"#
        let http = RoutingHTTPClient { request in
            if request.url.path.contains("retrieveUserQuotaSummary") {
                XCTAssertEqual(request.headers["Authorization"], "Bearer personal-access")
                XCTAssertEqual(request.headers["User-Agent"], AntigravityUsageClient.clientUserAgent)
                return HTTPResponse(statusCode: 200, headers: [:], body: Data(summaryBody.utf8))
            }
            if request.url.path.contains("loadCodeAssist") {
                XCTAssertEqual(request.headers["Authorization"], "Bearer personal-access")
                return HTTPResponse(statusCode: 200, headers: [:], body: Data(loadBody.utf8))
            }
            return HTTPResponse(statusCode: 404, headers: [:], body: Data())
        }
        let provider = AntigravityProvider(
            provider: AntigravityProvider.makeProvider(
                id: "antigravity@1234abcd",
                displayName: "Antigravity — personal@example.test"
            ),
            authStore: authStore,
            usageClient: AntigravityUsageClient(lsHTTP: http, http: http),
            discovery: LanguageServerDiscovery(processRunner: EmptyProcessRunner()),
            dbUsageScanner: AntigravityDbUsageScanner(conversationsDirectories: { ["/nonexistent-antigravity-tests"] }),
            usesLanguageServer: false
        )

        let hasCreds = await provider.hasLocalCredentials()
        XCTAssertTrue(hasCreds)

        let snapshot = await provider.refresh()
        XCTAssertNil(snapshot.errorCategory)
        XCTAssertEqual(snapshot.providerID, "antigravity@1234abcd")
        XCTAssertEqual(snapshot.plan, "Pro")
        XCTAssertEqual(snapshot.lines.map(\.label), ["Session", "Weekly", "Claude", "Claude Weekly"])
    }

    func testCachedTokensStayIsolatedBetweenCards() {
        let files = FakeFiles([:])
        let workStore = AntigravityAuthStore(
            files: files,
            credentialSource: .keychain,
            cachePath: AntigravityAuthStore.cachePath(forProviderID: "antigravity"),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let personalStore = AntigravityAuthStore(
            files: files,
            credentialSource: .tokenFile("/Users/dev/.agy-personal/.gemini/antigravity-cli/antigravity-oauth-token"),
            cachePath: AntigravityAuthStore.cachePath(forProviderID: "antigravity@1234abcd"),
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        workStore.cacheToken("work-refreshed", expiresIn: 3600, sourceRefreshToken: "work-refresh")
        personalStore.cacheToken("personal-refreshed", expiresIn: 3600, sourceRefreshToken: "personal-refresh")

        let workSource = AntigravityKeychainToken(accessToken: nil, refreshToken: "work-refresh", expiry: nil)
        let personalSource = AntigravityKeychainToken(accessToken: nil, refreshToken: "personal-refresh", expiry: nil)
        XCTAssertEqual(workStore.loadCachedToken(matching: workSource), "work-refreshed")
        XCTAssertEqual(personalStore.loadCachedToken(matching: personalSource), "personal-refreshed")
    }

    func testMultiAccountAntigravityHistoryDocumentValidatesAndAggregatesByIdentity() throws {
        let workID = "antigravity"
        let personalID = ProviderAccountID.make(family: "antigravity", identityKey: "personal@example.test")
        let day = DailyUsageEntry(date: "2026-11-24", totalTokens: 500, costUSD: 0.5)
        let peerDay = DailyUsageEntry(date: "2026-11-24", totalTokens: 300, costUSD: 0.3)

        let doc = UsageHistoryDocument(
            schema: UsageHistoryDocument.accountSchema,
            deviceID: "mac-a",
            deviceName: "Mac A",
            updatedAt: Date(),
            providers: [
                workID: ProviderUsageHistory(series: DailyUsageSeries(daily: [day])),
                personalID: ProviderUsageHistory(series: DailyUsageSeries(daily: [peerDay]))
            ],
            identities: [
                workID: "work@example.test|test-project",
                personalID: "personal@example.test"
            ]
        )
        XCTAssertNoThrow(try doc.validate())

        let providers: [ProviderRuntime] = [
            AntigravityProvider(provider: AntigravityProvider.makeProvider(id: workID, displayName: "Antigravity — Work")),
            AntigravityProvider(provider: AntigravityProvider.makeProvider(id: personalID, displayName: "Antigravity — Personal"))
        ]
        let registry = WidgetRegistry.from(providers)
        let peerDoc = UsageHistoryDocument(
            schema: UsageHistoryDocument.accountSchema,
            deviceID: "mac-b",
            deviceName: "Mac B",
            updatedAt: Date(),
            providers: [
                "antigravity": ProviderUsageHistory(series: DailyUsageSeries(daily: [peerDay]))
            ],
            identities: [
                "antigravity": "personal@example.test"
            ]
        )
        let now = OpenUsageISO8601.date(from: "2026-11-24T12:00:00Z")!
        let localSnapshots = [
            workID: ProviderSnapshot.make(
                provider: providers[0].provider,
                plan: nil,
                lines: [],
                refreshedAt: now,
                usageHistory: ProviderUsageHistory(series: DailyUsageSeries(daily: [day]))
            ),
            personalID: ProviderSnapshot.make(
                provider: providers[1].provider,
                plan: nil,
                lines: [],
                refreshedAt: now,
                usageHistory: ProviderUsageHistory(series: DailyUsageSeries(daily: [day]))
            )
        ]

        let merged = UsageHistoryAggregator.merged(
            localSnapshots: localSnapshots,
            peerDocuments: [peerDoc],
            descriptors: registry.historyDescriptorsByProvider,
            providerIdentityKeys: [
                workID: "work@example.test|test-project",
                personalID: "personal@example.test"
            ],
            now: now
        )

        XCTAssertEqual(merged[workID]?.series.daily.first?.totalTokens, 500, "personal peer history must not merge into work card")
        XCTAssertEqual(merged[personalID]?.series.daily.first?.totalTokens, 800, "matching personal peer history merges into personal card")
    }

    func testDefaultLayoutExpandsMetricsForAdditionalAntigravityCard() {
        let personalID = "antigravity@1234abcd"
        let expanded = DefaultLayout.expandingAccounts(
            DefaultLayout.metricIDs,
            providerIDs: ["antigravity", personalID]
        )
        XCTAssertTrue(expanded.contains("\(personalID).geminiPro"))
        XCTAssertTrue(expanded.contains("\(personalID).geminiWeekly"))
        XCTAssertTrue(expanded.contains("\(personalID).argonWeekly"))
        XCTAssertTrue(expanded.contains("\(personalID).claude"))
        XCTAssertTrue(expanded.contains("\(personalID).claudeWeekly"))
        XCTAssertTrue(expanded.contains("\(personalID).trend"))
        XCTAssertTrue(expanded.contains("\(personalID).today"))
    }
}
