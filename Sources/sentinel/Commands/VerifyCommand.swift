import ArgumentParser
import Engine
import Foundation

struct VerifyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify an archive against its manifest."
    )

    @Argument(help: "Path to the archive directory.")
    var path: String

    @Option(name: .shortAndLong, help: "Manifest path. Default: <path>.b3manifest")
    var manifest: String?

    @Flag(name: .shortAndLong, help: "Quick check: compare file counts only, no hashing.")
    var quick = false

    @Flag(name: .long, help: "After a clean deep check, append new files to the manifest.")
    var append = false

    @Option(name: .long, help: "Milliseconds to sleep between 1MB chunks (I/O throttle).")
    var throttleMs: Int = 0

    func run() async throws {
        let root = URL(fileURLWithPath: path).standardized
        let manifestURL = resolvedManifestURL(root: root)

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            fputs("error: no manifest at \(manifestURL.path)\n", stderr)
            fputs("       run 'sentinel baseline \(path)' first.\n", stderr)
            throw ExitCode.failure
        }

        var manifest = try Manifest(url: manifestURL)

        if quick {
            try runQuickCheck(root: root, manifest: manifest)
        } else {
            try await runDeepCheck(root: root, manifest: &manifest, manifestURL: manifestURL)
        }
    }

    // MARK: - Quick check

    private func runQuickCheck(root: URL, manifest: Manifest) throws {
        let result = try Verifier().quickCheck(root: root, manifest: manifest)

        print("Quick check: \(root.path)")
        print("  Manifest: \(result.manifestCount) files")
        print("  Live:     \(result.liveCount) files")
        print()

        for path in result.missing { print("MISSING   \(path)") }
        for path in result.new     { print("NEW       \(path)") }

        if !result.missing.isEmpty {
            if !result.new.isEmpty { print() }
            print("FAIL — \(result.missingFiles) file(s) missing.")
            throw ExitCode.failure
        } else if !result.new.isEmpty {
            print("OK — \(result.newFiles) new file(s) not yet in manifest.")
        } else {
            print("OK — all files present.")
        }
    }

    // MARK: - Deep check

    private func runDeepCheck(
        root: URL,
        manifest: inout Manifest,
        manifestURL: URL
    ) async throws {
        let throttle: Duration? = throttleMs > 0 ? .milliseconds(throttleMs) : nil
        let verifier = Verifier(throttle: throttle)

        print("Verify: \(root.path)")
        print("Manifest: \(manifestURL.path) (\(manifest.count) entries)")

        var progressLine = ""
        let result = try await verifier.deepCheck(root: root, manifest: manifest) { event in
            if case .hashing(let p, let index, let total) = event {
                updateProgress(&progressLine, index: index, total: total, path: p)
            }
        }

        finishProgress(progressLine)
        print()

        // Summary table
        print("  OK:        \(result.ok.count)")
        print("  Corrupted: \(result.corrupted.count)")
        print("  Missing:   \(result.missing.count)")
        print("  New:       \(result.new.count)")
        print()

        // Detail lines
        for f in result.corrupted {
            print("CORRUPTED \(f.path)")
            print("  expected: \(f.expected)")
            print("  actual:   \(f.actual)")
        }
        for path in result.missing {
            print("MISSING   \(path)")
        }
        for path in result.new.keys.sorted() {
            print("NEW       \(path)")
        }

        // All-files-fail heuristic: likely a path/mount mismatch, not mass corruption
        let failRate = manifest.count > 0
            ? Double(result.corrupted.count + result.missing.count) / Double(manifest.count)
            : 0
        if failRate > 0.5 && manifest.count > 10 {
            print()
            print("WARNING: >\(Int(failRate * 100))% of files failed.")
            print("This pattern suggests a path or mount-point mismatch rather than")
            print("mass corruption. Verify the archive is mounted at the expected path.")
        }

        if result.isClean {
            if result.hasNewFiles && append {
                try manifest.append(result.new)
                print("Appended \(result.new.count) new file(s) to manifest.")
            } else if result.hasNewFiles {
                print("Clean — \(result.new.count) new file(s) not yet in manifest.")
                print("Re-run with --append to add them.")
            } else {
                print("All files OK.")
            }
        } else {
            print()
            print("FAILED — do not proceed until failures are resolved.")
            print("Restore corrupted/missing files from backup before re-running.")
            throw ExitCode.failure
        }
    }

    // MARK: - Helpers

    private func resolvedManifestURL(root: URL) -> URL {
        if let m = manifest { return URL(fileURLWithPath: m) }
        return root.deletingLastPathComponent()
            .appendingPathComponent(root.lastPathComponent + ".b3manifest")
    }
}
