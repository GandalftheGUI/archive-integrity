import Foundation
import Observation
import Engine

@MainActor
@Observable
final class AppState {
    var volumes: [MonitoredVolume] = []
    var activeChecks: [UUID: CheckProgress] = [:]

    struct CheckProgress: Sendable {
        var mode: CheckMode
        var message: String
        var task: Task<Void, Never>
    }

    enum CheckMode { case quick, deep }

    private var diskMonitor: DiskMonitor?

    private var configURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Archive Integrity/volumes.json")
    }

    var menuBarIcon: String {
        if !activeChecks.isEmpty { return "arrow.clockwise.circle" }
        if volumes.contains(where: { $0.overallStatus == .failed }) {
            return "exclamationmark.shield.fill"
        }
        return volumes.isEmpty ? "shield" : "checkmark.shield.fill"
    }

    // MARK: - Lifecycle

    init() { load() }

    func start() {
        guard diskMonitor == nil else { return }
        let monitor = DiskMonitor()
        monitor.onVolumeAppeared = { @Sendable [weak self] path, uuid in
            Task { @MainActor [weak self] in
                self?.volumeMounted(atPath: path, uuid: uuid)
            }
        }
        monitor.start()
        diskMonitor = monitor
        Task { await NotificationManager.shared.requestPermission() }
    }

    // MARK: - Persistence

    func save() {
        let dir = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(volumes) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? JSONDecoder().decode([MonitoredVolume].self, from: data)
        else { return }
        volumes = decoded
    }

    // MARK: - Volume management

    func addVolume(_ volume: MonitoredVolume) {
        volumes.append(volume)
        save()
    }

    func removeVolume(id: UUID) {
        volumes.removeAll { $0.id == id }
        save()
    }

    // MARK: - Mount events

    func volumeMounted(atPath mountPath: String, uuid: String?) {
        for volume in volumes {
            let pathMatch = volume.archivePath.hasPrefix(mountPath)
            let uuidMatch = uuid != nil && uuid == volume.volumeUUID
            guard pathMatch || uuidMatch else { continue }
            runCheck(volumeID: volume.id, mode: .quick)
            // Only auto-deep-check after the first manual deep check has been run.
            // Prevents kicking off a hours-long initial hash on every mount.
            if shouldAutoDeepCheck(volume) {
                runCheck(volumeID: volume.id, mode: .deep)
            }
        }
    }

    private func shouldAutoDeepCheck(_ volume: MonitoredVolume) -> Bool {
        guard let last = volume.lastDeepCheck else { return false }
        return Date().timeIntervalSince(last.date) >= Double(volume.deepCheckIntervalDays * 86_400)
    }

    // MARK: - Running checks

    func runCheck(volumeID: UUID, mode: CheckMode) {
        guard let volume = volumes.first(where: { $0.id == volumeID }),
              activeChecks[volumeID] == nil else { return }
        let task = Task { await performCheck(volume: volume, mode: mode) }
        activeChecks[volumeID] = CheckProgress(
            mode: mode,
            message: mode == .quick ? "Quick check…" : "Deep check…",
            task: task
        )
    }

    func cancelCheck(volumeID: UUID) {
        activeChecks[volumeID]?.task.cancel()
        activeChecks.removeValue(forKey: volumeID)
    }

    // MARK: - Check execution

    private func performCheck(volume: MonitoredVolume, mode: CheckMode) async {
        defer {
            activeChecks.removeValue(forKey: volume.id)
            save()
        }

        guard let idx = volumes.firstIndex(where: { $0.id == volume.id }) else { return }

        do {
            var manifest = try Manifest(url: volume.manifestURL)
            let verifier = Verifier()

            switch mode {
            case .quick:
                let result = try verifier.quickCheck(root: volume.archiveURL, manifest: manifest)
                let issues = result.isClean ? [] :
                    ["\(result.missingFiles) file(s) missing from manifest count"]
                volumes[idx].lastQuickCheck = .init(
                    date: Date(), outcome: result.isClean ? .clean : .failed,
                    fileCount: result.liveCount, issues: issues)
                if !result.isClean {
                    FailureMarker.write(to: volume.archiveURL, volumeName: volume.displayName)
                    await NotificationManager.shared.postFailure(
                        volumeName: volume.displayName, issues: issues)
                }

            case .deep:
                // Ensure manifest directory exists before the first write attempt.
                let manifestDir = volume.manifestURL.deletingLastPathComponent()
                try? FileManager.default.createDirectory(
                    at: manifestDir, withIntermediateDirectories: true)

                let result = try await verifier.deepCheck(
                    root: volume.archiveURL,
                    manifest: manifest
                ) { [weak self] event in
                    if case .hashing(let path, let index, let total) = event {
                        Task { @MainActor [weak self] in
                            self?.activeChecks[volume.id]?.message = "[\(index)/\(total)] \(path)"
                        }
                    }
                }

                var issues: [String] = []
                issues += result.corrupted.map { "CORRUPTED: \($0.path)" }
                issues += result.missing.map  { "MISSING: \($0)" }

                // Total live files — valid regardless of whether manifest write succeeds.
                let liveCount = result.totalChecked + result.new.count

                if result.isClean {
                    if !result.new.isEmpty {
                        do {
                            try manifest.append(result.new)
                            issues.append("NEW:\(result.new.count)")
                        } catch {
                            issues.append("ERR: manifest write failed – \(error.localizedDescription)")
                        }
                    }
                    FailureMarker.clear(from: volume.archiveURL)
                } else {
                    FailureMarker.write(to: volume.archiveURL, volumeName: volume.displayName)
                    await NotificationManager.shared.postFailure(
                        volumeName: volume.displayName, issues: issues)
                }

                // Always record the result so the UI always updates.
                volumes[idx].lastDeepCheck = .init(
                    date: Date(),
                    outcome: result.isClean ? .clean : .failed,
                    fileCount: liveCount,
                    issues: issues)
            }
        } catch {
            // Manifest unreadable — leave state unchanged
        }
    }
}
