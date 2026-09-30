import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Drives the Dynamic Island / lock-screen Live Activity while a NewAPI batch
/// check-in runs. No-ops below iOS 16.2, when Live Activities are disabled, or
/// when the request cannot start (e.g. background start without entitlement).
@MainActor
enum NewAPICheckInLiveActivity {
    /// How long a card may stay on screen without an update. A batch finishes in
    /// seconds to a couple of minutes, so anything older is a stranded card from a
    /// process that was killed mid-run (the system does not remove those for us).
    private static let staleness: TimeInterval = 10 * 60

    @available(iOS 16.2, *)
    private static var current: Activity<NewAPICheckInActivityAttributes>?

    static var isSupported: Bool {
        if #available(iOS 16.2, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    static func start(total: Int) {
        guard #available(iOS 16.2, *) else { return }
        guard isSupported, total > 0 else { return }
        // Snapshot first: reading `.activities` inside a Task runs after
        // `Activity.request` returned, so a bare "end everything" pass ended the
        // activity it had just created — the card froze at 0/N and vanished.
        let previous = Activity<NewAPICheckInActivityAttributes>.activities
        let attributes = NewAPICheckInActivityAttributes(total: total, startedAt: Date())
        let state = NewAPICheckInActivityAttributes.ContentState(
            completed: 0,
            succeeded: 0,
            alreadySigned: 0,
            failed: 0
        )
        let activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: Date().addingTimeInterval(staleness))
        )
        current = activity
        guard !previous.isEmpty else { return }
        let currentId = activity?.id
        Task {
            for old in previous where old.id != currentId {
                await old.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    static func update(
        completed: Int,
        succeeded: Int,
        alreadySigned: Int,
        failed: Int
    ) {
        guard #available(iOS 16.2, *) else { return }
        // Explicit generic parameter: a bare `ActivityContent(state:staleDate:)`
        // local has no context to infer the state type from.
        let content = ActivityContent<NewAPICheckInActivityAttributes.ContentState>(
            state: NewAPICheckInActivityAttributes.ContentState(
                completed: completed,
                succeeded: succeeded,
                alreadySigned: alreadySigned,
                failed: failed
            ),
            staleDate: Date().addingTimeInterval(staleness)
        )
        let tracked = current
        Task {
            if let tracked {
                await tracked.update(content)
            } else {
                for activity in Activity<NewAPICheckInActivityAttributes>.activities {
                    await activity.update(content)
                }
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
        let content = ActivityContent<NewAPICheckInActivityAttributes.ContentState>(
            state: NewAPICheckInActivityAttributes.ContentState(
                completed: completed,
                succeeded: succeeded,
                alreadySigned: alreadySigned,
                failed: failed
            ),
            staleDate: nil
        )
        let tracked = current
        current = nil
        Task {
            if let tracked {
                await tracked.end(content, dismissalPolicy: .after(Date().addingTimeInterval(20)))
            } else {
                for activity in Activity<NewAPICheckInActivityAttributes>.activities {
                    await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(20)))
                }
            }
        }
    }

    /// Clear cards left behind by a process that was killed mid-batch. Safe on a
    /// fresh launch: no batch can be running yet, so anything still listed is stale.
    static func endStrandedActivities() {
        guard #available(iOS 16.2, *) else { return }
        let stranded = Activity<NewAPICheckInActivityAttributes>.activities
        current = nil
        guard !stranded.isEmpty else { return }
        Task {
            for activity in stranded {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
