import Testing
import Foundation
@testable import Engine

@Suite struct VerifierTests {

    // MARK: - Baseline + verify clean

    @Test func baselineThenVerifyClean() async throws {
        let (root, manifestURL) = try makeArchive(fileCount: 3)
        defer { cleanup(root, manifestURL) }

        let verifier = Verifier()
        let manifest = try await verifier.baseline(root: root, manifestURL: manifestURL)
        #expect(manifest.count == 3)

        let result = try await verifier.deepCheck(root: root, manifest: manifest)
        #expect(result.isClean)
        #expect(result.ok.count == 3)
        #expect(result.corrupted.isEmpty)
        #expect(result.missing.isEmpty)
        #expect(result.new.isEmpty)
    }

    // MARK: - Corruption detection

    @Test func detectsCorruption() async throws {
        let (root, manifestURL) = try makeArchive(fileCount: 3)
        defer { cleanup(root, manifestURL) }

        let verifier = Verifier()
        let manifest = try await verifier.baseline(root: root, manifestURL: manifestURL)

        // Corrupt one file after baselining
        let target = root.appendingPathComponent("file-0.bin")
        try Data("corrupted".utf8).write(to: target)

        let result = try await verifier.deepCheck(root: root, manifest: manifest)
        #expect(!result.isClean)
        #expect(result.corrupted.count == 1)
        #expect(result.corrupted[0].path == "./file-0.bin")
        #expect(result.ok.count == 2)
    }

    // MARK: - Missing file detection

    @Test func detectsMissingFile() async throws {
        let (root, manifestURL) = try makeArchive(fileCount: 3)
        defer { cleanup(root, manifestURL) }

        let verifier = Verifier()
        let manifest = try await verifier.baseline(root: root, manifestURL: manifestURL)

        try FileManager.default.removeItem(at: root.appendingPathComponent("file-1.bin"))

        let result = try await verifier.deepCheck(root: root, manifest: manifest)
        #expect(!result.isClean)
        #expect(result.missing.count == 1)
    }

    // MARK: - New file detection

    @Test func detectsNewFile() async throws {
        let (root, manifestURL) = try makeArchive(fileCount: 2)
        defer { cleanup(root, manifestURL) }

        let verifier = Verifier()
        let manifest = try await verifier.baseline(root: root, manifestURL: manifestURL)

        try Data("new".utf8).write(to: root.appendingPathComponent("new.bin"))

        let result = try await verifier.deepCheck(root: root, manifest: manifest)
        #expect(result.isClean)  // new files don't mark the check dirty
        #expect(result.new.count == 1)
        #expect(result.new["./new.bin"] != nil)
    }

    // MARK: - Quick check

    @Test func quickCheckClean() async throws {
        let (root, manifestURL) = try makeArchive(fileCount: 3)
        defer { cleanup(root, manifestURL) }

        let verifier = Verifier()
        let manifest = try await verifier.baseline(root: root, manifestURL: manifestURL)
        let result = try verifier.quickCheck(root: root, manifest: manifest)

        #expect(result.isClean)
        #expect(result.manifestCount == 3)
        #expect(result.liveCount == 3)
    }

    @Test func quickCheckDetectsMissingByCount() async throws {
        let (root, manifestURL) = try makeArchive(fileCount: 3)
        defer { cleanup(root, manifestURL) }

        let verifier = Verifier()
        let manifest = try await verifier.baseline(root: root, manifestURL: manifestURL)

        try FileManager.default.removeItem(at: root.appendingPathComponent("file-2.bin"))

        let result = try verifier.quickCheck(root: root, manifest: manifest)
        #expect(!result.isClean)
        #expect(result.missingFiles == 1)
    }

    // MARK: - Append gate

    @Test func newFilesAppendedAfterCleanRun() async throws {
        let (root, manifestURL) = try makeArchive(fileCount: 2)
        defer { cleanup(root, manifestURL) }

        let verifier = Verifier()
        var manifest = try await verifier.baseline(root: root, manifestURL: manifestURL)
        #expect(manifest.count == 2)

        try Data("new".utf8).write(to: root.appendingPathComponent("new.bin"))

        let result = try await verifier.deepCheck(root: root, manifest: manifest)
        #expect(result.isClean)
        #expect(result.new.count == 1)

        try manifest.append(result.new)
        #expect(manifest.count == 3)

        let reloaded = try Manifest(url: manifestURL)
        #expect(reloaded.count == 3)
    }

    @Test func baselineErrorsIfManifestExists() async throws {
        let (root, manifestURL) = try makeArchive(fileCount: 1)
        defer { cleanup(root, manifestURL) }

        let verifier = Verifier()
        _ = try await verifier.baseline(root: root, manifestURL: manifestURL)

        await #expect(throws: VerifierError.self) {
            _ = try await verifier.baseline(root: root, manifestURL: manifestURL)
        }
    }

    // MARK: - Helpers

    private func makeArchive(fileCount: Int) throws -> (root: URL, manifestURL: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for i in 0..<fileCount {
            let data = Data("content-\(i)-\(UUID().uuidString)".utf8)
            try data.write(to: root.appendingPathComponent("file-\(i).bin"))
        }

        let manifestURL = root.deletingLastPathComponent()
            .appendingPathComponent(root.lastPathComponent + ".b3manifest")

        return (root, manifestURL)
    }

    private func cleanup(_ root: URL, _ manifestURL: URL) {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: manifestURL)
    }
}
