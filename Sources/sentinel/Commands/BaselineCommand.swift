import ArgumentParser
import Engine
import Foundation

struct BaselineCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "baseline",
        abstract: "Create a BLAKE3 manifest for an archive directory."
    )

    @Argument(help: "Path to the archive directory.")
    var path: String

    @Option(name: .shortAndLong, help: "Manifest output path. Default: <path>.b3manifest")
    var manifest: String?

    @Option(name: .long, help: "Milliseconds to sleep between 1MB chunks (I/O throttle).")
    var throttleMs: Int = 0

    func run() async throws {
        let root = URL(fileURLWithPath: path).standardized
        let manifestURL = resolvedManifestURL(root: root)

        guard !FileManager.default.fileExists(atPath: manifestURL.path) else {
            fputs("error: manifest already exists at \(manifestURL.path)\n", stderr)
            fputs("       run 'sentinel verify \(path)' to check the existing archive.\n", stderr)
            throw ExitCode.failure
        }

        print("Baseline: \(root.path)")
        print("Manifest: \(manifestURL.path)")
        print()

        let throttle: Duration? = throttleMs > 0 ? .milliseconds(throttleMs) : nil
        let verifier = Verifier(throttle: throttle)

        var progressLine = ""
        let result = try await verifier.baseline(root: root, manifestURL: manifestURL) { event in
            if case .hashing(let p, let index, let total) = event {
                updateProgress(&progressLine, index: index, total: total, path: p)
            }
        }

        finishProgress(progressLine)
        print("Done. \(result.count) files baselined.")
        print("Manifest: \(manifestURL.path)")
    }

    private func resolvedManifestURL(root: URL) -> URL {
        if let m = manifest { return URL(fileURLWithPath: m) }
        return root.deletingLastPathComponent()
            .appendingPathComponent(root.lastPathComponent + ".b3manifest")
    }
}

