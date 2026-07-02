import Foundation

public enum ManifestError: Error, Sendable {
    case appendFailed(URL)
}

/// A map of archive-relative paths to their BLAKE3 hex digests.
///
/// Format is b3sum-compatible: `<64-hex>  ./relative/path\n`
/// The CLI only ever appends; the app may also remove entries via `remove(_:)`.
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

        // Split on the Unicode *scalar* "\n", not a grapheme-cluster-based Character split.
        // A path can legitimately end in a raw "\r" (e.g. macOS's hidden `Icon\r` custom-folder-icon
        // marker); Swift's Character clusters a trailing "\r" with the following "\n" into a single
        // grapheme, so `String.split(separator: "\n" as Character)` silently fails to split there,
        // merging that entry with the next line.
        var line = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\n" {
                parseLine(String(line), into: &result)
                line.removeAll(keepingCapacity: true)
            } else {
                line.append(scalar)
            }
        }
        if !line.isEmpty {
            parseLine(String(line), into: &result)
        }

        return result
    }

    private static func parseLine(_ s: String, into result: inout [String: String]) {
        // Minimum valid line: 64 hex + "  " + "./" + at least one char = 69 chars
        guard s.count >= 69 else { return }
        let hashEnd = s.index(s.startIndex, offsetBy: 64)
        let sepEnd = s.index(hashEnd, offsetBy: 2)
        guard s[hashEnd..<sepEnd] == "  " else { return }
        let hash = String(s[s.startIndex..<hashEnd])
        let path = String(s[sepEnd...])
        guard path.hasPrefix("./"), !path.isEmpty else { return }
        result[path] = hash
    }

    public func hash(for path: String) -> String? {
        entries[path]
    }

    /// Removes `paths` from the manifest, atomically rewriting the file.
    public mutating func remove(_ paths: Set<String>) throws {
        guard !paths.isEmpty else { return }
        for path in paths { entries.removeValue(forKey: path) }
        var output = ""
        for (path, hash) in entries.sorted(by: { $0.key < $1.key }) {
            output += "\(hash)  \(path)\n"
        }
        try output.data(using: .utf8)!.write(to: url, options: .atomic)
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
