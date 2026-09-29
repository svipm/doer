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
    }

    private static let defaultsKey = "plugin.newapi.site_detection.v1"
    /// Cache lifetime for both positive and negative results. One week keeps
    /// repeated visits from hammering unrelated domains.
    private static let cacheLifetime: TimeInterval = 7 * 24 * 60 * 60

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
        guard let host = origin.host?.lowercased(), !host.isEmpty else { return nil }
        if !force,
           let entry = cache[host],
           Date().timeIntervalSince(entry.checkedAt) < Self.cacheLifetime {
            return Self.detection(from: entry, origin: origin)
        }

        let detection = await Self.probe(origin: origin, session: session)
        let entry = CacheEntry(
            flavor: detection?.flavor.rawValue,
            systemName: detection?.systemName,
            version: detection?.version,
            isSite: detection != nil,
            checkedAt: Date()
        )
        cache[host] = entry
        persist()
        return detection
    }

    private func persist() {
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

    nonisolated static func probe(origin: URL, session: URLSession) async -> Detection? {
        guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = NewAPISiteFlavor.newAPI.statusPath
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(NewAPISiteFlavor.defaultUserAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request) else {
            return nil
        }
        return NewAPISiteFlavor.detection(
            fromStatusData: data,
            statusCode: (response as? HTTPURLResponse)?.statusCode
        )
        .map { Detection(origin: origin, flavor: $0.flavor, systemName: $0.systemName, version: $0.version) }
    }
}
