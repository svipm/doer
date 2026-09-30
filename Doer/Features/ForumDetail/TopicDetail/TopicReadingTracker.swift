import UIKit

/// Whether the current moment still counts as reading time.
///
/// Mirrors Discourse's `screen-track`: that service stops accumulating once the
/// page has been untouched for three minutes (`PAUSE_UNLESS_SCROLLED`) and only
/// counts time while the session has focus. Without both gates a topic left open
/// on a stationary screen keeps accruing read time and POSTs a batch every flush
/// interval with nobody reading it.
enum TopicReadingCreditPolicy {
    static let idlePauseInterval: TimeInterval = 3 * 60

    static func shouldCreditTime(
        mode: ReadingTimingReportMode,
        now: Date,
        lastInteraction: Date,
        isAppActive: Bool
    ) -> Bool {
        guard mode != .off else { return false }
        guard isAppActive else { return false }
        return now.timeIntervalSince(lastInteraction) <= idlePauseInterval
    }
}

final class TopicReadingTracker {
    private let api: DiscourseAPI
    private var topicId: Int?
    private var visiblePostNumbers: Set<Int> = []
    private var pendingTimings: [Int: Int] = [:]
    private var pendingTopicTimeMilliseconds = 0
    private var timer: Timer?
    private var lastTickDate: Date?
    private var lastFlushDate = Date()
    private var lastInteractionDate = Date()
    private var isFlushInFlight = false
    private var lifecycleTokens: [NSObjectProtocol] = []
    /// A forced flush arrived while another was in flight; run it once the
    /// current one settles so the pending batch is not stranded.
    private var pendingFollowUpFlush = false

    /// Flush cadence follows the user's reporting policy: the web client's
    /// 60-second rhythm, or a merged batch every 30 minutes (fewer automated
    /// POSTs for Cloudflare to score). `.off` never flushes.
    private static func flushInterval(for mode: ReadingTimingReportMode) -> TimeInterval? {
        switch mode {
        case .realtime: return 60
        case .batched: return 30 * 60
        case .off: return nil
        }
    }

    init(api: DiscourseAPI) {
        self.api = api
    }

    func start(topicId: Int) {
        if self.topicId != topicId {
            pendingTimings.removeAll()
            pendingTopicTimeMilliseconds = 0
        }
        self.topicId = topicId
        lastTickDate = Date()
        lastFlushDate = Date()
        lastInteractionDate = Date()
        registerLifecycleObservers()
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTickDate = nil
        visiblePostNumbers.removeAll()
        unregisterLifecycleObservers()
        flush(force: true)
    }

