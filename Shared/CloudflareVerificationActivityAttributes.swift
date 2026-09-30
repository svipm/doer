import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Cloudflare verification progress, shared between the app (producer) and
/// the DoerWidget extension (Dynamic Island / lock-screen presentation).
/// Started when a challenge is minimized (background verification), ended
/// when it passes or gives up. iOS 16.2+ (ActivityContent API cluster).
@available(iOS 16.2, *)
struct CloudflareVerificationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Human-readable status, localized by the app when updating.
        var statusText: String
    }

    var startedAt: Date
}
#endif
