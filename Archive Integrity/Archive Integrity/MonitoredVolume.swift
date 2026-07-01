import Foundation

struct MonitoredVolume: Identifiable, Codable, Sendable {
    static let defaultDeepCheckIntervalDays = 7

    var id: UUID = UUID()
    var displayName: String
    var archivePath: String
    var manifestPath: String
    var volumeUUID: String?          // populated for external drives; nil for local dirs
    var deepCheckIntervalDays: Int = MonitoredVolume.defaultDeepCheckIntervalDays
    /// Concurrent files hashed in parallel during deep check. 1 = sequential (HDD-safe), 4–8 for SSDs.
    var concurrency: Int = 1

    var lastQuickCheck: CheckRecord?
    var lastDeepCheck: CheckRecord?

    struct CheckRecord: Codable, Sendable {
        var date: Date
        var outcome: Outcome
        var fileCount: Int
        var issues: [String]

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
