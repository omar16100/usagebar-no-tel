import XCTest
import Synchronization
@testable import OpenUsage

/// The launch account pass end to end: observer outcomes → account registry records → the per-card
/// identity map consumed by the snapshot cache stamp and the bare-id resolver.
@MainActor
final class ProviderAccountAssemblyTests: XCTestCase {
    private func makeScratchDefaults() -> UserDefaults {
        let suiteName = "OpenUsageTests.ProviderAccountAssembly.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    func testResolvedFamiliesFeedIdentityKeysAndTheRegistry() async throws {
        let defaults = makeScratchDefaults()
        let store = ProviderAccountsStore(defaults: defaults)
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment([:]),
            files: FakeFiles([
                // Claude resolved at the default home; Codex has credentials that name no account.
                "/Users/dev/.claude.json": #"{"oauthAccount": {"accountUuid": "ACCT-1", "emailAddress": "dev@example.com"}}"#,
                "/Users/dev/.codex/auth.json": #"{"tokens": {"access_token": "at-1"}}"#,
            ]),
            keychain: FakeKeychain(nil),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )

        let assembly = await ProviderAccountAssembly.make(observer: observer, accountsStore: store)

        XCTAssertEqual(assembly.identityKeysByCard, ["claude": "acct-1"])
        // The registry recorded the resolved account under the bare id, holding the default badge.
        let record = try XCTUnwrap(store.defaultBadgeHolder(family: "claude"))
        XCTAssertEqual(record.id, "claude")
        XCTAssertEqual(record.label, "dev@example.com")
        XCTAssertEqual(record.sources.map(\.kind), [.defaultHome])
        // An unresolved family claims no account: no record, no identity key.
        XCTAssertNil(store.defaultBadgeHolder(family: "codex"))
    }

    /// A family whose home facts aren't readable this launch (first Finder/Dock launch racing a
    /// slow shell) is left out of the pass entirely: not observed, not reconciled — while a family
    /// whose home override is already in the process environment still resolves.
    func testFamiliesOutsideThePassAreNeitherObservedNorReconciled() async {
        let defaults = makeScratchDefaults()
        let store = ProviderAccountsStore(defaults: defaults)
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment([:]),
            files: FakeFiles([
                "/Users/dev/.claude.json": #"{"oauthAccount": {"accountUuid": "ACCT-1"}}"#,
                "/Users/dev/.codex/auth.json": #"{"tokens": {"access_token": "at-1", "account_id": "CODEX-1"}}"#,
            ]),
            keychain: FakeKeychain(nil),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )

        let assembly = await ProviderAccountAssembly.make(observer: observer, accountsStore: store, families: ["codex"])

        XCTAssertEqual(assembly.identityKeysByCard, ["codex": "codex-1"])
        XCTAssertNil(store.defaultBadgeHolder(family: "claude"), "an out-of-pass family must not be reconciled")
    }

    func testNothingObservedLeavesRegistryAndKeysEmpty() async {
        let defaults = makeScratchDefaults()
        let store = ProviderAccountsStore(defaults: defaults)
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment([:]),
            files: FakeFiles([:]),
            keychain: FakeKeychain(nil),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )

        let assembly = await ProviderAccountAssembly.make(observer: observer, accountsStore: store)

        XCTAssertTrue(assembly.identityKeysByCard.isEmpty)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertNil(defaults.data(forKey: ProviderAccountsStore.storageKey), "no observations, no write")
    }

    func testPersonalProfileReattachesExistingDesktopCardWithoutChangingWorkAccount() async throws {
        let defaults = makeScratchDefaults()
        let store = ProviderAccountsStore(defaults: defaults)
        store.reconcile(with: [
            .init(family: "claude", identityKey: "work|work-org", label: "Work", sources: [
                .init(kind: .defaultHome, anchor: "/Users/dev/.claude-work", holdsDefaultSource: true)
            ]),
            .init(family: "claude", identityKey: "personal|personal-org", label: "Personal", sources: [
                .init(kind: .defaultHome, anchor: "/Users/dev/Library/Application Support/Claude", holdsDefaultSource: false)
            ])
        ])
        let personalID = try XCTUnwrap(store.records.last?.id)
        let environment = FakeEnvironment(["CLAUDE_CONFIG_DIR": "/Users/dev/.claude-work"])
        let files = FakeFiles([
            "/Users/dev/.claude-work/.claude.json": #"{"oauthAccount":{"accountUuid":"work","organizationUuid":"work-org","organizationName":"Work"}}"#,
            "/Users/dev/.claude-personal/.claude.json": #"{"oauthAccount":{"accountUuid":"personal","organizationUuid":"personal-org","organizationName":"Personal org"}}"#
        ])
        let observer = DefaultAccountObserver(
            environment: environment, files: files, keychain: FakeKeychain(),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )
        let assembly = await ProviderAccountAssembly.make(
            observer: observer, accountsStore: store, families: ["claude"],
            claudeConfigDirectories: ["~/.claude-personal", "/Users/dev/.claude-personal/", "/Users/dev/.claude-work"]
        )

        XCTAssertEqual(assembly.claudeCards.map(\.id), ["claude", personalID])
        XCTAssertEqual(assembly.identityKeysByCard, ["claude": "work|work-org", personalID: "personal|personal-org"])
        XCTAssertEqual(store.defaultBadgeHolder(family: "claude")?.id, "claude")
        XCTAssertEqual(assembly.claudeCards.last?.displayName, "Claude — Personal")
        XCTAssertEqual(assembly.claudeCards.last?.configDirectory, "/Users/dev/.claude-personal")
        XCTAssertEqual(store.records.last?.sources, [
            .init(kind: .configDirectory, anchor: "/Users/dev/.claude-personal", holdsDefaultSource: false)
        ])
        XCTAssertFalse(assembly.claudeCards.contains { $0.allowsUnattributedPiUsage })

        let providers = ProviderCatalog.make(claudeCards: assembly.claudeCards).compactMap { $0 as? ClaudeProvider }
        var personalAuth = try XCTUnwrap(providers.last?.authStore)
        XCTAssertFalse(personalAuth.desktopOnly)
        XCTAssertFalse(personalAuth.preferOrganizationScopedDesktop)
        XCTAssertEqual(personalAuth.expectedIdentityKey, "personal|personal-org")
        // With work exported globally, the personal provider still reads the personal profile's
        // Keychain entry. A work token must not shadow the personal token or refresh into its slot.
        personalAuth.files = files
        let keychain = ServiceKeychain()
        personalAuth.keychain = keychain
        let workService = ClaudeAuthStore(environment: environment).keychainServiceCandidates()[0]
        let personalService = ClaudeAuthStore(
            environment: FakeEnvironment(["CLAUDE_CONFIG_DIR": "/Users/dev/.claude-personal"])
        ).keychainServiceCandidates()[0]
        keychain.currentUserValues[workService] = #"{"claudeAiOauth":{"accessToken":"work-token","scopes":["user:profile"]}}"#
        keychain.currentUserValues[personalService] = #"{"claudeAiOauth":{"accessToken":"personal-token","scopes":["user:profile"]}}"#
        XCTAssertEqual(personalAuth.loadCredentialCandidates().first?.oauth.accessToken, "personal-token")
    }

    func testAdditionalProfileWorksWithoutDefaultOrDesktopLoginAndRejectsUnknownIdentities() async {
        let store = ProviderAccountsStore(defaults: makeScratchDefaults())
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment(), files: FakeFiles([
                "/Users/dev/.claude-personal/.claude.json": #"{"oauthAccount":{"accountUuid":"personal","organizationUuid":"personal-org"}}"#,
                "/Users/dev/.claude-incomplete/.claude.json": #"{"oauthAccount":{"accountUuid":"unknown"}}"#
            ]), keychain: FakeKeychain(), homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )
        let assembly = await ProviderAccountAssembly.make(
            observer: observer, accountsStore: store, families: ["claude"],
            claudeConfigDirectories: ["", "~/.claude-missing", "~/.claude-incomplete", "~/.claude-personal"]
        )
        XCTAssertEqual(assembly.claudeCards.count, 1)
        XCTAssertEqual(assembly.claudeCards.first?.identityKey, "personal|personal-org")
        XCTAssertEqual(assembly.claudeCards.first?.configDirectory, "/Users/dev/.claude-personal")
        XCTAssertNil(store.defaultBadgeHolder(family: "claude"))
    }

    // A default login with no organization takes an early return when it is the only Claude
    // account. A configured profile must still get its card on that path.
    func testProfileCardSurvivesDefaultLoginWithoutOrganization() async {
        let store = ProviderAccountsStore(defaults: makeScratchDefaults())
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment(), files: FakeFiles([
                "/Users/dev/.claude.json": #"{"oauthAccount":{"accountUuid":"default-user"}}"#,
                "/Users/dev/.claude-personal/.claude.json": #"{"oauthAccount":{"accountUuid":"personal","organizationUuid":"personal-org"}}"#
            ]), keychain: FakeKeychain(), homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )
        let assembly = await ProviderAccountAssembly.make(
            observer: observer, accountsStore: store, families: ["claude"],
            claudeConfigDirectories: ["~/.claude-personal"]
        )
        let profileCard = assembly.claudeCards.first { $0.identityKey == "personal|personal-org" }
        XCTAssertEqual(profileCard?.configDirectory, "/Users/dev/.claude-personal")
        XCTAssertEqual(assembly.claudeCards.count, 2, "the default login keeps its own card")
    }

    func testSwapDiscoveryKeepsMatchingExplicitProfileCredentials() async throws {
        let home = URL(fileURLWithPath: "/Users/dev")
        let profile = home.appendingPathComponent(".claude-personal").path
        let user = "11111111-1111-1111-1111-111111111111"
        let org = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let files = FakeFiles([
            profile + "/.claude.json": #"{"oauthAccount":{"accountUuid":"\#(user)","organizationUuid":"\#(org)"}}"#,
            profile + "/.credentials.json": #"{"claudeAiOauth":{"accessToken":"personal-token","scopes":["user:profile"]}}"#,
            home.path + "/.claude-swap-backup/sequence.json": #"{"accounts":{"1":{"email":"personal@example.com","uuid":"\#(user)","organizationUuid":"\#(org)"}}}"#
        ])
        let defaults = makeScratchDefaults()
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment(), files: files, keychain: FakeKeychain(),
            homeDirectory: { home }
        )
        let assembly = await ProviderAccountAssembly.make(
            observer: observer, accountsStore: ProviderAccountsStore(defaults: defaults), families: ["claude"],
            claudeConfigDirectories: [profile]
        )
        XCTAssertEqual(assembly.claudeCards.count, 1)
        let card = try XCTUnwrap(assembly.claudeCards.first)
        XCTAssertEqual(card.configDirectory, profile)
        XCTAssertNotNil(card.swapAccount)
        let provider = try XCTUnwrap(ProviderCatalog.make(defaults: defaults, claudeCards: [card])
            .compactMap { $0 as? ClaudeProvider }.first)
        var auth = provider.authStore
        auth.files = files
        auth.keychain = FakeKeychain()
        auth.desktop = ClaudeDesktopAuthStore(files: files, homeDirectory: { home })
        XCTAssertEqual(auth.loadCredentialCandidates().map(\.oauth.accessToken), ["personal-token"])
    }
    func testFamilyDiscoveryRunsOffMainActor() async {
        let store = ProviderAccountsStore(defaults: makeScratchDefaults())
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment([:]),
            files: BackgroundDiscoveryFiles(),
            keychain: FakeKeychain(nil),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )

        let assembly = await ProviderAccountAssembly.make(
            observer: observer,
            accountsStore: store,
            listCodexHomeDirectories: { path in
                guard path == "/Users/dev" else { return [] }
                return Thread.isMainThread ? [".codex-main"] : [".codex-background"]
            }
        )

        XCTAssertEqual(assembly.identityKeysByCard["claude"], "claude-id")
        XCTAssertEqual(assembly.codex.plainAuthHomes, ["/Users/dev/.codex-background"])
    }

    func testEstablishedCodexAccountsKeepDefaultIdentityWhenNoCardsAreDiscovered() async {
        let store = ProviderAccountsStore(defaults: makeScratchDefaults())
        store.reconcile(with: [
            .init(
                family: "codex", identityKey: "workspace-a|a@example.test", label: "A",
                sources: [.init(kind: .codexHome, anchor: "/Users/dev/.codex-a", holdsDefaultSource: false)]
            ),
            .init(
                family: "codex", identityKey: "workspace-b|b@example.test", label: "B",
                sources: [.init(kind: .codexHome, anchor: "/Users/dev/.codex-b", holdsDefaultSource: false)]
            ),
        ])
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment([:]),
            files: CodexAuthAppearsAfterScan(),
            keychain: FakeKeychain(nil),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )

        let assembly = await ProviderAccountAssembly.make(
            observer: observer, accountsStore: store, families: ["codex"]
        )

        XCTAssertTrue(assembly.codexCards.isEmpty)
        XCTAssertEqual(assembly.identityKeysByCard["codex"], "default-account")
    }
}

