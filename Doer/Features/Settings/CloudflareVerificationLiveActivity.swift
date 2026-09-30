import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Dynamic Island / lock-screen companion for background Cloudflare
/// verification. Started when the challenge sheet is minimized, ended when it
/// passes or gives up. No-ops below iOS 16.2 or when Live Activities are off.
@MainActor
enum CloudflareVerificationLiveActivity {
    @available(iOS 16.2, *)
    private static var current: Activity<CloudflareVerificationActivityAttributes>?

    static func start() {
        guard #available(iOS 16.2, *) else { return }
        // Snapshot before requesting. Reading `.activities` inside a Task used to
        // run after `Activity.request` returned, so the loop ended the activity it
        // had just created and nothing ever appeared on the Dynamic Island.
        let previous = Activity<CloudflareVerificationActivityAttributes>.activities
        let attributes = CloudflareVerificationActivityAttributes(startedAt: Date())
        let state = CloudflareVerificationActivityAttributes.ContentState(
            statusText: String(
                localized: "cloudflare.activity.verifying",
                defaultValue: "正在通过 Cloudflare 验证…"
            )
        )
        // Goes stale alongside the minimized challenge's own 5-minute timeout.
        let activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: Date().addingTimeInterval(5 * 60))
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

    static func end(passed: Bool) {
        guard #available(iOS 16.2, *) else { return }
        let statusText = passed
            ? String(localized: "cloudflare.activity.passed", defaultValue: "验证通过，可以继续操作")
            : String(localized: "cloudflare.activity.failed", defaultValue: "验证未完成，可点盾牌重试")
        let content = ActivityContent<CloudflareVerificationActivityAttributes.ContentState>(
            state: .init(statusText: statusText),
            staleDate: nil
        )
        let tracked = current
        current = nil
        Task {
            // End the card this facade owns. With no tracked card — a fresh
            // process after a kill, or a repeat call — clear whatever is left
            // over so a stale entry cannot stay on the lock screen.
            if let tracked {
                await tracked.end(content, dismissalPolicy: .after(Date().addingTimeInterval(10)))
            } else {
                for leftover in Activity<CloudflareVerificationActivityAttributes>.activities {
                    await leftover.end(content, dismissalPolicy: .after(Date().addingTimeInterval(10)))
                }
            }
        }
    }
    /// Clear a card left behind by a process that was killed while a challenge was
    /// minimized. Safe at launch: no challenge can be running yet.
    static func endStrandedActivities() {
        guard #available(iOS 16.2, *) else { return }
        let stranded = Activity<CloudflareVerificationActivityAttributes>.activities
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
