import Foundation

public enum WorkspaceStepState: String, Codable, Equatable, Sendable {
    case present
    case missing
}

public struct WorkspaceStepStatus: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var state: WorkspaceStepState
    public var path: String

    public init(id: String, title: String, state: WorkspaceStepState, path: String) {
        self.id = id
        self.title = title
        self.state = state
        self.path = path
    }
}

public struct WorkspaceStatus: Codable, Equatable, Sendable {
    public var releaseID: String
    public var root: String
    public var generatedAt: Date
    public var steps: [WorkspaceStepStatus]

    public init(releaseID: String, root: String, generatedAt: Date = Date(), steps: [WorkspaceStepStatus]) {
        self.releaseID = releaseID
        self.root = root
        self.generatedAt = generatedAt
        self.steps = steps
    }

    public var completeStepCount: Int {
        steps.filter { $0.state == .present }.count
    }
}

public struct WorkspaceStatusReader {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func read(workspace: ReleaseWorkspace) -> WorkspaceStatus {
        let candidates: [(String, String, String)] = [
            ("manifest", "Release manifest", workspace.paths.manifest),
            ("intake", "Intake report", workspace.paths.intake),
            ("doctor", "Doctor report", workspace.paths.doctorReport),
            ("readiness", "Submission readiness report", workspace.paths.readiness),
            ("metadata-source", "English metadata source", workspace.paths.metadataSource),
            ("metadata-lint", "Metadata lint report", workspace.paths.metadataLint),
            ("screenshot-plan", "Screenshot plan", workspace.paths.screenshotPlan),
            ("screenshot-import", "Screenshot import manifest", workspace.paths.screenshotImportManifest),
            ("screenshot-composition", "Screenshot composition manifest", workspace.paths.screenshotCompositionManifest),
            ("screenshot-upload-plan", "Screenshot upload plan", workspace.paths.screenshotUploadPlan),
            ("screenshot-upload-result", "Screenshot upload result", workspace.paths.screenshotUploadResult),
            ("review-info", "Reviewer info", workspace.paths.reviewInfo),
            ("review-checklist", "Review preparation checklist", workspace.paths.reviewChecklist),
            ("review-submission-plan", "Review submission plan", workspace.paths.reviewSubmissionPlan),
            ("review-submission-result", "Review submission execution result", workspace.paths.reviewSubmissionResult),
            ("review-handoff", "Review handoff markdown", workspace.paths.reviewHandoffMarkdown),
            ("build-candidates", "Build candidates", workspace.paths.buildCandidates),
            ("asc-auth", "ASC auth configuration", workspace.paths.ascAuthConfig),
            ("asc-lookup-plan", "ASC lookup dry-run plan", workspace.paths.ascLookupPlan),
            ("asc-apps", "ASC app lookup observation", workspace.paths.ascApps),
            ("asc-observed", "ASC observed state", workspace.paths.ascObservedState),
            ("asc-diff", "ASC diff", workspace.paths.ascDiff),
            ("asc-metadata-plan", "ASC metadata mutation dry-run plan", workspace.paths.ascMetadataPlan),
            ("asc-metadata-requests", "ASC metadata request dry-run plan", workspace.paths.ascMetadataRequests),
            ("asc-metadata-apply", "ASC metadata apply result", workspace.paths.ascMetadataApplyResult),
            ("asc-pricing", "ASC pricing result", workspace.paths.ascPricingResult),
            ("asc-privacy", "ASC App Privacy status", workspace.paths.ascPrivacyStatus),
            ("iap-subscriptions", "IAP subscription templates", workspace.paths.iapSubscriptions),
            ("iap-validation", "IAP validation report", workspace.paths.iapValidation),
            ("audit", "Audit events", workspace.paths.auditEvents)
        ]

        return WorkspaceStatus(
            releaseID: workspace.releaseID,
            root: workspace.paths.root,
            steps: candidates.map { id, title, path in
                WorkspaceStepStatus(
                    id: id,
                    title: title,
                    state: fileManager.fileExists(atPath: path) ? .present : .missing,
                    path: path
                )
            }
        )
    }
}

public struct WorkspaceSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String { releaseID }
    public var releaseID: String
    public var root: String
    public var appSlug: String?
    public var createdAt: Date?
    public var completeStepCount: Int
    public var totalStepCount: Int

    public init(
        releaseID: String,
        root: String,
        appSlug: String?,
        createdAt: Date?,
        completeStepCount: Int,
        totalStepCount: Int
    ) {
        self.releaseID = releaseID
        self.root = root
        self.appSlug = appSlug
        self.createdAt = createdAt
        self.completeStepCount = completeStepCount
        self.totalStepCount = totalStepCount
    }
}

public struct WorkspaceList: Codable, Equatable, Sendable {
    public var baseDirectory: String
    public var generatedAt: Date
    public var releases: [WorkspaceSummary]

    public init(baseDirectory: String, generatedAt: Date = Date(), releases: [WorkspaceSummary]) {
        self.baseDirectory = baseDirectory
        self.generatedAt = generatedAt
        self.releases = releases
    }
}

public struct WorkspaceLister {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func list(baseDirectory: URL) -> WorkspaceList {
        let releasesRoot = baseDirectory
            .appendingPathComponent(".ascendkit")
            .appendingPathComponent("releases")
        guard let contents = try? fileManager.contentsOfDirectory(
            at: releasesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return WorkspaceList(baseDirectory: baseDirectory.path, releases: [])
        }

        let statusReader = WorkspaceStatusReader(fileManager: fileManager)
        let summaries = contents.compactMap { url -> WorkspaceSummary? in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            let workspace = ReleaseWorkspace(releaseID: url.lastPathComponent, root: url)
            let status = statusReader.read(workspace: workspace)
            let manifest = try? ReleaseWorkspaceStore(fileManager: fileManager).loadManifest(from: workspace)
            return WorkspaceSummary(
                releaseID: workspace.releaseID,
                root: workspace.paths.root,
                appSlug: manifest?.appSlug,
                createdAt: manifest?.createdAt,
                completeStepCount: status.completeStepCount,
                totalStepCount: status.steps.count
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (lhsDate?, rhsDate?):
                return lhsDate > rhsDate
            default:
                return lhs.releaseID < rhs.releaseID
            }
        }

        return WorkspaceList(baseDirectory: baseDirectory.path, releases: summaries)
    }
}
