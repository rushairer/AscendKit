import Foundation

// MARK: - Chunking Strategy
public enum ScreenshotChunkingStrategy: String, Codable, CaseIterable, Sendable {
    case locale
    case platform
    case none
}

// MARK: - Upload Chunk
public struct ScreenshotUploadChunk: Codable, Identifiable, Sendable {
    public let id: String
    public let strategy: ScreenshotChunkingStrategy
    public var remoteScreenshotsToDelete: [String]
    public var itemsToUpload: [ScreenshotUploadPlanItem]
    
    public init(id: String, strategy: ScreenshotChunkingStrategy, remoteScreenshotsToDelete: [String], itemsToUpload: [ScreenshotUploadPlanItem]) {
        self.id = id
        self.strategy = strategy
        self.remoteScreenshotsToDelete = remoteScreenshotsToDelete
        self.itemsToUpload = itemsToUpload
    }
}

// MARK: - Chunk Execution State
public enum ScreenshotChunkExecutionState: String, Codable, Sendable {
    case pending
    case wiping
    case wiped
    case uploading
    case success
    case failed
}

// MARK: - Chunk State Tracking
public struct ScreenshotChunkState: Codable, Identifiable, Sendable {
    public let id: String
    public var state: ScreenshotChunkExecutionState
    public var uploadedCount: Int
    public var deletedCount: Int
    public var failedCount: Int
    public var findings: [String]
    
    public init(id: String, state: ScreenshotChunkExecutionState = .pending, uploadedCount: Int = 0, deletedCount: Int = 0, failedCount: Int = 0, findings: [String] = []) {
        self.id = id
        self.state = state
        self.uploadedCount = uploadedCount
        self.deletedCount = deletedCount
        self.failedCount = failedCount
        self.findings = findings
    }
}

// MARK: - Progress State Machine
public struct ScreenshotUploadProgressState: Codable, Sendable {
    public let planID: String
    public let timestamp: Date
    public let strategy: ScreenshotChunkingStrategy
    public var chunks: [String: ScreenshotChunkState]
    public var overallFindings: [String]
    
    public init(planID: String, timestamp: Date = Date(), strategy: ScreenshotChunkingStrategy, chunks: [String : ScreenshotChunkState] = [:], overallFindings: [String] = []) {
        self.planID = planID
        self.timestamp = timestamp
        self.strategy = strategy
        self.chunks = chunks
        self.overallFindings = overallFindings
    }
    
    public var isAllSuccess: Bool {
        guard !chunks.isEmpty else { return false }
        return chunks.values.allSatisfy { $0.state == .success }
    }
}
