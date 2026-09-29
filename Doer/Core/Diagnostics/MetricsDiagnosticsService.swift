import Foundation
import MetricKit

/// MetricKit subscriber for crash / hang / launch diagnostics.
///
/// iOS 27 rebuilt MetricKit as a Swift-first engine with daily delivery; the
/// subscription surface here is the long-stable `MXMetricManager` API, so this
/// compiles and runs on every supported OS version and automatically rides the
/// rebuilt engine on iOS 27+. Payloads land in the DohDebugLog ring buffer and
/// as capped JSON files under Application Support/Doer/Diagnostics/.
final class MetricsDiagnosticsService: NSObject {
    static let shared = MetricsDiagnosticsService()

    private var isRegistered = false
    private let fileLock = NSLock()
    private static let maxFilesPerKind = 10

    private override init() {
        super.init()
    }

    func start() {
        guard !isRegistered else { return }
        isRegistered = true
        MXMetricManager.shared.add(self)
    }

    private nonisolated func diagnosticsDirectory() -> URL? {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Doer/Diagnostics", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }

    private nonisolated func store(json: Data, kind: String) {
        fileLock.lock()
        defer { fileLock.unlock() }
        guard let dir = diagnosticsDirectory() else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("\(kind)-\(stamp).json")
        try? json.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

        // Keep only the newest files per kind so the folder stays bounded.
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let kindFiles = contents
            .filter { $0.lastPathComponent.hasPrefix("\(kind)-") && $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
        for old in kindFiles.dropFirst(Self.maxFilesPerKind) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    private nonisolated func summaryLine(for payload: MXDiagnosticPayload) -> String? {
        let crashes = payload.crashDiagnostics?.count ?? 0
        let hangs = payload.hangDiagnostics?.count ?? 0
        let cpu = payload.cpuExceptionDiagnostics?.count ?? 0
        let disk = payload.diskWriteExceptionDiagnostics?.count ?? 0
        guard crashes > 0 || hangs > 0 || cpu > 0 || disk > 0 else { return nil }
        return "diagnostics: crashes=\(crashes) hangs=\(hangs) cpuExceptions=\(cpu) diskExceptions=\(disk)"
    }
}

extension MetricsDiagnosticsService: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            store(json: payload.jsonRepresentation(), kind: "diagnostic")
            if let line = summaryLine(for: payload) {
                DohDebugLog.record(line, subsystem: "Metrics")
            }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            store(json: payload.jsonRepresentation(), kind: "metric")
            DohDebugLog.record("daily metrics payload stored", subsystem: "Metrics")
        }
    }
}
