import Foundation

public enum TreeWalkerError: Error, Sendable {
    case notADirectory(URL)
    case enumerationFailed(URL)
}

public let defaultExclusions: Set<String> = [
    ".Spotlight-V100",
    ".Trashes",
    ".TemporaryItems",
    ".DocumentRevisions-V100",
    ".fseventsd",
    ".bzvol",
    ".DS_Store",
]

public struct TreeWalker {
    /// Returns NFC-normalized manifest-style paths (`./relative/path`) for every regular
    /// file under `root`, excluding any entry whose last path component is in `exclusions`.
    /// Subtrees whose directory name matches are skipped entirely.
    public static func walk(
        root: URL,
        exclusions: Set<String> = defaultExclusions
    ) throws -> [String] {
        // resolvingSymlinksInPath resolves /var -> /private/var etc. so that the
        // prefix check below doesn't mismatch enumerated URLs on macOS temp dirs.
        let standardRoot = root.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardRoot.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw TreeWalkerError.notADirectory(root)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: standardRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: []
        ) else {
            throw TreeWalkerError.enumerationFailed(root)
        }

        // Ensure root path ends with "/" so dropFirst is clean
        let rootPrefix = standardRoot.path.hasSuffix("/")
            ? standardRoot.path
            : standardRoot.path + "/"

        var paths: [String] = []

        for case let url as URL in enumerator {
            if exclusions.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            // A single file erroring out here (deleted mid-enumeration, a transient I/O hiccup)
            // shouldn't abort the entire walk — just skip that one entry.
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }

            let absPath = url.resolvingSymlinksInPath().path
            guard absPath.hasPrefix(rootPrefix) else { continue }

            let relative = String(absPath.dropFirst(rootPrefix.count))
            // NFC normalization for cross-filesystem consistency (§11)
            let manifestPath = "./\(relative)".precomposedStringWithCanonicalMapping
            paths.append(manifestPath)
        }

        // C-locale byte order: stable, reproducible, b3sum-compatible
        paths.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        return paths
    }
}
