import UIKit
import WebKit

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
    /// Tiny on-screen host the challenge web view is parked in while minimized.
    private weak var hostView: UIView?

    /// Called whenever the minimized set changes so hosts can sync the shield.
    var onChange: (() -> Void)?

    private init() {}

    var isMinimized: Bool { minimizedController != nil }

    /// Minimize by parking the challenge's web view in a 2×2, nearly
    /// transparent host attached to the key window. Cloudflare's challenge JS
    /// checks visibility/focus, so simply dismissing the sheet (which takes the
    /// web view out of the window) would stop the challenge from ever passing.
    func minimize(_ controller: CloudflareVerificationViewController, webView: WKWebView) {
        minimizedController = controller
        releaseHostView()

        let host = UIView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        host.alpha = 0.01
        host.isUserInteractionEnabled = false
        host.clipsToBounds = true
        if let window = Self.keyWindow() {
            window.addSubview(host)
            host.center = CGPoint(x: window.bounds.midX, y: max(window.bounds.maxY - 2, 2))
        }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.frame = host.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(webView)
        hostView = host
        onChange?()
    }

    /// Hand the controller (and its web view) back for re-presentation.
    func takeForPresentation() -> CloudflareVerificationViewController? {
        guard let controller = minimizedController else { return nil }
        minimizedController = nil
        if let webView = hostView?.subviews.first as? WKWebView {
            controller.reattachWebViewAfterMinimization(webView)
        }
        releaseHostView()
        onChange?()
        return controller
    }

    /// Drop the off-screen reference after the challenge finished or gave up.
    func release(_ controller: CloudflareVerificationViewController) {
        guard minimizedController === controller else { return }
        minimizedController = nil
        releaseHostView()
        onChange?()
    }

    private func releaseHostView() {
        hostView?.subviews.forEach { $0.removeFromSuperview() }
        hostView?.removeFromSuperview()
        hostView = nil
    }

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
    }
}
