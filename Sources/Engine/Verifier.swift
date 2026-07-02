import Foundation

public enum VerifierError: Error, Sendable {
    case manifestNotEmpty(URL)
}

public struct Verifier: Sendable {
    public var throttle: Duration?
    public var chunkSize: Int
    /// Number of files hashed concurrently. Default 1 (safe for HDDs).
    /// Set to 4–8 for SSDs to saturate I/O queue depth.
    public var concurrency: Int

    public init(
        throttle: Duration? = nil,
        chunkSize: Int = FileHasher.defaultChunkSize,
        concurrency: Int = 1
    ) {
        self.throttle = throttle
        self.chunkSize = chunkSize
        self.concurrency = max(1, concurrency)
    }

    // MARK: - Quick check

    public func quickCheck(root: URL, manifest: Manifest) throws -> QuickCheckResult {
        let live = try TreeWalker.walk(root: root)
        let liveSet = Set(live)
        let manifestSet = Set(manifest.entries.keys)
        return QuickCheckResult(
            manifestCount: manifest.count,
            liveCount: live.count,
            missing: manifestSet.subtracting(liveSet).sorted(),
            new: liveSet.subtracting(manifestSet).sorted()
        )
    }

    // MARK: - Deep check

    /// Hashes every baselined file and collects new files, up to `concurrency` files at once.
    public func deepCheck(
        root: URL,
        manifest: Manifest,
        onProgress: ((VerifyProgress) -> Void)? = nil
    ) async throws -> DeepCheckResult {
        let live = try TreeWalker.walk(root: root)
        let rootURL = root.resolvingSymlinksInPath()

        let newPaths = live.filter { manifest.entries[$0] == nil }
        let total = manifest.count + newPaths.count

        // Flatten all work into a single list so the pool can drain it uniformly.
        enum WorkItem: Sendable {
            case verify(path: String, expected: String)
            case hashNew(path: String)
        }
        var work: [WorkItem] = []
        work.reserveCapacity(total)
        for (path, expected) in manifest.entries { work.append(.verify(path: path, expected: expected)) }
        for path in newPaths                      { work.append(.hashNew(path: path)) }

        enum FileResult: Sendable {
            case ok(String)
            case corrupted(String, expected: String, actual: String)
            case missing(String)
            case new(String, hash: String)
            var path: String {
                switch self {
                case .ok(let p), .corrupted(let p, _, _), .missing(let p), .new(let p, _): return p
                }
            }
        }

        var result = DeepCheckResult()
        var completed = 0
        var lastProgressUpdate = Date.distantPast

        try await withThrowingTaskGroup(of: FileResult.self) { group in
            var iter = work.makeIterator()

            func submit() {
                guard let item = iter.next() else { return }
                group.addTask { [self] in
                    try Task.checkCancellation()
                    switch item {
                    case .verify(let path, let expected):
                        let url = fileURL(for: path, root: rootURL)
                        guard FileManager.default.fileExists(atPath: url.path) else {
                            return .missing(path)
                        }
                        do {
                            let actual = try await FileHasher.hash(url: url, chunkSize: chunkSize, throttle: throttle)
                            return actual == expected ? .ok(path) : .corrupted(path, expected: expected, actual: actual)
                        } catch {
                            return .missing(path)
                        }
                    case .hashNew(let path):
                        let url = fileURL(for: path, root: rootURL)
                        guard let hash = try? await FileHasher.hash(url: url, chunkSize: chunkSize, throttle: throttle) else {
                            return .missing(path)
                        }
                        return .new(path, hash: hash)
                    }
                }
            }

            // Seed the pool.
            for _ in 0..<min(concurrency, work.count) { submit() }

            // Drain: collect a result, refill one slot, repeat.
            while let fileResult = try await group.next() {
                completed += 1
                if Self.shouldReportProgress(completed: completed, total: total, since: &lastProgressUpdate) {
                    onProgress?(.hashing(path: fileResult.path, index: completed, total: total))
                }
                switch fileResult {
                case .ok(let p):                         result.ok.append(p)
                case .corrupted(let p, let e, let a):    result.corrupted.append(CorruptedFile(path: p, expected: e, actual: a))
                case .missing(let p):                    result.missing.append(p)
                case .new(let p, let h):                 result.new[p] = h
                }
                submit()
            }
        }

        return result
    }

    // MARK: - Baseline

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
        let total = paths.count
        var newEntries: [String: String] = [:]

        try await withThrowingTaskGroup(of: (String, String).self) { group in
            var iter = paths.makeIterator()

            func submit() {
                guard let path = iter.next() else { return }
                group.addTask { [self] in
                    try Task.checkCancellation()
                    let hash = try await FileHasher.hash(
                        url: fileURL(for: path, root: rootURL),
                        chunkSize: chunkSize,
                        throttle: throttle
                    )
                    return (path, hash)
                }
            }

            for _ in 0..<min(concurrency, paths.count) { submit() }

            var completed = 0
            var lastProgressUpdate = Date.distantPast
            while let (path, hash) = try await group.next() {
                completed += 1
                if Self.shouldReportProgress(completed: completed, total: total, since: &lastProgressUpdate) {
                    onProgress?(.hashing(path: path, index: completed, total: total))
                }
                newEntries[path] = hash
                submit()
            }
        }

        try manifest.append(newEntries)
        return manifest
    }

    // MARK: - Helpers

    /// Caps progress callbacks to roughly 10/sec (always reporting the final item), so a large
    /// archive doesn't fire hundreds of thousands of progress events nobody can perceive —
    /// each one costs a real hop back to the caller (e.g. a MainActor UI update) that adds up.
    private static func shouldReportProgress(completed: Int, total: Int, since lastUpdate: inout Date) -> Bool {
        let now = Date()
        guard completed == total || now.timeIntervalSince(lastUpdate) >= 0.1 else { return false }
        lastUpdate = now
        return true
    }

    private func fileURL(for manifestPath: String, root: URL) -> URL {
        let relative = manifestPath.hasPrefix("./") ? String(manifestPath.dropFirst(2)) : manifestPath
        return root.appendingPathComponent(relative)
    }
}
