import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Dynamic Island / lock-screen companion for background Cloudflare
/// verification. Started when the challenge sheet is minimized, ended when it
/// passes or gives up. No-ops below iOS 16.2 or when Live Activities are off.
@MainActor
enum CloudflareVerificationLiveActivity {
    static func start() {
        guard #available(iOS 16.2, *) else { return }
        endReplacing()
        let attributes = CloudflareVerificationActivityAttributes(startedAt: Date())
        let state = CloudflareVerificationActivityAttributes.ContentState(
            statusText: String(
                localized: "cloudflare.activity.verifying",
                defaultValue: "正在通过 Cloudflare 验证…"
            )
        )
        // Goes stale alongside the minimized challenge's own 5-minute timeout.
        _ = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: Date().addingTimeInterval(5 * 60))
        )
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
        Task {
            for activity in Activity<CloudflareVerificationActivityAttributes>.activities {
                await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(10)))
            }
        }
    }

    private static func endReplacing() {
        guard #available(iOS 16.2, *) else { return }
        let content = ActivityContent<CloudflareVerificationActivityAttributes.ContentState>(
            state: .init(
                statusText: String(
                    localized: "cloudflare.activity.verifying",
                    defaultValue: "正在通过 Cloudflare 验证…"
                )
            ),
            staleDate: nil
        )
        Task {
            for activity in Activity<CloudflareVerificationActivityAttributes>.activities {
                await activity.end(content, dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
