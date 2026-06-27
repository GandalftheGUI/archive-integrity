import Foundation

public enum VerifierError: Error, Sendable {
    case manifestNotEmpty(URL)
}

public struct Verifier: Sendable {
    public var throttle: Duration?
    public var chunkSize: Int

    public init(throttle: Duration? = nil, chunkSize: Int = FileHasher.defaultChunkSize) {
        self.throttle = throttle
        self.chunkSize = chunkSize
    }

    // MARK: - Quick check

    /// Counts live files vs manifest entries. Seconds. No hashing.
    public func quickCheck(root: URL, manifest: Manifest) throws -> QuickCheckResult {
        let live = try TreeWalker.walk(root: root)
        return QuickCheckResult(manifestCount: manifest.count, liveCount: live.count)
    }

    // MARK: - Deep check

    /// Hashes every baselined file, diffs result, collects new files.
    /// All-files-fail detection: if every manifest entry fails, the caller should
    /// treat that as a likely path/normalization mismatch rather than mass corruption.
    public func deepCheck(
        root: URL,
        manifest: Manifest,
        onProgress: ((VerifyProgress) -> Void)? = nil
    ) async throws -> DeepCheckResult {
        let live = try TreeWalker.walk(root: root)
        let rootURL = root.resolvingSymlinksInPath()
        var result = DeepCheckResult()

        let newPaths = live.filter { manifest.entries[$0] == nil }
        let total = manifest.count + newPaths.count
        var index = 0

        // Verify every file in the manifest
        for (path, expected) in manifest.entries {
            index += 1
            try Task.checkCancellation()
            onProgress?(.hashing(path: path, index: index, total: total))

            let fileURL = fileURL(for: path, root: rootURL)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                result.missing.append(path)
                onProgress?(.result(path: path, verdict: .missing))
                continue
            }

            do {
                let actual = try await FileHasher.hash(
                    url: fileURL, chunkSize: chunkSize, throttle: throttle)
                if actual == expected {
                    result.ok.append(path)
                    onProgress?(.result(path: path, verdict: .ok))
                } else {
                    result.corrupted.append(
                        CorruptedFile(path: path, expected: expected, actual: actual))
                    onProgress?(.result(path: path, verdict: .corrupted))
                }
            } catch {
                result.missing.append(path)
                onProgress?(.result(path: path, verdict: .missing))
            }
        }

        // Hash new files so they're ready to append after a clean run
        for path in newPaths {
            index += 1
            try Task.checkCancellation()
            onProgress?(.hashing(path: path, index: index, total: total))

            let fileURL = fileURL(for: path, root: rootURL)
            if let hash = try? await FileHasher.hash(
                url: fileURL, chunkSize: chunkSize, throttle: throttle)
            {
                result.new[path] = hash
                onProgress?(.result(path: path, verdict: .new))
            }
        }

        return result
    }

    // MARK: - Baseline

    /// Hashes all files under `root` and writes the initial manifest.
    /// Errors if the manifest file already exists (append-only invariant).
    public func baseline(
        root: URL,
        manifestURL: URL,
        onProgress: ((VerifyProgress) -> Void)? = nil
    ) async throws -> Manifest {
        var manifest = try Manifest(url: manifestURL)
        guard manifest.count == 0 else {
            throw VerifierError.manifestNotEmpty(manifestURL)
        }

        let paths = try TreeWalker.walk(root: root)
        let rootURL = root.resolvingSymlinksInPath()
        var newEntries: [String: String] = [:]
        let total = paths.count

        for (index, path) in paths.enumerated() {
            try Task.checkCancellation()
            onProgress?(.hashing(path: path, index: index + 1, total: total))
            let hash = try await FileHasher.hash(
                url: fileURL(for: path, root: rootURL),
                chunkSize: chunkSize,
                throttle: throttle
            )
            newEntries[path] = hash
        }

        try manifest.append(newEntries)
        return manifest
    }

    // MARK: - Helpers

    private func fileURL(for manifestPath: String, root: URL) -> URL {
        let relative = manifestPath.hasPrefix("./")
            ? String(manifestPath.dropFirst(2))
            : manifestPath
        return root.appendingPathComponent(relative)
    }
}
