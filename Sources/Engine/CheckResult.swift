public struct CorruptedFile: Sendable {
    public let path: String
    public let expected: String
    public let actual: String
}

public struct QuickCheckResult: Sendable {
    public let manifestCount: Int
    public let liveCount: Int

    public var isClean: Bool { liveCount >= manifestCount }
    public var newFiles: Int { max(0, liveCount - manifestCount) }
    public var missingFiles: Int { max(0, manifestCount - liveCount) }
}

public struct DeepCheckResult: Sendable {
    public var ok: [String] = []
    public var corrupted: [CorruptedFile] = []
    public var missing: [String] = []
    public var new: [String: String] = [:]  // path -> hash

    public var isClean: Bool { corrupted.isEmpty && missing.isEmpty }
    public var hasNewFiles: Bool { !new.isEmpty }
    public var totalChecked: Int { ok.count + corrupted.count + missing.count }
}

public enum VerifyProgress: Sendable {
    case hashing(path: String, index: Int, total: Int)
    case result(path: String, verdict: Verdict)

    public enum Verdict: Sendable {
        case ok, corrupted, missing, new
    }
}
