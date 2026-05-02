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
            ("screenshot-capture-plan", "Screenshot capture plan", workspace.paths.screenshotCapturePlan),
            ("screenshot-capture-result", "Screenshot capture result", workspace.paths.screenshotCaptureResult),
            ("screenshot-import", "Screenshot import manifest", workspace.paths.screenshotImportManifest),
            ("screenshot-copy-lint", "Screenshot copy lint report", workspace.paths.screenshotCopyLint),
            ("screenshot-composition", "Screenshot composition manifest", workspace.paths.screenshotCompositionManifest),
            ("screenshot-workflow-result", "Screenshot local workflow result", workspace.paths.screenshotWorkflowResult),
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

public enum WorkspaceHygieneSeverity: String, Codable, Equatable, Sendable {
    case warning
    case blocker
}

public struct WorkspaceHygieneFinding: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var severity: WorkspaceHygieneSeverity
    public var path: String
    public var reason: String

    public init(id: String, severity: WorkspaceHygieneSeverity, path: String, reason: String) {
        self.id = id
        self.severity = severity
        self.path = path
        self.reason = reason
    }
}

public struct WorkspaceHygieneReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var releaseID: String
    public var root: String
    public var safeForPublicCommit: Bool
    public var findings: [WorkspaceHygieneFinding]
    public var nextActions: [String]

    public init(
        generatedAt: Date = Date(),
        releaseID: String,
        root: String,
        findings: [WorkspaceHygieneFinding],
        nextActions: [String]
    ) {
        self.generatedAt = generatedAt
        self.releaseID = releaseID
        self.root = root
        self.findings = findings
        self.safeForPublicCommit = findings.contains { $0.severity == .blocker } == false
        self.nextActions = nextActions
    }
}

public struct WorkspaceHygieneScanner {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(workspace: ReleaseWorkspace) -> WorkspaceHygieneReport {
        let rootURL = URL(fileURLWithPath: workspace.paths.root)
        let files = workspaceFiles(rootURL: rootURL)
        var findings: [WorkspaceHygieneFinding] = [
            WorkspaceHygieneFinding(
                id: "workspace.local-artifacts",
                severity: .blocker,
                path: relativePath(rootURL.path, root: rootURL),
                reason: "Release workspaces contain release-specific local state and should not be committed."
            )
        ]

        for file in files {
            let relative = relativePath(file.path, root: rootURL)
            findings.append(contentsOf: pathFindings(relativePath: relative))
            findings.append(contentsOf: contentFindings(fileURL: file, relativePath: relative))
        }

        return WorkspaceHygieneReport(
            releaseID: workspace.releaseID,
            root: workspace.paths.root,
            findings: deduplicated(findings).sorted { $0.id < $1.id },
            nextActions: [
                "Keep .ascendkit/ out of git and public archives.",
                "Share sanitized command output or workspace summary instead of raw workspace files.",
                "Store ASC keys outside repositories and reference them through env, file, or keychain providers."
            ]
        )
    }

