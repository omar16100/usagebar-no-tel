import Foundation

extension AntigravityUsageClient {
    static let businessOAuthClientIDKey = "openusage.antigravity.businessOAuthClientID.v1"
    static let businessOAuthClientSecretKey = "openusage.antigravity.businessOAuthClientSecret.v1"

    struct BusinessOAuthClient: Sendable, Equatable {
        var clientID: String
        var clientSecret: String
    }

    static func configuredBusinessOAuthClient(defaults: UserDefaults = .standard) -> BusinessOAuthClient? {
        guard let clientID = defaults.string(forKey: businessOAuthClientIDKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
              let clientSecret = defaults.string(forKey: businessOAuthClientSecretKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        else { return nil }
        return BusinessOAuthClient(clientID: clientID, clientSecret: clientSecret)
    }

    /// Request the project quota with the entitlement from the current Antigravity account.
    func businessQuota(token: String, credentials: AntigravityKeychainToken) async -> CloudCodeOutcome {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard let project = credentials.projectID?.nilIfEmpty,
              let region = credentials.region?.nilIfEmpty,
              let tier = credentials.userTier?.nilIfEmpty,
              project.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              region.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            AppLog.error(LogTag.plugin("antigravity"), "Business account has no valid project, region, or tier")
            return .unavailable
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "businessaicode.googleapis.com"
        components.path = "/v1alpha/projects/\(project)/locations/\(region):fetchQuotaStatus"
        components.queryItems = [URLQueryItem(name: "entitlement.userTier", value: tier)]
        guard let url = components.url else { return .unavailable }
        let request = HTTPRequest(
            method: "GET",
            url: url,
            headers: ["Accept": "application/json", "Authorization": "Bearer \(token)", "User-Agent": Self.clientUserAgent],
            timeout: 15
        )
        guard let response = try? await http.send(request) else { return .unavailable }
        if response.statusCode == 401 { return .authFailed }
        guard (200..<300).contains(response.statusCode) else {
            AppLog.warn(LogTag.plugin("antigravity"), "Business quota request returned HTTP \(response.statusCode)")
            return .unavailable
        }
        return .ok(response.body)
    }
}
