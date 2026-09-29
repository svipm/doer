import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Drives the Dynamic Island / lock-screen Live Activity while a NewAPI batch
/// check-in runs. No-ops below iOS 16.2, when Live Activities are disabled, or
/// when the request cannot start (e.g. background start without entitlement).
@MainActor
enum NewAPICheckInLiveActivity {
    static var isSupported: Bool {
        if #available(iOS 16.2, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    static func start(total: Int) {
        guard #available(iOS 16.2, *) else { return }
        guard isSupported, total > 0 else { return }
        // One batch at a time — end any stale activity from a previous run.
        end(completed: 0, succeeded: 0, alreadySigned: 0, failed: 0)
        let attributes = NewAPICheckInActivityAttributes(total: total, startedAt: Date())
        let state = NewAPICheckInActivityAttributes.ContentState(
            completed: 0,
            succeeded: 0,
            alreadySigned: 0,
            failed: 0
        )
        _ = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil)
        )
    }

    static func update(
        completed: Int,
        succeeded: Int,
        alreadySigned: Int,
        failed: Int
    ) {
        guard #available(iOS 16.2, *) else { return }
        let content = ActivityContent(
            state: .init(
                completed: completed,
                succeeded: succeeded,
                alreadySigned: alreadySigned,
                failed: failed
            ),
            staleDate: nil
        )
        Task {
            for activity in Activity<NewAPICheckInActivityAttributes>.activities {
                await activity.update(content)
            }
        }
    }

    static func end(
        completed: Int,
        succeeded: Int,
        alreadySigned: Int,
        failed: Int
    ) {
        guard #available(iOS 16.2, *) else { return }
        let content = ActivityContent(
            state: .init(
                completed: completed,
                succeeded: succeeded,
                alreadySigned: alreadySigned,
                failed: failed
            ),
            staleDate: nil
        )
        Task {
            for activity in Activity<NewAPICheckInActivityAttributes>.activities {
                await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(20)))
            }
        }
    }
}
#endif
