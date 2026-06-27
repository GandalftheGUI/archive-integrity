import Foundation

public enum ManifestError: Error, Sendable {
    case appendFailed(URL)
}

/// An append-only map of archive-relative paths to their BLAKE3 hex digests.
///
/// Format is b3sum-compatible: `<64-hex>  ./relative/path\n`
/// Existing entries are never rewritten; new entries are appended.
public struct Manifest: Sendable {
    public let url: URL
    public private(set) var entries: [String: String]  // normalized path -> hex hash

    public var count: Int { entries.count }

    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            self.entries = try Self.parse(url: url)
        } else {
            self.entries = [:]
        }
    }

    private static func parse(url: URL) throws -> [String: String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var result: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line)
            // Minimum valid line: 64 hex + "  " + "./" + at least one char = 69 chars
            guard s.count >= 69 else { continue }
            let hashEnd = s.index(s.startIndex, offsetBy: 64)
            let sepEnd = s.index(hashEnd, offsetBy: 2)
            guard s[hashEnd..<sepEnd] == "  " else { continue }
            let hash = String(s[s.startIndex..<hashEnd])
            let path = String(s[sepEnd...])
            guard path.hasPrefix("./"), !path.isEmpty else { continue }
            result[path] = hash
        }
        return result
    }

    public func hash(for path: String) -> String? {
        entries[path]
    }

    /// Appends `newEntries` to the manifest file and updates the in-memory map.
    /// Caller is responsible for ensuring these paths are not already present.
    public mutating func append(_ newEntries: [String: String]) throws {
        guard !newEntries.isEmpty else { return }

        var output = ""
        for (path, hash) in newEntries {
            output += "\(hash)  \(path)\n"
        }

        guard let data = output.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = FileHandle(forWritingAtPath: url.path) else {
                throw ManifestError.appendFailed(url)
            }
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try data.write(to: url, options: .atomic)
        }

        for (path, hash) in newEntries {
            entries[path] = hash
        }
    }
}
