import UIKit

/// Keeps a minimized Cloudflare challenge alive off-screen.
///
/// Minimizing dismisses the sheet so the user can keep browsing, but the
/// challenge web view keeps loading and the clearance polling keeps running.
/// When the challenge passes, the normal completion notification fires and the
/// controller is released; tapping the shield re-presents the same controller
/// instead of starting a second challenge.
@MainActor
final class CloudflareChallengeMinimizer {
    static let shared = CloudflareChallengeMinimizer()

    private(set) var minimizedController: CloudflareVerificationViewController?

    /// Called whenever the minimized set changes so hosts can sync the shield.
    var onChange: (() -> Void)?

    private init() {}

    var isMinimized: Bool { minimizedController != nil }

    func minimize(_ controller: CloudflareVerificationViewController) {
        minimizedController = controller
        onChange?()
    }

    /// Hand the controller back for re-presentation (clears the slot).
    func takeForPresentation() -> CloudflareVerificationViewController? {
        let controller = minimizedController
        minimizedController = nil
        onChange?()
        return controller
    }

    /// Drop the off-screen reference after the challenge finished or gave up.
    func release(_ controller: CloudflareVerificationViewController) {
        guard minimizedController === controller else { return }
        minimizedController = nil
        onChange?()
    }
}
