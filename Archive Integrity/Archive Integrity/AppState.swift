import Foundation
import Observation
import Engine
import ServiceManagement

@MainActor
@Observable
final class AppState {
    var volumes: [MonitoredVolume] = []
    var activeChecks: [UUID: CheckProgress] = [:]
    /// Set by the menu bar row so the Settings window can select the right volume when it opens.
    var pendingSettingsSelection: UUID?

    var launchAtLoginEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Registration failed (e.g. not yet installed in /Applications); the toggle
                // will just reflect the actual current status next time it's read.
            }
        }
    }

    struct CheckProgress: Sendable {
        var mode: CheckMode
        var message: String
        var task: Task<Void, Never>
    }

    enum CheckMode { case quick, deep }

    private var diskMonitor: DiskMonitor?
    private var scheduledCheckActivity: NSBackgroundActivityScheduler?

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

        // Covers archives that are always mounted (e.g. a folder on the internal disk),
        // which never generate a mount event after the first launch. Deliberately does NOT
        // catch up on app launch or wake-from-sleep — checks are CPU-heavy, and firing one at
        // whatever moment you happen to open your laptop would be exactly the wrong time.
        // Uses NSBackgroundActivityScheduler rather than a plain Timer so the OS's power
        // management picks the actual best moment within the tolerance window (batching with
        // other apps' scheduled wakeups, deferring under thermal/battery pressure) instead of
        // insisting on an exact tick every 15 minutes.
        let activity = NSBackgroundActivityScheduler(identifier: "com.archiveintegrity.scheduledcheck")
        activity.repeats = true
        activity.interval = 15 * 60
        activity.tolerance = 5 * 60
        activity.qualityOfService = .utility
        activity.schedule { [weak self] completion in
            Task { @MainActor in
                self?.runScheduledChecksIfDue()
                completion(.finished)
            }
        }
        scheduledCheckActivity = activity
    }

    // MARK: - Daily scheduled check

    private func runScheduledChecksIfDue() {
        let calendar = Calendar.current
        let now = Date()

        for volume in volumes {
            // Any time from the scheduled hour onward, not just within that exact hour — this
            // still never fires early, and never on wake/launch (see start()), but a Mac that's
            // asleep right at the scheduled hour will still catch up later the same day rather
            // than skipping it entirely. Each day is evaluated independently (see the "already
            // ran today" check below), so a late catch-up never shifts future days' schedule.
            guard calendar.component(.hour, from: now) >= volume.effectiveScheduledHour else { continue }
            // (Archives that aren't actually reachable right now, e.g. an unplugged external
            // drive, are skipped by runCheck itself before any state is touched.)

            // Quick and deep are gated independently — a quick check already having run today
            // (whether from this scheduler or a manual/mount-triggered check) has nothing to do
            // with whether a deep check is separately due; shouldAutoDeepCheck already has its
            // own interval-based due-check against deepCheckIntervalDays.
            // Uses lastQuickAttempt (set the instant a check starts) rather than lastQuickCheck
            // (only set on completion), so a cancelled attempt still counts as "already tried
            // today" instead of looking untouched and getting retried on the next tick.
            let quickReferenceDate = volume.lastQuickAttempt ?? volume.lastQuickCheck?.date
            let quickAlreadyRanToday = quickReferenceDate.map {
                calendar.isDate($0, inSameDayAs: now)
            } ?? false
            if !quickAlreadyRanToday {
                runCheck(volumeID: volume.id, mode: .quick)
            }
            if shouldAutoDeepCheck(volume) {
                runCheck(volumeID: volume.id, mode: .deep)
            }
        }
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

    func rebuildManifest(volumeID: UUID) {
        guard let idx = volumes.firstIndex(where: { $0.id == volumeID }) else { return }
        try? FileManager.default.removeItem(at: volumes[idx].manifestURL)
        volumes[idx].lastDeepCheck = nil
        volumes[idx].lastQuickCheck = nil
        save()
    }

    func removeFromManifest(volumeID: UUID, paths: Set<String>) {
        guard let idx = volumes.firstIndex(where: { $0.id == volumeID }) else { return }
        let volume = volumes[idx]
        guard var manifest = try? Manifest(url: volume.manifestURL) else { return }
        try? manifest.remove(paths)
        // Strip resolved paths from recorded issues so the UI updates immediately.
        if var record = volumes[idx].lastDeepCheck {
            record.issues = record.issues.filter { issue in
                !paths.contains(where: { issue.contains($0) })
            }
            volumes[idx].lastDeepCheck = record
        }
        if var record = volumes[idx].lastQuickCheck {
            record.issues = record.issues.filter { issue in
                !paths.contains(where: { issue.contains($0) })
            }
            volumes[idx].lastQuickCheck = record
        }
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

    /// Whether a deep check is due, by calendar date rather than exact elapsed seconds — due on
    /// the date `deepCheckIntervalDays` days after the last deep check's date, as soon as today's
    /// date reaches that day (not tied to what time of day the last check happened to finish at).
    /// Requires at least one deep check to have ever *completed* (that's the real baseline check),
    /// but measures the interval from whichever is more recent, completion or attempt, so a
    /// cancelled/incomplete attempt today still pushes the next due date out instead of leaving
    /// it looking untouched and getting retried on the next tick.
    private func shouldAutoDeepCheck(_ volume: MonitoredVolume) -> Bool {
        guard let last = volume.lastDeepCheck else { return false }
        let calendar = Calendar.current
        let referenceDate = max(last.date, volume.lastDeepAttempt ?? .distantPast)
        guard let dueDate = calendar.date(
            byAdding: .day, value: volume.deepCheckIntervalDays, to: calendar.startOfDay(for: referenceDate)
        ) else { return false }
        return calendar.startOfDay(for: Date()) >= dueDate
    }

    // MARK: - Running checks

    func runCheck(volumeID: UUID, mode: CheckMode) {
        guard let volume = volumes.first(where: { $0.id == volumeID }),
              activeChecks[volumeID] == nil else { return }
        // Bail out before touching any state (in particular lastQuickAttempt/lastDeepAttempt)
        // if the archive isn't actually reachable (e.g. an unplugged external drive). Otherwise
        // the tree walker fails instantly, but the attempt timestamp already stamped by
        // performCheck would still push the next scheduled deep check out by a full interval,
        // even though nothing was actually verified.
        guard FileManager.default.fileExists(atPath: volume.archivePath) else {
            Task {
                await NotificationManager.shared.postUnreachable(
                    volumeID: volume.id, volumeName: volume.displayName,
                    checkType: mode == .quick ? "Quick" : "Deep")
            }
            return
        }
        // Run at .utility priority so the scheduler yields CPU to whatever you're actively doing
        // instead of a check competing evenly with foreground work.
        let task = Task(priority: .utility) { await performCheck(volume: volume, mode: mode) }
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
        let startTime = Date()
        switch mode {
        case .quick: volumes[idx].lastQuickAttempt = startTime
        case .deep:  volumes[idx].lastDeepAttempt = startTime
        }

        do {
            var manifest = try Manifest(url: volume.manifestURL)
            let verifier = Verifier(concurrency: volume.concurrency)

            switch mode {
            case .quick:
                let result = try verifier.quickCheck(root: volume.archiveURL, manifest: manifest)
                let issues = result.missing.map { "MISSING: \($0.sanitizedForDisplay())" }
                volumes[idx].lastQuickCheck = .init(
                    date: Date(), outcome: result.isClean ? .clean : .failed,
                    fileCount: result.liveCount, issues: issues,
                    duration: Date().timeIntervalSince(startTime))
                if !result.isClean {
                    await NotificationManager.shared.postFailure(
                        volumeID: volume.id, volumeName: volume.displayName, checkType: "Quick", issues: issues)
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
                            self?.activeChecks[volume.id]?.message = "[\(index)/\(total)] \(path.sanitizedForDisplay())"
                        }
                    }
                }

                var issues: [String] = []
                issues += result.corrupted.map { "MODIFIED: \($0.path.sanitizedForDisplay())" }
                issues += result.missing.map  { "MISSING: \($0.sanitizedForDisplay())" }

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
                } else {
                    await NotificationManager.shared.postFailure(
                        volumeID: volume.id, volumeName: volume.displayName, checkType: "Deep", issues: issues)
                }

                // Always record the result so the UI always updates.
                volumes[idx].lastDeepCheck = .init(
                    date: Date(),
                    outcome: result.isClean ? .clean : .failed,
                    fileCount: liveCount,
                    issues: issues,
                    duration: Date().timeIntervalSince(startTime))
            }
        } catch {
            // Manifest unreadable — leave state unchanged
        }
    }
}