private final class CodexAuthAppearsAfterScan: TextFileAccessing, Sendable {
    private let defaultHomeReads = Mutex(0)
    private let auth = #"{"tokens":{"access_token":"token","account_id":"default-account"}}"#

    func exists(_ path: String) -> Bool { false }

    func readTextIfPresent(_ path: String) throws -> String? {
        guard path == "/Users/dev/.codex/auth.json" else { return nil }
        let read = defaultHomeReads.withLock { count in
            count += 1
            return count
        }
        return read == 1 ? nil : auth
    }

    func readText(_ path: String) throws -> String {
        if let text = try readTextIfPresent(path) { return text }
        throw CocoaError(.fileReadNoSuchFile)
    }

    func writeText(_ path: String, _ text: String) throws {}
    func remove(_ path: String) throws {}
}

private struct BackgroundDiscoveryFiles: TextFileAccessing {
    func exists(_ path: String) -> Bool { false }

    func readTextIfPresent(_ path: String) throws -> String? {
        guard !Thread.isMainThread else { return nil }
        switch path {
        case "/Users/dev/.claude.json":
            return #"{"oauthAccount":{"accountUuid":"CLAUDE-ID"}}"#
        case "/Users/dev/.codex-background/auth.json":
            return #"{"tokens":{"access_token":"token","account_id":"workspace-1"}}"#
        default:
            return nil
        }
    }

    func readText(_ path: String) throws -> String {
        throw CocoaError(.fileReadNoSuchFile)
    }

    func writeText(_ path: String, _ text: String) throws {}
    func remove(_ path: String) throws {}
}