    /// Leaving the foreground sends whatever accumulated — the system may suspend
    /// (then kill) the process, and in batched mode the pending window can hold up
    /// to 30 minutes of reading. Returning to the foreground counts as interaction,
    /// so reading a long post without scrolling still credits time.
    private func registerLifecycleObservers() {
        guard lifecycleTokens.isEmpty else { return }
        let center = NotificationCenter.default
        lifecycleTokens.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.flush(force: true)
                }
            }
        )
        lifecycleTokens.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.lastInteractionDate = Date()
                }
            }
        )
    }

    private func unregisterLifecycleObservers() {
        let center = NotificationCenter.default
        for token in lifecycleTokens {
            center.removeObserver(token)
        }
        lifecycleTokens.removeAll()
    }

    func setVisiblePostNumbers(_ postNumbers: Set<Int>) {
        visiblePostNumbers = postNumbers.filter { $0 > 0 }
        guard let topicId, let highest = visiblePostNumbers.max() else { return }
        let username = AuthManager.shared.username(for: api.baseURL)
        let before = TopicReadProgressStore.shared.highestSeen(
            topicId: topicId,
            baseURL: api.baseURL,
            username: username
        )
        TopicReadProgressStore.shared.record(
            topicId: topicId,
            highestSeen: highest,
            baseURL: api.baseURL,
            username: username
        )
        // Push list styling as the user scrolls, not only on 60s timings flush.
        if highest > before {
            NotificationCenter.default.post(
                name: .topicReadProgressDidChange,
                object: nil,
                userInfo: [
                    TopicReadProgressUserInfoKey.baseURL: api.baseURL,
                    TopicReadProgressUserInfoKey.topicId: topicId,
                    TopicReadProgressUserInfoKey.highestSeen: highest,
                ]
            )
        }
    }

    func scrolled() {
        lastInteractionDate = Date()
        tick()
    }

    private func tick() {
        let mode = AppSettings.shared.readingTimingReportMode
        let now = Date()
        // `.off` skips accumulation entirely — pending stays empty so no code path
        // can produce a timings POST. An idle or backgrounded page stops too, so a
        // topic left open does not report phantom reading. Either way the tick
        // clock stays fresh so resuming does not compute a stale elapsed.
        guard TopicReadingCreditPolicy.shouldCreditTime(
            mode: mode,
            now: now,
            lastInteraction: lastInteractionDate,
            isAppActive: UIApplication.shared.applicationState == .active
        ) else {
            lastTickDate = now
            return
        }
        let elapsedMilliseconds: Int
        if let lastTickDate {
            elapsedMilliseconds = min(max(Int(now.timeIntervalSince(lastTickDate) * 1000), 0), 2_000)
        } else {
            elapsedMilliseconds = 0
        }
        lastTickDate = now

        guard elapsedMilliseconds > 0, !visiblePostNumbers.isEmpty else { return }
        pendingTopicTimeMilliseconds += elapsedMilliseconds
        for postNumber in visiblePostNumbers {
            pendingTimings[postNumber, default: 0] += elapsedMilliseconds
        }

        if let interval = Self.flushInterval(for: mode),
           now.timeIntervalSince(lastFlushDate) >= interval {
            flush(force: false)
        }
    }

    private func flush(force: Bool) {
        guard AppSettings.shared.readingTimingReportMode != .off else { return }
        guard let topicId,
              pendingTopicTimeMilliseconds > 0,
              !pendingTimings.isEmpty
        else { return }
        if isFlushInFlight {
            // A forced flush (topic exit / background) must not be swallowed by
            // an in-flight one — the process can be suspended right after, and
            // in batched mode that pending window holds up to 30 minutes.
            if force { pendingFollowUpFlush = true }
            return
        }

        let topicTime = pendingTopicTimeMilliseconds
        let timings = pendingTimings
        pendingTopicTimeMilliseconds = 0
        pendingTimings.removeAll()
        lastFlushDate = Date()
        isFlushInFlight = true

        Task { [weak self, api, topicId, topicTime, timings] in
            let statusCode = await api.sendTopicTimings(
                topicId: topicId,
                topicTime: topicTime,
                timings: timings
            )
            await MainActor.run {
                guard let self else { return }
                self.isFlushInFlight = false

                // Local progress stays honest regardless of upload outcome.
                if let highestSeen = timings.keys.max() {
                    TopicReadProgressStore.shared.record(
                        topicId: topicId,
                        highestSeen: highestSeen,
                        baseURL: api.baseURL,
                        username: AuthManager.shared.username(for: api.baseURL)
                    )
                    NotificationCenter.default.post(
                        name: .topicReadProgressDidChange,
                        object: nil,
                        userInfo: [
                            TopicReadProgressUserInfoKey.baseURL: api.baseURL,
                            TopicReadProgressUserInfoKey.topicId: topicId,
                            TopicReadProgressUserInfoKey.highestSeen: highestSeen,
                        ]
                    )
                }

                if let statusCode, (200 ..< 300).contains(statusCode) {
                    // Uploaded.
                } else {
                    // Failed — including a nil status (no auth, CF cooldown,
                    // invalid params). Keep the batch so the next natural flush
                    // retries instead of silently dropping the accumulated
                    // reading window.
                    self.pendingTopicTimeMilliseconds += topicTime
                    for (postNumber, milliseconds) in timings {
                        self.pendingTimings[postNumber, default: 0] += milliseconds
                    }
                }

                if self.pendingFollowUpFlush {
                    self.pendingFollowUpFlush = false
                    if self.pendingTopicTimeMilliseconds > 0 {
                        self.flush(force: true)
                    }
                }
            }
        }
    }
}