    private func workspaceFiles(rootURL: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url
        }
    }

    private func pathFindings(relativePath: String) -> [WorkspaceHygieneFinding] {
        var findings: [WorkspaceHygieneFinding] = []
        let lowercased = relativePath.lowercased()
        if lowercased.hasSuffix(".p8") || lowercased.hasSuffix(".pem") || lowercased.hasSuffix(".key") {
            findings.append(.init(
                id: "workspace.secret-key-file.\(stableID(relativePath))",
                severity: .blocker,
                path: relativePath,
                reason: "Potential private key file found in the workspace."
            ))
        }
        if lowercased.hasPrefix("review/") {
            findings.append(.init(
                id: "workspace.review-artifact.\(stableID(relativePath))",
                severity: .blocker,
                path: relativePath,
                reason: "Review artifacts can contain reviewer contact, access notes, or submission state."
            ))
        }
        if lowercased.hasPrefix("screenshots/") && isImagePath(lowercased) {
            findings.append(.init(
                id: "workspace.screenshot-artifact.\(stableID(relativePath))",
                severity: .blocker,
                path: relativePath,
                reason: "Screenshot image artifacts can contain unreleased product or user data."
            ))
        }
        if lowercased == "asc/auth.json" {
            findings.append(.init(
                id: "workspace.asc-auth-config",
                severity: .blocker,
                path: relativePath,
                reason: "ASC auth config should contain references only, but still reveals key identifiers and provider paths."
            ))
        }
        if lowercased.hasPrefix("asc/") {
            findings.append(.init(
                id: "workspace.asc-state.\(stableID(relativePath))",
                severity: .warning,
                path: relativePath,
                reason: "ASC state files can reveal app identifiers, build IDs, metadata, pricing, or App Privacy state."
            ))
        }
        return findings
    }

    private func contentFindings(fileURL: URL, relativePath: String) -> [WorkspaceHygieneFinding] {
        guard let data = try? Data(contentsOf: fileURL),
              data.count <= 1_000_000,
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        let sensitiveMarkers = [
            "BEGIN PRIVATE KEY",
            "BEGIN EC PRIVATE KEY",
            "BEGIN OPENSSH PRIVATE KEY",
            "PRIVATE KEY",
            "bearer "
        ]
        guard sensitiveMarkers.contains(where: { content.localizedCaseInsensitiveContains($0) }) else {
            return []
        }
        return [
            WorkspaceHygieneFinding(
                id: "workspace.sensitive-content.\(stableID(relativePath))",
                severity: .blocker,
                path: relativePath,
                reason: "Potential plaintext secret material was detected by marker scan."
            )
        ]
    }

    private func relativePath(_ path: String, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardizedPath.hasPrefix(rootPath) else {
            return path
        }
        let remainder = String(standardizedPath.dropFirst(rootPath.count))
        return remainder.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
            ? "."
            : remainder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func isImagePath(_ path: String) -> Bool {
        [".png", ".jpg", ".jpeg", ".heic", ".tif", ".tiff", ".webp"].contains { path.hasSuffix($0) }
    }

    private func deduplicated(_ findings: [WorkspaceHygieneFinding]) -> [WorkspaceHygieneFinding] {
        var seen = Set<String>()
        return findings.filter { seen.insert($0.id).inserted }
    }

    private func stableID(_ value: String) -> String {
        value
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" {
                    result.append(character)
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

public enum ReleaseActionSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case blocker
}

public struct ReleaseActionItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var severity: ReleaseActionSeverity

    public init(id: String, title: String, detail: String, severity: ReleaseActionSeverity) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
    }
}

public struct ReleaseWorkspaceSummary: Codable, Equatable, Sendable {
    public var releaseID: String
    public var root: String
    public var generatedAt: Date
    public var submissionReadinessReady: Bool?
    public var readyForManualReviewSubmission: Bool?
    public var remoteSubmissionExecutionAllowed: Bool?
    public var appPrivacyReadyForSubmission: Bool?
    public var appPrivacyState: String?
    public var screenshotWorkflowReadyForUploadPlan: Bool?
    public var nextActions: [ReleaseActionItem]

    public init(
        releaseID: String,
        root: String,
        generatedAt: Date = Date(),
        submissionReadinessReady: Bool?,
        readyForManualReviewSubmission: Bool?,
        remoteSubmissionExecutionAllowed: Bool?,
        appPrivacyReadyForSubmission: Bool?,
        appPrivacyState: String?,
        screenshotWorkflowReadyForUploadPlan: Bool?,
        nextActions: [ReleaseActionItem]
    ) {
        self.releaseID = releaseID
        self.root = root
        self.generatedAt = generatedAt
        self.submissionReadinessReady = submissionReadinessReady
        self.readyForManualReviewSubmission = readyForManualReviewSubmission
        self.remoteSubmissionExecutionAllowed = remoteSubmissionExecutionAllowed
        self.appPrivacyReadyForSubmission = appPrivacyReadyForSubmission
        self.appPrivacyState = appPrivacyState
        self.screenshotWorkflowReadyForUploadPlan = screenshotWorkflowReadyForUploadPlan
        self.nextActions = nextActions
    }
}

