import Foundation

/// Writes and clears a visible plain-text marker file inside the archive directory.
/// This is the last-resort failure signal: survives no-permission / DND / logged-out states.
enum FailureMarker {
    private static let filename = "⚠️_ARCHIVE_CHECK_FAILED.txt"

    static func write(to directory: URL, volumeName: String) {
        let url = directory.appendingPathComponent(filename)
        let body = """
            ARCHIVE INTEGRITY CHECK FAILED
            Volume : \(volumeName)
            Time   : \(Date())

            One or more files are corrupted or missing.
            Restore from backup before re-running a check.
            This file is removed automatically after a clean run.
            """
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    static func clear(from directory: URL) {
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(filename))
    }
}
