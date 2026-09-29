import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Batch NewAPI check-in progress, shared between the app (producer) and the
/// DoerWidget extension (Dynamic Island / lock-screen presentation).
/// ActivityKit itself is iOS 16.1+; the app target gates all runtime use.
@available(iOS 16.1, *)
struct NewAPICheckInActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Sites finished = succeeded + alreadySigned + failed.
        var completed: Int
        var succeeded: Int
        var alreadySigned: Int
        var failed: Int
    }

    var total: Int
    var startedAt: Date
}
#endif
