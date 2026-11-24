import Foundation

/// The installed provider set and its canonical order. Both the menu-bar app and one-shot CLI build
/// their runtimes here so credentials, refresh behavior, pricing, and normalization can never drift.
@MainActor
enum ProviderCatalog {
    static func make(
        defaults: UserDefaults = .standard,
        claudeCards: [ClaudeAccountCard] = [],
        codex: CodexAccountDiscovery = CodexAccountDiscovery(),
        antigravityCards: [AntigravityAccountCard] = [],
        claudeIdentityKeys: [String: String] = [:]
    ) -> [ProviderRuntime] {
        // Default provider order (see AGENTS.md "## Providers"): the three established providers first,
        // then every other provider alphabetically by display name.
        var providers: [ProviderRuntime]
        if claudeCards.isEmpty {
            providers = [ClaudeProvider()]
        } else {
            providers = claudeCards.map { card in
                let identity = claudeIdentityKeys[card.id] ?? card.identityKey
                let user = identity.split(separator: "|").first.map(String.init)
                let environment = ClaudeProfileEnvironment(configDirectory: card.configDirectory)
                let scanner = ClaudeLogUsageScanner(
                    environment: environment,
                    accountUUID: user, organizationUUID: card.organizationID,
                    allowsUnattributedSessions: card.allowsUnattributedPiUsage,
                    additionalConfigDirectories: card.additionalLogDirectories
                )
                return ClaudeProvider(
                    provider: ClaudeProvider.makeProvider(
                        id: card.id,
                        displayName: claudeCards.count == 1 ? "Claude" : card.displayName
                    ),
                    authStore: ClaudeAuthStore(
                        environment: environment,
                        desktopOrganization: card.organizationID,
                        expectedIdentityKey: identity,
                        desktopOnly: card.usesDesktopCredentials,
                        swapAccount: card.swapAccount,
                        preferOrganizationScopedDesktop: claudeCards.count > 1
                            && card.organizationID != nil && !card.usesDesktopCredentials
                            && card.configDirectory == nil
                    ),
                    logUsageScanner: scanner,
                    allowsUnattributedPiUsage: card.allowsUnattributedPiUsage
                )
            }
        }
        if codex.cards.isEmpty {
            providers.append(CodexProvider(
                authStore: CodexAuthStore(
                    additionalAuthHomes: codex.plainAuthHomes,
                    writableAuthHomes: Set(codex.plainWritableAuthHomes),
                    piCredentialSources: codex.plainPiCredentialSources
                ),
                logUsageScanner: CodexLogUsageScanner(additionalHomes: codex.plainAuthHomes)
            ))
        } else {
            providers += codex.cards.map { card in
                CodexProvider(
                    provider: CodexProvider.makeProvider(id: card.id, displayName: card.displayName),
                    authStore: CodexAuthStore(
                        expectedIdentity: card.identity,
                        additionalAuthHomes: card.authHomes,
                        writableAuthHomes: Set(card.writableAuthHomes),
                        piCredentialSources: card.piCredentialSources
                    ),
                    historyScope: .account(card.identity, codex.historyHomes, claimsPiUsage: card.claimsPiUsage)
                )
            }
        }
        providers.append(CursorProvider())
        let businessOAuthClient = AntigravityUsageClient.configuredBusinessOAuthClient(defaults: defaults)
        if antigravityCards.isEmpty {
            providers.append(AntigravityProvider(
                usageClient: AntigravityUsageClient(businessOAuthClient: businessOAuthClient)
            ))
        } else {
            let singleCard = antigravityCards.count == 1
            providers += antigravityCards.map { card in
                let provider = AntigravityProvider.makeProvider(
                    id: card.id,
                    displayName: singleCard ? "Antigravity" : card.displayName
                )
                let authStore: AntigravityAuthStore
                let usageClient: AntigravityUsageClient
                let dbUsageScanner: AntigravityDbUsageScanner
                if let profileHome = card.profileHome {
                    let geminiHome = profileHome.trimmingTrailingSlashes + "/.gemini"
                    authStore = AntigravityAuthStore(
                        credentialSource: .tokenFile(AntigravityAuthStore.tokenFilePath(forHome: profileHome)),
                        cachePath: AntigravityAuthStore.cachePath(forProviderID: card.id)
                    )
                    usageClient = AntigravityUsageClient(
                        cloudCodeBaseURLs: AntigravityUsageClient.cliCloudCodeURLs,
                        businessOAuthClient: businessOAuthClient
                    )
                    dbUsageScanner = AntigravityDbUsageScanner(
                        geminiHome: geminiHome,
                        conversationsDirectories: {
                            try AntigravityDbUsageScanner.conversationsDirectories(underGeminiHome: geminiHome)
                        }
                    )
                } else {
                    authStore = AntigravityAuthStore(
                        credentialSource: .keychain,
                        cachePath: AntigravityAuthStore.cachePath(forProviderID: card.id)
                    )
                    usageClient = AntigravityUsageClient(businessOAuthClient: businessOAuthClient)
                    dbUsageScanner = AntigravityDbUsageScanner()
                }
                return AntigravityProvider(
                    provider: provider,
                    authStore: authStore,
                    usageClient: usageClient,
                    dbUsageScanner: dbUsageScanner,
                    usesLanguageServer: singleCard && card.profileHome == nil
                )
            }
        }
        providers += [
            CopilotProvider(defaults: defaults),
            DevinProvider(),
            GrokProvider(),
            OllamaProvider(),
            OpenCodeProvider(),
            OpenRouterProvider(),
            ZAIProvider()
        ]
        return providers
    }
}

/// Pin both credentials and logs to a card's profile without changing the process environment.
struct ClaudeProfileEnvironment: EnvironmentReading {
    var configDirectory: String?
    var base: any EnvironmentReading = ProcessEnvironmentReader()

    func value(for name: String) -> String? {
        if name == "CLAUDE_CONFIG_DIR", let configDirectory { return configDirectory }
        return base.value(for: name)
    }
}
