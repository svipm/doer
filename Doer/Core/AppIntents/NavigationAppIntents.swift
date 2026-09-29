import AppIntents
import UIKit

/// Navigation shortcuts surfacing common destinations to the redesigned
/// Siri / Spotlight (iOS 27 routes App Intents through the new Siri
/// orchestrator; these compile and run on every iOS 16+ device). They reuse
/// the app's own deep-link routes, so navigation behavior matches in-app tabs.
@available(iOS 16.0, *)
struct OpenReadLaterIntent: AppIntent {
    static var title: LocalizedStringResource = "打开稍后读"
    static var description = IntentDescription("打开 Doer 的稍后读列表。")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await open(deepLink: "doer://read-later")
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "app_intent.read_later.done", defaultValue: "正在打开稍后读")))
    }
}

@available(iOS 16.0, *)
struct OpenNotificationsIntent: AppIntent {
    static var title: LocalizedStringResource = "打开通知"
    static var description = IntentDescription("打开 Doer 的通知列表。")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await open(deepLink: "doer://notifications")
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "app_intent.notifications.done", defaultValue: "正在打开通知")))
    }
}

@available(iOS 16.0, *)
@MainActor
private func open(deepLink: String) async {
    guard let url = URL(string: deepLink) else { return }
    _ = try? await UIApplication.shared.open(url)
}
