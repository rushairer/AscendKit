import Foundation

public struct ReleaseWorkspacePaths: Codable, Equatable, Sendable {
    public var root: String
    public var manifest: String
    public var intake: String
    public var doctorReport: String
    public var readiness: String
    public var screenshotPlan: String
    public var screenshotCapturePlan: String
    public var screenshotImportManifest: String
    public var screenshotCompositionManifest: String
    public var screenshotUploadPlan: String
    public var screenshotUploadResult: String
    public var metadataSource: String
    public var metadataLint: String
    public var reviewInfo: String
    public var reviewChecklist: String
    public var reviewSubmissionPlan: String
    public var reviewSubmissionResult: String
    public var reviewHandoffMarkdown: String
    public var buildCandidates: String
    public var ascAuthConfig: String
    public var ascLookupPlan: String
    public var ascApps: String
    public var ascObservedState: String
    public var ascDiff: String
    public var ascMetadataPlan: String
    public var ascMetadataRequests: String
    public var ascMetadataApplyResult: String
    public var ascPricingResult: String
    public var ascPrivacyStatus: String
    public var iapSubscriptions: String
    public var iapValidation: String
    public var auditEvents: String

    public init(root: URL) {
        let releaseRoot = root.standardizedFileURL
        self.root = releaseRoot.path
        self.manifest = releaseRoot.appendingPathComponent("manifest.json").path
        self.intake = releaseRoot.appendingPathComponent("intake.json").path
        self.doctorReport = releaseRoot.appendingPathComponent("doctor-report.json").path
        self.readiness = releaseRoot.appendingPathComponent("readiness.json").path
        self.screenshotPlan = releaseRoot.appendingPathComponent("screenshot-plan.json").path
        self.screenshotCapturePlan = releaseRoot.appendingPathComponent("screenshots/manifests/capture-plan.json").path
        self.screenshotImportManifest = releaseRoot.appendingPathComponent("screenshots/manifests/import.json").path
        self.screenshotCompositionManifest = releaseRoot.appendingPathComponent("screenshots/manifests/composition.json").path
        self.screenshotUploadPlan = releaseRoot.appendingPathComponent("screenshots/manifests/upload.json").path
        self.screenshotUploadResult = releaseRoot.appendingPathComponent("screenshots/manifests/upload-result.json").path
        self.metadataSource = releaseRoot.appendingPathComponent("metadata/source/en-US.json").path
        self.metadataLint = releaseRoot.appendingPathComponent("metadata/lint/en-US.json").path
        self.reviewInfo = releaseRoot.appendingPathComponent("review/reviewer-info.json").path
        self.reviewChecklist = releaseRoot.appendingPathComponent("review/checklist.json").path
        self.reviewSubmissionPlan = releaseRoot.appendingPathComponent("review/submission-plan.json").path
        self.reviewSubmissionResult = releaseRoot.appendingPathComponent("review/submission-result.json").path
        self.reviewHandoffMarkdown = releaseRoot.appendingPathComponent("review/handoff.md").path
        self.buildCandidates = releaseRoot.appendingPathComponent("build/candidates.json").path
        self.ascAuthConfig = releaseRoot.appendingPathComponent("asc/auth.json").path
        self.ascLookupPlan = releaseRoot.appendingPathComponent("asc/lookup-plan.json").path
        self.ascApps = releaseRoot.appendingPathComponent("asc/apps.json").path
        self.ascObservedState = releaseRoot.appendingPathComponent("asc/observed-state.json").path
        self.ascDiff = releaseRoot.appendingPathComponent("asc/diff.json").path
        self.ascMetadataPlan = releaseRoot.appendingPathComponent("asc/metadata-plan.json").path
        self.ascMetadataRequests = releaseRoot.appendingPathComponent("asc/metadata-requests.json").path
        self.ascMetadataApplyResult = releaseRoot.appendingPathComponent("asc/metadata-apply-result.json").path
        self.ascPricingResult = releaseRoot.appendingPathComponent("asc/pricing-result.json").path
        self.ascPrivacyStatus = releaseRoot.appendingPathComponent("asc/privacy-status.json").path
        self.iapSubscriptions = releaseRoot.appendingPathComponent("iap/subscriptions.json").path
        self.iapValidation = releaseRoot.appendingPathComponent("iap/validation.json").path
        self.auditEvents = releaseRoot.appendingPathComponent("audit/events.jsonl").path
    }
}

public struct ReleaseWorkspace: Codable, Equatable, Sendable {
    public var releaseID: String
    public var paths: ReleaseWorkspacePaths

    public init(releaseID: String, root: URL) {
        self.releaseID = releaseID
        self.paths = ReleaseWorkspacePaths(root: root)
    }
}

public struct ReleaseWorkspaceStore {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func workspaceRoot(baseDirectory: URL, releaseID: String) -> URL {
        baseDirectory
            .appendingPathComponent(".ascendkit")
            .appendingPathComponent("releases")
            .appendingPathComponent(releaseID)
    }

    @discardableResult
    public func createWorkspace(baseDirectory: URL, manifest: ReleaseManifest) throws -> ReleaseWorkspace {
        let root = workspaceRoot(baseDirectory: baseDirectory, releaseID: manifest.releaseID)
        let workspace = ReleaseWorkspace(releaseID: manifest.releaseID, root: root)

        try createDirectoryLayout(for: workspace)
        try save(manifest, to: URL(fileURLWithPath: workspace.paths.manifest))
        try appendAudit(
            AuditRecord(
                action: .workspaceCreated,
                summary: "Created release workspace",
                details: ["releaseID": manifest.releaseID]
            ),
            to: workspace
        )
        return workspace
    }

    public func loadWorkspace(root: URL) throws -> ReleaseWorkspace {
        guard fileManager.fileExists(atPath: root.path) else {
            throw AscendKitError.workspaceNotFound(root.path)
        }
        let releaseID = root.lastPathComponent
        let workspace = ReleaseWorkspace(releaseID: releaseID, root: root)
        try appendAudit(
            AuditRecord(action: .workspaceLoaded, summary: "Loaded release workspace"),
            to: workspace
        )
        return workspace
    }

    public func loadManifest(from workspace: ReleaseWorkspace) throws -> ReleaseManifest {
        let url = URL(fileURLWithPath: workspace.paths.manifest)
        let data = try Data(contentsOf: url)
        return try AscendKitJSON.decoder.decode(ReleaseManifest.self, from: data)
    }

    public func save<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try AscendKitJSON.encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    public func appendAudit(_ record: AuditRecord, to workspace: ReleaseWorkspace) throws {
        let url = URL(fileURLWithPath: workspace.paths.auditEvents)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let line = String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } else {
            try Data(line.utf8).write(to: url, options: [.atomic])
        }
    }

    private func createDirectoryLayout(for workspace: ReleaseWorkspace) throws {
        let root = URL(fileURLWithPath: workspace.paths.root)
        let directories = [
            root,
            root.appendingPathComponent("screenshots/raw"),
            root.appendingPathComponent("screenshots/composed"),
            root.appendingPathComponent("screenshots/manifests"),
            root.appendingPathComponent("metadata/source"),
            root.appendingPathComponent("metadata/localized"),
            root.appendingPathComponent("metadata/lint"),
            root.appendingPathComponent("asc"),
            root.appendingPathComponent("build"),
            root.appendingPathComponent("iap"),
            root.appendingPathComponent("review"),
            root.appendingPathComponent("audit")
        ]
        for directory in directories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
