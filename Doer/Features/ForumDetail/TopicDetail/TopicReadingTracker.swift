import UIKit

final class TopicReadingTracker {
    private let api: DiscourseAPI
    private var topicId: Int?
    private var visiblePostNumbers: Set<Int> = []
    private var pendingTimings: [Int: Int] = [:]
    private var pendingTopicTimeMilliseconds = 0
    private var timer: Timer?
    private var lastTickDate: Date?
    private var lastFlushDate = Date()
    private var isFlushInFlight = false
    private var backgroundFlushToken: NSObjectProtocol?

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
        registerBackgroundFlush()
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
        unregisterBackgroundFlush()
        flush(force: true)
    }

    /// Send whatever accumulated when the app leaves the foreground — the
    /// system may suspend (then kill) the process, and in batched mode the
    /// pending window can hold up to 30 minutes of reading.
    private func registerBackgroundFlush() {
        guard backgroundFlushToken == nil else { return }
        backgroundFlushToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.flush(force: true)
            }
        }
    }

    private func unregisterBackgroundFlush() {
        guard let backgroundFlushToken else { return }
        NotificationCenter.default.removeObserver(backgroundFlushToken)
        self.backgroundFlushToken = nil
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
        tick()
    }

    private func tick() {
        let mode = AppSettings.shared.readingTimingReportMode
        // `.off` also skips accumulation entirely — pending stays empty so no
        // code path can produce a timings POST.
        guard mode != .off else { return }
        let now = Date()
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
        guard !isFlushInFlight,
              let topicId,
              pendingTopicTimeMilliseconds > 0,
              !pendingTimings.isEmpty
        else { return }

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
                if let statusCode,
                   (200 ..< 300).contains(statusCode),
                   let highestSeen = timings.keys.max() {
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
                } else if let highestSeen = timings.keys.max() {
                    // Even if timings upload fails, keep local progress so list/resume stay honest.
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
                guard !force,
                      let statusCode,
                      !(200 ..< 300).contains(statusCode)
                else { return }
                self.pendingTopicTimeMilliseconds += topicTime
                for (postNumber, milliseconds) in timings {
                    self.pendingTimings[postNumber, default: 0] += milliseconds
                }
            }
        }
    }
}