public struct ReleaseWorkspaceSummaryReader {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func read(workspace: ReleaseWorkspace) -> ReleaseWorkspaceSummary {
        let readiness = load(SubmissionReadinessReport.self, path: workspace.paths.readiness)
        let reviewPlan = load(ReviewSubmissionPlan.self, path: workspace.paths.reviewSubmissionPlan)
        let appPrivacyStatus = load(AppPrivacyStatus.self, path: workspace.paths.ascPrivacyStatus) ?? AppPrivacyStatus(
            state: .unknown,
            source: "workspace",
            findings: ["No App Privacy status has been recorded."]
        )
        let screenshotWorkflowStatus = ScreenshotWorkflowStatusBuilder().build(
            capturePlan: load(ScreenshotCapturePlan.self, path: workspace.paths.screenshotCapturePlan),
            captureResult: load(ScreenshotCaptureExecutionResult.self, path: workspace.paths.screenshotCaptureResult),
            importManifest: load(ScreenshotImportManifest.self, path: workspace.paths.screenshotImportManifest),
            copyLintReport: load(ScreenshotCompositionCopyLintReport.self, path: workspace.paths.screenshotCopyLint),
            compositionManifest: load(ScreenshotCompositionManifest.self, path: workspace.paths.screenshotCompositionManifest),
            workflowResult: load(ScreenshotLocalWorkflowResult.self, path: workspace.paths.screenshotWorkflowResult),
            uploadPlan: load(ScreenshotUploadPlan.self, path: workspace.paths.screenshotUploadPlan),
            paths: workspace.paths
        )
        let screenshotUploadStatus = ScreenshotUploadStatusBuilder().build(
            plan: load(ScreenshotUploadPlan.self, path: workspace.paths.screenshotUploadPlan),
            result: load(ScreenshotUploadExecutionResult.self, path: workspace.paths.screenshotUploadResult)
        )
        let screenshotCoverage = ScreenshotCoverageBuilder().build(
            plan: load(ScreenshotPlan.self, path: workspace.paths.screenshotPlan),
            importManifest: load(ScreenshotImportManifest.self, path: workspace.paths.screenshotImportManifest),
            compositionManifest: load(ScreenshotCompositionManifest.self, path: workspace.paths.screenshotCompositionManifest),
            uploadPlan: load(ScreenshotUploadPlan.self, path: workspace.paths.screenshotUploadPlan)
        )
        let metadataStatus = ASCMetadataSyncStatusBuilder().build(
            applyResult: load(ASCMetadataApplyResult.self, path: workspace.paths.ascMetadataApplyResult),
            diffReport: load(MetadataDiffReport.self, path: workspace.paths.ascDiff)
        )

        var actions: [ReleaseActionItem] = []

        if let readiness {
            for item in readiness.items where !item.satisfied {
                actions.append(.init(
                    id: "readiness.\(item.id)",
                    title: item.title,
                    detail: item.note ?? "Resolve this readiness checklist item.",
                    severity: .blocker
                ))
            }
        } else {
            actions.append(.init(
                id: "readiness.missing",
                title: "Submission readiness has not been generated",
                detail: "Run submit readiness --workspace PATH.",
                severity: .blocker
            ))
        }

