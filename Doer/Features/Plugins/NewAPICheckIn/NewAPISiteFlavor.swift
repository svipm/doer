import Foundation

/// Site presets for NewAPI-family relay deployments. Forks disagree on the
/// check-in route and on which auth-refresh endpoint exists, so each flavor
/// carries candidates negotiated at runtime instead of one hardcoded path.
enum NewAPISiteFlavor: String, Codable, CaseIterable, Sendable {
    case newAPI = "new-api"
    case veloera = "veloera"
    case doneHub = "done-hub"
    /// Self-built / unknown check-in systems. No route negotiation; the
    /// user-configured endpoint is used verbatim.
    case generic = "generic"

    static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1"

    nonisolated var displayName: String {
        switch self {
        case .newAPI: return "NewAPI"
        case .veloera: return "Veloera"
        case .doneHub: return "DoneHub"
        case .generic: return String(localized: "plugins.newapi.flavor.generic", defaultValue: "通用签到")
        }
    }

    nonisolated var platformType: NewAPICheckInPlatformType {
        self == .generic ? .custom : .newAPI
    }

    /// Public fingerprint endpoint — no auth, safe to probe speculatively.
    nonisolated var statusPath: String { "/api/status" }

    nonisolated var userInfoPath: String { "/api/user/self" }

    /// Check-in routes seen across forks. The service tries them in order on
    /// the first sign-in and persists whichever one does not 404/405.
    nonisolated var checkInEndpointCandidates: [String] {
        switch self {
        case .newAPI: return ["/api/user/checkin", "/api/user/check_in"]
        case .veloera: return ["/api/user/check_in", "/api/user/checkin"]
        case .doneHub: return ["/api/user/check_in", "/api/user/checkin"]
        case .generic: return []
        }
    }

    /// Silent `/api/user/auth/refresh` is a new-api convention; other flavors
    /// fall back to the WebView relogin ladder.
    nonisolated var supportsAuthRefresh: Bool { self == .newAPI }

    /// Best-effort flavor guess from a public `/api/status` payload.
    /// Returns nil when the payload does not look like a NewAPI-family site.
    nonisolated static func detection(
        fromStatusData data: Data,
        statusCode: Int?
    ) -> (flavor: NewAPISiteFlavor, systemName: String?, version: String?)? {
        guard statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let success = (json["success"] as? Bool) == true || (json["code"] as? Int) == 0
        guard success, let values = json["data"] as? [String: Any] else { return nil }

        // one-api family status payloads expose a subset of these markers.
        let markers = ["version", "start_time", "system_name", "quota_per_unit"]
        guard markers.contains(where: { values[$0] != nil }) else { return nil }

        let version = stringValue(in: values, keys: ["version"])
        let systemName = stringValue(in: values, keys: ["system_name", "systemName"])
        var flavor = NewAPISiteFlavor.newAPI
        if let version {
            let lowered = version.lowercased()
            if lowered.contains("veloera") {
                flavor = .veloera
            } else if lowered.contains("done-hub") || lowered.contains("donehub") {
                flavor = .doneHub
            } else if lowered.contains("one-api") || lowered.contains("oneapi") {
                // one-api has no built-in check-in; treat as a generic endpoint.
                flavor = .generic
            }
        }
        return (flavor, systemName, version)
    }

    nonisolated private static func stringValue(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
            if let value = dict[key] as? Int { return String(value) }
        }
        return nil
    }
}
