import Foundation

struct MonitoredVolume: Identifiable, Codable, Sendable {
    static let defaultDeepCheckIntervalDays = 7
    static let defaultScheduledHour = 3

    var id: UUID = UUID()
    var displayName: String
    var archivePath: String
    var manifestPath: String
    var volumeUUID: String?          // populated for external drives; nil for local dirs
    var deepCheckIntervalDays: Int = MonitoredVolume.defaultDeepCheckIntervalDays
    /// Concurrent files hashed in parallel during deep check. 1 = sequential (HDD-safe), 4–8 for SSDs.
    var concurrency: Int = 1
    /// Hour of day (local time, 0–23) this volume's daily scheduled check runs at, if due.
    /// Optional only so volumes persisted before this field existed still decode; use
    /// `effectiveScheduledHour` rather than reading this directly.
    var scheduledHour: Int?

    var effectiveScheduledHour: Int { scheduledHour ?? Self.defaultScheduledHour }

    var lastQuickCheck: CheckRecord?
    var lastDeepCheck: CheckRecord?

    /// Timestamp of the most recent check *attempt* of each mode — set as soon as a check
    /// starts, regardless of whether it completes, fails, or gets cancelled. Distinct from
    /// lastQuickCheck/lastDeepCheck, which only record completed results and drive the UI.
    /// Used purely so due-date scheduling doesn't treat a cancelled/incomplete attempt as if
    /// nothing happened and immediately retry it.
    var lastQuickAttempt: Date?
    var lastDeepAttempt: Date?

    /// When the scheduler last found this volume unreachable (e.g. an unplugged drive) and
    /// notified about it. Deliberately separate from lastQuickAttempt/lastDeepAttempt — those
    /// feed the deep-check due-date math, but an unreachable check never actually attempted
    /// anything, so it must not affect that schedule. This field exists purely to throttle
    /// how often the background scheduler retries (and re-notifies) while a drive stays
    /// disconnected, independent of that.
    var lastUnreachableNotification: Date?

    struct CheckRecord: Codable, Sendable {
        var date: Date
        var outcome: Outcome
        var fileCount: Int
        var issues: [String]
        /// Wall-clock time the check took to run. Optional only so records persisted before this
        /// field existed still decode.
        var duration: TimeInterval?

        enum Outcome: String, Codable, Sendable {
            case clean
            case failed
            case uncovered  // new files present that haven't been appended yet
        }
    }

    var overallStatus: Status {
        guard let deep = lastDeepCheck else { return .unknown }
        return deep.outcome == .failed ? .failed : .clean
    }

    enum Status { case unknown, clean, failed }

    var archiveURL: URL  { URL(fileURLWithPath: archivePath) }
    var manifestURL: URL { URL(fileURLWithPath: manifestPath) }
}