        if let reviewPlan {
            for (index, finding) in reviewPlan.findings.enumerated() {
                actions.append(.init(
                    id: "review-plan.finding.\(index + 1)",
                    title: "Review plan finding",
                    detail: finding,
                    severity: reviewPlanFindingSeverity(finding, plan: reviewPlan)
                ))
            }
            if reviewPlan.readyForManualReviewSubmission && !reviewPlan.remoteSubmissionExecutionAllowed {
                actions.append(.init(
                    id: "review.submit-manual",
                    title: "Complete final App Review submission manually",
                    detail: "Run submit handoff, then submit the prepared version in App Store Connect. Remote submission execution is boundary-disabled.",
                    severity: .info
                ))
            }
        } else {
            actions.append(.init(
                id: "review-plan.missing",
                title: "Review submission plan has not been generated",
                detail: "Run submit review-plan --workspace PATH, then submit handoff --workspace PATH.",
                severity: .blocker
            ))
        }

        if !appPrivacyStatus.readyForSubmission {
            for (index, action) in appPrivacyStatus.nextActions.enumerated() {
                actions.append(.init(
                    id: "app-privacy.next-action.\(index + 1)",
                    title: "App Privacy next action",
                    detail: action,
                    severity: .blocker
                ))
            }
        }

        if !screenshotWorkflowStatus.readyForUploadPlan {
            for (index, finding) in screenshotWorkflowStatus.findings.enumerated() {
                actions.append(.init(
                    id: "screenshots.workflow.finding.\(index + 1)",
                    title: "Screenshot workflow finding",
                    detail: finding,
                    severity: .warning
                ))
            }
        }

        if screenshotUploadStatus.failedCount > 0 {
            for (index, action) in screenshotUploadStatus.nextActions.enumerated() {
                actions.append(.init(
                    id: "screenshots.upload.next-action.\(index + 1)",
                    title: "Screenshot upload next action",
                    detail: action,
                    severity: .warning
                ))
            }
        }

        if !screenshotCoverage.complete {
            for (index, finding) in screenshotCoverage.findings.enumerated() {
                actions.append(.init(
                    id: "screenshots.coverage.finding.\(index + 1)",
                    title: "Screenshot coverage finding",
                    detail: finding,
                    severity: .warning
                ))
            }
        }

        if !metadataStatus.readyForReviewPlan {
            for (index, action) in metadataStatus.nextActions.enumerated() {
                actions.append(.init(
                    id: "metadata.next-action.\(index + 1)",
                    title: "Metadata next action",
                    detail: action,
                    severity: .blocker
                ))
            }
        }

        return ReleaseWorkspaceSummary(
            releaseID: workspace.releaseID,
            root: workspace.paths.root,
            submissionReadinessReady: readiness?.ready,
            readyForManualReviewSubmission: reviewPlan?.readyForManualReviewSubmission,
            remoteSubmissionExecutionAllowed: reviewPlan?.remoteSubmissionExecutionAllowed,
            appPrivacyReadyForSubmission: appPrivacyStatus.readyForSubmission,
            appPrivacyState: appPrivacyStatus.state.rawValue,
            screenshotWorkflowReadyForUploadPlan: screenshotWorkflowStatus.readyForUploadPlan,
            nextActions: deduplicated(actions)
        )
    }

    private func load<T: Decodable>(_ type: T.Type, path: String) -> T? {
        guard fileManager.fileExists(atPath: path),
              let data = fileManager.contents(atPath: path) else {
            return nil
        }
        return try? AscendKitJSON.decoder.decode(type, from: data)
    }

    private func deduplicated(_ actions: [ReleaseActionItem]) -> [ReleaseActionItem] {
        var seen = Set<String>()
        var result: [ReleaseActionItem] = []
        for action in actions {
            let key = "\(action.title)\n\(action.detail)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(action)
        }
        return result
    }

    private func reviewPlanFindingSeverity(_ finding: String, plan: ReviewSubmissionPlan) -> ReleaseActionSeverity {
        if finding.contains("Remote review submission execution is intentionally disabled") {
            return .info
        }
        if finding.contains("releaseNotes/whatsNew remains unsynced") {
            return .warning
        }
        return plan.readyForManualReviewSubmission ? .warning : .blocker
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
