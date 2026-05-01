import Foundation

public enum AuditAction: String, Codable, Equatable, Sendable {
    case workspaceCreated
    case workspaceLoaded
    case manifestSaved
    case intakeObserved
    case doctorRan
    case metadataInitialized
    case metadataLinted
    case screenshotPlanSaved
    case screenshotImportManifestSaved
    case screenshotCompositionManifestSaved
    case screenshotUploadPlanned
    case screenshotUploadExecuted
    case screenshotReadinessChecked
    case reviewInfoInitialized
    case submissionReadinessChecked
    case submissionPreparationSaved
    case reviewSubmissionPlanned
    case reviewSubmissionExecuted
    case reviewHandoffWritten
    case ascAuthInitialized
    case ascAuthChecked
    case ascLookupPlanned
    case ascAppsObserved
    case buildCandidatesImported
    case ascObservedStateImported
    case ascMetadataPlanned
    case ascMetadataRequestsPlanned
    case ascMetadataApplied
    case ascPricingApplied
    case ascPrivacyUpdated
    case iapTemplateInitialized
    case iapValidated
    case metadataDiffed
}

public struct AuditRecord: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var action: AuditAction
    public var summary: String
    public var details: [String: String]

    public init(
        timestamp: Date = Date(),
        action: AuditAction,
        summary: String,
        details: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.action = action
        self.summary = summary
        self.details = details.mapValues { Redactor.redact($0) }
    }
}

public struct AuditLogReader {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func read(workspace: ReleaseWorkspace) throws -> [AuditRecord] {
        let url = URL(fileURLWithPath: workspace.paths.auditEvents)
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents
            .split(separator: "\n")
            .compactMap { line in
                try? AscendKitJSON.decoder.decode(AuditRecord.self, from: Data(line.utf8))
            }
    }
}
