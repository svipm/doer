import Foundation

/// Detects NewAPI-family relay sites from their public `/api/status` payload.
/// The in-app browser calls this on navigation; results are cached per host
/// so each site is probed at most once per cache lifetime.
actor NewAPISiteDetector {
    static let shared = NewAPISiteDetector()

    struct Detection: Equatable, Sendable {
        let origin: URL
        let flavor: NewAPISiteFlavor
        let systemName: String?
        let version: String?
    }

    private struct CacheEntry: Codable {
        var flavor: String?
        var systemName: String?
        var version: String?
        var isSite: Bool
        var checkedAt: Date
        /// The last probe never reached the host. Kept briefly so a burst of
        /// navigations while offline does not re-probe every time.
        var unreachable: Bool?
    }

    /// What a probe learned. "Not a NewAPI relay" and "could not reach the host"
    /// must stay distinct: caching the latter hid a site for a whole week.
    enum ProbeOutcome: Equatable, Sendable {
        case site(Detection)
        case notASite
        case unreachable
    }

    private static let defaultsKey = "plugin.newapi.site_detection.v1"
    /// Cache lifetime for both positive and negative results. One week keeps
    /// repeated visits from hammering unrelated domains.
    private static let cacheLifetime: TimeInterval = 7 * 24 * 60 * 60
    /// An unreachable host is only remembered this long, so recovery is quick.
    private static let unreachableRetryInterval: TimeInterval = 2 * 60
    /// One entry per host the in-app browser ever visited would grow without bound.
    private static let maximumEntries = 64

    private let defaults: UserDefaults
    private let session: URLSession
    private var cache: [String: CacheEntry]

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    /// Returns the detection for this origin, or nil when the site does not
    /// look like a NewAPI-family relay (or the probe failed).
    func detect(origin: URL, force: Bool = false) async -> Detection? {
        guard let host = Self.cacheKey(for: origin) else { return nil }
        if !force, let entry = cache[host] {
            let lifetime = entry.unreachable == true
                ? Self.unreachableRetryInterval
                : Self.cacheLifetime
            if Date().timeIntervalSince(entry.checkedAt) < lifetime {
                return Self.detection(from: entry, origin: origin)
            }
        }

        switch await Self.probe(origin: origin, session: session) {
        case .unreachable:
            // Not evidence about the host — remember it only briefly.
            cache[host] = CacheEntry(
                flavor: nil,
                systemName: nil,
                version: nil,
                isSite: false,
                checkedAt: Date(),
                unreachable: true
            )
            persist()
            return nil
        case .notASite:
            cache[host] = CacheEntry(
                flavor: nil,
                systemName: nil,
                version: nil,
                isSite: false,
                checkedAt: Date(),
                unreachable: false
            )
            persist()
            return nil
        case .site(let detection):
            cache[host] = CacheEntry(
                flavor: detection.flavor.rawValue,
                systemName: detection.systemName,
                version: detection.version,
                isSite: true,
                checkedAt: Date(),
                unreachable: false
            )
            persist()
            return detection
        }
    }

    /// Host plus port: a self-hosted deployment on the same host as something else
    /// (`localhost:3000` vs `localhost:8080`) must not share one verdict.
    nonisolated private static func cacheKey(for origin: URL) -> String? {
        guard let host = origin.host?.lowercased(), !host.isEmpty else { return nil }
        guard let port = origin.port else { return host }
        return "\(host):\(port)"
    }

    private func persist() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.checkedAt) < Self.cacheLifetime }
        if cache.count > Self.maximumEntries {
            let recent = cache.sorted { $0.value.checkedAt > $1.value.checkedAt }
                .prefix(Self.maximumEntries)
            cache = Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    nonisolated private static func detection(from entry: CacheEntry, origin: URL) -> Detection? {
        guard entry.isSite, let raw = entry.flavor, let flavor = NewAPISiteFlavor(rawValue: raw) else {
            return nil
        }
        return Detection(origin: origin, flavor: flavor, systemName: entry.systemName, version: entry.version)
    }

    nonisolated static func probe(origin: URL, session: URLSession) async -> ProbeOutcome {
        guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
            return .unreachable
        }
        components.path = NewAPISiteFlavor.newAPI.statusPath
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { return .unreachable }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(NewAPISiteFlavor.defaultUserAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request) else {
            return .unreachable
        }
        guard let parsed = NewAPISiteFlavor.detection(
            fromStatusData: data,
            statusCode: (response as? HTTPURLResponse)?.statusCode
        ) else {
            return .notASite
        }
        return .site(
            Detection(
                origin: origin,
                flavor: parsed.flavor,
                systemName: parsed.systemName,
                version: parsed.version
            )
        )
    }
}
