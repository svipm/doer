import Foundation

/// linux.do serves API traffic for iOS clients from a challenge-free subdomain
/// (`ios.linux.do`, provided by the forum admins). API requests are rewritten to
/// it so Cloudflare never intercepts them; webviews, shared links and cookie
/// storage stay on the canonical host.
///
/// The session cookie (`_t`) is host-only for `linux.do`, so cookie lookups and
/// response-cookie storage must keep using the canonical host — see
/// `canonicalized(_:)` and the auth interceptor.
enum ForumAPIHostAlias {
    static let canonicalHost = "linux.do"
    static let aliasHost = "ios.linux.do"

    /// The alias URL for a forum API request, or nil when the request should keep
    /// the canonical base: other forums, non-HTTPS bases, or the alias switched off.
    static func apiRequestURL(base: String, path: String, enabled: Bool) -> String? {
        guard enabled else { return nil }
        guard let url = URL(string: base),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == canonicalHost
        else { return nil }
        let trimmedPath = path.hasPrefix("/") ? path : "/" + path
        return "https://\(aliasHost)\(trimmedPath)"
    }

    /// The canonical-host equivalent of an alias URL. Used for every cookie
    /// decision: looking up request cookies (the session cookie is host-only for
    /// the canonical host) and storing response cookies where the webview, the
    /// session refresher and the rest of the app expect them.
    static func canonicalized(_ url: URL) -> URL {
        guard url.host?.lowercased() == aliasHost,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.host = canonicalHost
        return components.url ?? url
    }

    /// Transport failures that mean the request never reached the server. Used to
    /// fall back to the canonical host when the alias is unreachable (e.g. DNS
    /// pollution); slower failures are not retried because the request may have
    /// landed and a replayed POST could double-apply.
    static func isUnreachableTransportError(_ error: Error?) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .notConnectedToInternet, .networkConnectionLost:
            return true
        default:
            return false
        }
    }
}
