import Testing
import Foundation
@testable import Engine

@Suite struct ManifestTests {

    @Test func emptyOnCreate() throws {
        let url = tmpURL()
        let manifest = try Manifest(url: url)
        #expect(manifest.count == 0)
    }

    @Test func roundtrip() throws {
        let url = tmpURL()
        defer { cleanup(url) }

        var manifest = try Manifest(url: url)
        let entries = [
            "./Photos/img001.jpg": String(repeating: "a", count: 64),
            "./Photos/img002.jpg": String(repeating: "b", count: 64),
        ]
        try manifest.append(entries)

        let reloaded = try Manifest(url: url)
        #expect(reloaded.count == 2)
        for (path, hash) in entries {
            #expect(reloaded.hash(for: path) == hash)
        }
    }

    @Test func appendIsAdditive() throws {
        let url = tmpURL()
        defer { cleanup(url) }

        var manifest = try Manifest(url: url)
        try manifest.append(["./a.jpg": String(repeating: "a", count: 64)])
        try manifest.append(["./b.jpg": String(repeating: "b", count: 64)])

        let reloaded = try Manifest(url: url)
        #expect(reloaded.count == 2)
        #expect(reloaded.hash(for: "./a.jpg") != nil)
        #expect(reloaded.hash(for: "./b.jpg") != nil)
    }

    @Test func existingEntriesUnchangedAfterAppend() throws {
        let url = tmpURL()
        defer { cleanup(url) }

        let firstHash = String(repeating: "c", count: 64)
        var manifest = try Manifest(url: url)
        try manifest.append(["./first.jpg": firstHash])
        try manifest.append(["./second.jpg": String(repeating: "d", count: 64)])

        let reloaded = try Manifest(url: url)
        #expect(reloaded.hash(for: "./first.jpg") == firstHash)
    }

    @Test func partialFinalLineIgnoredOnLoad() throws {
        let url = tmpURL()
        defer { cleanup(url) }

        let good = "\(String(repeating: "e", count: 64))  ./good.jpg\n"
        let partial = String(repeating: "f", count: 30)  // no separator, no newline
        try (good + partial).write(to: url, atomically: true, encoding: .utf8)

        let manifest = try Manifest(url: url)
        #expect(manifest.count == 1)
        #expect(manifest.hash(for: "./good.jpg") != nil)
    }

    // MARK: - Helpers

    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".b3manifest")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
