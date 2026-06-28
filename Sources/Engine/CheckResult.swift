public struct CorruptedFile: Sendable {
    public let path: String
    public let expected: String
    public let actual: String
}

public struct QuickCheckResult: Sendable {
    public let manifestCount: Int
    public let liveCount: Int
    public let missing: [String]   // in manifest but not on disk
    public let new: [String]       // on disk but not in manifest

    public var isClean: Bool { missing.isEmpty }
    public var missingFiles: Int { missing.count }
    public var newFiles: Int { new.count }
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
