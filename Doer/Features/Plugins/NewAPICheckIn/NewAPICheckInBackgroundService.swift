import BackgroundTasks
import Foundation

enum NewAPICheckInBackgroundPolicy {
    static let taskIdentifier = "com.naine.doer.newapiCheckIn"
    private static let firstRunDelay: TimeInterval = 60 * 60
    /// Check-in is a daily job. iOS only grants a few BGAppRefresh slots per
    /// day (notification sync competes for the same budget), so ask for the
    /// next slot a full day out and never earlier than an hour from now.
    private static let interRunDelay: TimeInterval = 26 * 60 * 60

    static func earliestBeginDate(lastRun: Date?, now: Date = Date()) -> Date {
        guard let lastRun else {
            return now.addingTimeInterval(firstRunDelay)
        }
        return max(now.addingTimeInterval(firstRunDelay), lastRun.addingTimeInterval(interRunDelay))
    }
}

/// BGAppRefresh-driven daily check-in. The system wakes the app when budget
/// allows; the run is strictly background-safe (no interactive relogin —
/// `signInAll` skips platforms that would need one and records them as
/// `authenticationExpired`).
@MainActor
final class NewAPICheckInBackgroundService {
    static let shared = NewAPICheckInBackgroundService()

    private static let lastRunKey = "plugin.newapi.auto_checkin.last_run"

    private let scheduler = BGTaskScheduler.shared
    private var isRegistered = false
    private var activeWork: Task<Bool, Never>?

    private init() {}

    static var lastRunDate: Date? {
        get { UserDefaults.standard.object(forKey: lastRunKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastRunKey) }
    }

    func register() {
        guard !isRegistered else { return }
        isRegistered = scheduler.register(
            forTaskWithIdentifier: NewAPICheckInBackgroundPolicy.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                NewAPICheckInBackgroundService.shared.handle(refreshTask)
            }
        }
    }

    /// (Re)submits the background request. No-op when the user has not opted
    /// in; also safe to call repeatedly (it cancels the previous request).
    func scheduleNextRun() {
        guard isRegistered else { return }
        guard NewAPICheckInRuntime.autoCheckInEnabled else {
            scheduler.cancel(taskRequestWithIdentifier: NewAPICheckInBackgroundPolicy.taskIdentifier)
            return
        }
        scheduler.cancel(taskRequestWithIdentifier: NewAPICheckInBackgroundPolicy.taskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: NewAPICheckInBackgroundPolicy.taskIdentifier)
        request.earliestBeginDate = NewAPICheckInBackgroundPolicy.earliestBeginDate(
            lastRun: Self.lastRunDate
        )
        try? scheduler.submit(request)
    }

    private func handle(_ systemTask: BGAppRefreshTask) {
        Self.lastRunDate = Date()
        scheduleNextRun()

        guard activeWork == nil else {
            systemTask.setTaskCompleted(success: false)
            return
        }

        let work: Task<Bool, Never> = Task { @MainActor in
            guard NewAPICheckInRuntime.autoCheckInEnabled else { return false }
            let platforms = await NewAPICheckInRuntime.shared.store.platforms()
            guard !platforms.isEmpty else { return false }
            _ = await NewAPICheckInRuntime.shared.service.signInAll()
            return true
        }
        activeWork = work

        systemTask.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.activeWork?.cancel()
            }
        }

        Task { @MainActor [weak self] in
            _ = await work.value
            self?.activeWork = nil
            systemTask.setTaskCompleted(success: !work.isCancelled)
        }
    }
}
