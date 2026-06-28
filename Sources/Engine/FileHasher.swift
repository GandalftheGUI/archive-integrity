import Blake3
import Foundation

public enum HashError: Error, Sendable {
    case openFailed(URL, any Error)
    case readFailed(URL, any Error)
}

public struct FileHasher {
    public static let defaultChunkSize = 8 * 1024 * 1024  // 8 MB

    /// Streams `url` through BLAKE3 in `chunkSize` chunks, checking for cancellation
    /// and optionally sleeping between chunks to throttle I/O.
    public static func hash(
        url: URL,
        chunkSize: Int = defaultChunkSize,
        throttle: Duration? = nil
    ) async throws -> String {
        var hasher = Blake3()

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw HashError.openFailed(url, error)
        }
        defer { handle.closeFile() }

        while true {
            try Task.checkCancellation()

            let chunk: Data
            do {
                guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else { break }
                chunk = data
            } catch {
                throw HashError.readFailed(url, error)
            }

            chunk.withUnsafeBytes { ptr in
                hasher.update(bufferPointer: ptr)
            }

            if let throttle {
                try await Task.sleep(for: throttle)
            }
        }

        let digest = hasher.finalize()
        return digest.withUnsafeBytes { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
    }
}
