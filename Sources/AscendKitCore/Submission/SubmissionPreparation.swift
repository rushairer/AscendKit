import Foundation

public struct SubmissionPreparation: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var releaseID: String
    public var appSlug: String
    public var ready: Bool
    public var checklist: [SubmissionChecklistItem]
    public var targetSummaries: [String]
    public var metadataLocales: [String]
    public var screenshotArtifactCount: Int
    public var composedScreenshotArtifactCount: Int
    public var ascLookupStepCount: Int
    public var ascLookupFindingCount: Int?
    public var processableBuildCount: Int
    public var iapFindingCount: Int?
    public var reviewNotesPresent: Bool

    public init(
        generatedAt: Date = Date(),
        releaseID: String,
        appSlug: String,
        ready: Bool,
        checklist: [SubmissionChecklistItem],
        targetSummaries: [String],
        metadataLocales: [String],
        screenshotArtifactCount: Int,
        composedScreenshotArtifactCount: Int,
        ascLookupStepCount: Int,
        ascLookupFindingCount: Int?,
        processableBuildCount: Int,
        iapFindingCount: Int?,
        reviewNotesPresent: Bool
    ) {
        self.generatedAt = generatedAt
        self.releaseID = releaseID
        self.appSlug = appSlug
        self.ready = ready
        self.checklist = checklist
        self.targetSummaries = targetSummaries
        self.metadataLocales = metadataLocales
        self.screenshotArtifactCount = screenshotArtifactCount
        self.composedScreenshotArtifactCount = composedScreenshotArtifactCount
        self.ascLookupStepCount = ascLookupStepCount
        self.ascLookupFindingCount = ascLookupFindingCount
        self.processableBuildCount = processableBuildCount
        self.iapFindingCount = iapFindingCount
        self.reviewNotesPresent = reviewNotesPresent
    }
}

public struct SubmissionPreparationBuilder {
    public init() {}

    public func build(
        manifest: ReleaseManifest,
        readiness: SubmissionReadinessReport,
        metadataLintReports: [MetadataLintReport],
        screenshotImportManifest: ScreenshotImportManifest?,
        screenshotCompositionManifest: ScreenshotCompositionManifest? = nil,
        ascLookupPlan: ASCLookupPlan? = nil,
        buildCandidatesReport: BuildCandidatesReport?,
        iapValidationReport: IAPValidationReport?,
        reviewInfo: ReviewInfo?
    ) -> SubmissionPreparation {
        SubmissionPreparation(
            releaseID: manifest.releaseID,
            appSlug: manifest.appSlug,
            ready: readiness.ready,
            checklist: readiness.items,
            targetSummaries: manifest.targets
                .filter(\.isAppStoreApplication)
                .map { target in
                    let bundleID = target.bundleIdentifier ?? "unknown-bundle-id"
                    let version = target.version.marketingVersion ?? "unknown-version"
                    let build = target.version.buildNumber ?? "unknown-build"
                    return "\(target.name) (\(bundleID)) \(version) build \(build)"
                },
            metadataLocales: metadataLintReports.map(\.locale).sorted(),
            screenshotArtifactCount: screenshotImportManifest?.artifacts.count ?? 0,
            composedScreenshotArtifactCount: screenshotCompositionManifest?.artifacts.count ?? 0,
            ascLookupStepCount: ascLookupPlan?.steps.count ?? 0,
            ascLookupFindingCount: ascLookupPlan?.findings.count,
            processableBuildCount: buildCandidatesReport?.processableCandidates.count ?? 0,
            iapFindingCount: iapValidationReport?.findings.count,
            reviewNotesPresent: !(reviewInfo?.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        )
    }
}

public struct ReviewSubmissionPlan: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var releaseID: String
    public var appID: String?
    public var selectedBuildID: String?
    public var selectedBuildVersion: String?
    public var selectedBuildNumber: String?
    public var reviewerName: String?
    public var reviewerPhone: String?
    public var metadataApplied: Bool
    public var metadataRemainingDiffCount: Int?
    public var metadataRemainingBlockingDiffCount: Int?
    public var metadataApplyFindings: [String]
    public var screenshotArtifactCount: Int
    public var appPrivacyState: String?
    public var appPrivacySource: String?
    public var appPrivacyReadyForSubmission: Bool?
    public var appPrivacyNextActions: [String]?
    public var readinessReady: Bool
    public var readyForManualReviewSubmission: Bool
    public var remoteSubmissionExecutionAllowed: Bool
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        releaseID: String,
        appID: String?,
        selectedBuildID: String?,
        selectedBuildVersion: String?,
        selectedBuildNumber: String?,
        reviewerName: String?,
        reviewerPhone: String?,
        metadataApplied: Bool,
        metadataRemainingDiffCount: Int? = nil,
        metadataRemainingBlockingDiffCount: Int? = nil,
        metadataApplyFindings: [String] = [],
        screenshotArtifactCount: Int,
        appPrivacyState: String? = nil,
        appPrivacySource: String? = nil,
        appPrivacyReadyForSubmission: Bool? = nil,
        appPrivacyNextActions: [String]? = nil,
        readinessReady: Bool,
        readyForManualReviewSubmission: Bool,
        remoteSubmissionExecutionAllowed: Bool = false,
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.releaseID = releaseID
        self.appID = appID
        self.selectedBuildID = selectedBuildID
        self.selectedBuildVersion = selectedBuildVersion
        self.selectedBuildNumber = selectedBuildNumber
        self.reviewerName = reviewerName
        self.reviewerPhone = reviewerPhone
        self.metadataApplied = metadataApplied
        self.metadataRemainingDiffCount = metadataRemainingDiffCount
        self.metadataRemainingBlockingDiffCount = metadataRemainingBlockingDiffCount
        self.metadataApplyFindings = metadataApplyFindings
        self.screenshotArtifactCount = screenshotArtifactCount
        self.appPrivacyState = appPrivacyState
        self.appPrivacySource = appPrivacySource
        self.appPrivacyReadyForSubmission = appPrivacyReadyForSubmission
        self.appPrivacyNextActions = appPrivacyNextActions
        self.readinessReady = readinessReady
        self.readyForManualReviewSubmission = readyForManualReviewSubmission
        self.remoteSubmissionExecutionAllowed = remoteSubmissionExecutionAllowed
        self.findings = findings
    }
}

public struct ReviewSubmissionPlanBuilder {
    public init() {}

    public func build(
        manifest: ReleaseManifest,
        reviewInfo: ReviewInfo?,
        readiness: SubmissionReadinessReport,
        screenshotCompositionManifest: ScreenshotCompositionManifest?,
        appsLookupReport: ASCAppsLookupReport?,
        metadataApplyResult: ASCMetadataApplyResult?,
        metadataDiffReport: MetadataDiffReport?,
        appPrivacyStatus: AppPrivacyStatus? = nil,
        buildCandidatesReport: BuildCandidatesReport?
    ) -> ReviewSubmissionPlan {
        let target = manifest.targets.first(where: \.isAppStoreApplication)
        let selectedBuild = buildCandidatesReport?.preferredCandidate(
            version: target?.version.marketingVersion,
            buildNumber: target?.version.buildNumber,
            platform: target?.platform
        )
        let remainingDiffs = metadataDiffReport?.diffs.filter { $0.status != .unchanged }
        let blockingMetadataDiffs = remainingDiffs?.filter { $0.field != "releaseNotes" }
        let metadataApplied = metadataApplyResult?.applied == true
        let metadataDiffFresh = Self.metadataDiffIsFresh(
            metadataApplied: metadataApplied,
            metadataApplyResult: metadataApplyResult,
            metadataDiffReport: metadataDiffReport
        )
        let effectiveAppPrivacyStatus = appPrivacyStatus ?? AppPrivacyStatus(
            state: .unknown,
            source: "workspace",
            findings: ["No App Privacy status has been recorded."]
        )

        var findings: [String] = []
        if !readiness.ready {
            findings.append("Submission readiness is not complete.")
        }
        if selectedBuild == nil {
            findings.append("No processable ASC build candidate is selected.")
        }
        if !metadataApplied {
            findings.append("ASC metadata apply has not completed.")
        }
        if metadataApplied && metadataDiffReport == nil {
            findings.append("ASC metadata diff has not been observed after metadata apply.")
        }
        if metadataApplied,
           let metadataApplyResult,
           let metadataDiffReport,
           metadataDiffReport.generatedAt < metadataApplyResult.generatedAt {
            findings.append("ASC metadata diff is older than the latest metadata apply; re-run asc metadata observe and metadata diff.")
        }
        if let blockingMetadataDiffs, !blockingMetadataDiffs.isEmpty {
            findings.append("\(blockingMetadataDiffs.count) blocking metadata diff(s) remain after ASC observation.")
        }
        if remainingDiffs?.contains(where: { $0.field == "releaseNotes" }) == true {
            findings.append("releaseNotes/whatsNew remains unsynced because App Store Connect rejected edits in the current version state.")
        }
        if !effectiveAppPrivacyStatus.readyForSubmission {
            if appPrivacyStatus != nil {
                let statusFindings = effectiveAppPrivacyStatus.findings.isEmpty
                    ? ""
                    : " Findings: \(effectiveAppPrivacyStatus.findings.joined(separator: " "))"
                findings.append("App Privacy answers are not recorded as published. Current state: \(effectiveAppPrivacyStatus.state.rawValue) via \(effectiveAppPrivacyStatus.source).\(statusFindings) Run asc privacy status, then complete App Privacy in App Store Connect UI or run asc privacy confirm-manual after publishing.")
            } else {
                findings.append("App Privacy answers are not recorded as published. Run asc privacy status, then complete App Privacy in App Store Connect UI or run asc privacy confirm-manual after publishing.")
            }
        }
        findings.append("Remote review submission execution is intentionally disabled in this MVP boundary.")

        let reviewerName = reviewInfo.map {
            "\($0.contact.firstName) \($0.contact.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let readyForManualReviewSubmission = readiness.ready &&
            selectedBuild != nil &&
            metadataApplied &&
            metadataDiffFresh &&
            effectiveAppPrivacyStatus.readyForSubmission &&
            (blockingMetadataDiffs?.isEmpty == true)

        return ReviewSubmissionPlan(
            releaseID: manifest.releaseID,
            appID: appsLookupReport?.apps.first?.id,
            selectedBuildID: selectedBuild?.id,
            selectedBuildVersion: selectedBuild?.version,
            selectedBuildNumber: selectedBuild?.buildNumber,
            reviewerName: reviewerName?.isEmpty == true ? nil : reviewerName,
            reviewerPhone: reviewInfo?.contact.phone,
            metadataApplied: metadataApplied,
            metadataRemainingDiffCount: remainingDiffs?.count,
            metadataRemainingBlockingDiffCount: blockingMetadataDiffs?.count,
            metadataApplyFindings: metadataApplyResult?.findings ?? [],
            screenshotArtifactCount: screenshotCompositionManifest?.artifacts.count ?? 0,
            appPrivacyState: effectiveAppPrivacyStatus.state.rawValue,
            appPrivacySource: effectiveAppPrivacyStatus.source,
            appPrivacyReadyForSubmission: effectiveAppPrivacyStatus.readyForSubmission,
            appPrivacyNextActions: effectiveAppPrivacyStatus.nextActions,
            readinessReady: readiness.ready,
            readyForManualReviewSubmission: readyForManualReviewSubmission,
            findings: findings
        )
    }

    private static func metadataDiffIsFresh(
        metadataApplied: Bool,
        metadataApplyResult: ASCMetadataApplyResult?,
        metadataDiffReport: MetadataDiffReport?
    ) -> Bool {
        guard metadataApplied, let metadataApplyResult, let metadataDiffReport else {
            return false
        }
        return metadataDiffReport.generatedAt >= metadataApplyResult.generatedAt
    }
}

public struct ReviewSubmissionExecutionResult: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var executed: Bool
    public var appStoreVersionID: String?
    public var buildID: String?
    public var appStoreReviewDetailID: String?
    public var reviewSubmissionID: String?
    public var reviewSubmissionItemID: String?
    public var submitted: Bool
    public var responses: [ReviewSubmissionExecutionResponse]
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        executed: Bool,
        appStoreVersionID: String? = nil,
        buildID: String? = nil,
        appStoreReviewDetailID: String? = nil,
        reviewSubmissionID: String? = nil,
        reviewSubmissionItemID: String? = nil,
        submitted: Bool = false,
        responses: [ReviewSubmissionExecutionResponse] = [],
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.executed = executed
        self.appStoreVersionID = appStoreVersionID
        self.buildID = buildID
        self.appStoreReviewDetailID = appStoreReviewDetailID
        self.reviewSubmissionID = reviewSubmissionID
        self.reviewSubmissionItemID = reviewSubmissionItemID
        self.submitted = submitted
        self.responses = responses
        self.findings = findings
    }

    public static func boundaryDisabled(appStoreVersionID: String?, buildID: String?) -> Self {
        Self(
            executed: false,
            appStoreVersionID: appStoreVersionID,
            buildID: buildID,
            findings: ["Remote review submission execution is disabled by the current AscendKit boundary. Use submit handoff and complete the final submit-for-review action manually in App Store Connect."]
        )
    }
}

public struct ReviewSubmissionExecutionResponse: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var method: String
    public var path: String
    public var statusCode: Int
    public var resourceID: String?

    public init(id: String, method: String, path: String, statusCode: Int, resourceID: String? = nil) {
        self.id = id
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.resourceID = resourceID
    }
}

public struct ReviewHandoffMarkdown {
    public init() {}

    public func render(plan: ReviewSubmissionPlan) -> String {
        let readiness = plan.readyForManualReviewSubmission ? "ready" : "not ready"
        let build = [
            plan.selectedBuildVersion,
            plan.selectedBuildNumber.map { "(\($0))" }
        ].compactMap { $0 }.joined(separator: " ")
        let findings = plan.findings.isEmpty
            ? "- None"
            : plan.findings.map { "- \($0)" }.joined(separator: "\n")
        let metadataFindings = plan.metadataApplyFindings.isEmpty
            ? "- None"
            : plan.metadataApplyFindings.map { "- \($0)" }.joined(separator: "\n")
        let appPrivacyReady = plan.appPrivacyReadyForSubmission.map { $0 ? "yes" : "no" } ?? "unknown"
        let appPrivacyNextActions: String
        if let nextActions = plan.appPrivacyNextActions, !nextActions.isEmpty {
            appPrivacyNextActions = nextActions.map { "- \($0)" }.joined(separator: "\n")
        } else {
            appPrivacyNextActions = "- None"
        }

        return """
        # AscendKit Review Handoff

        Release: \(plan.releaseID)
        Manual review submission readiness: \(readiness)
        Remote submission execution allowed: \(plan.remoteSubmissionExecutionAllowed ? "yes" : "no")

        ## App Store Connect

        - App ID: \(plan.appID ?? "unknown")
        - Selected build ID: \(plan.selectedBuildID ?? "none")
        - Selected build: \(build.isEmpty ? "none" : build)

        ## Reviewer

        - Reviewer: \(plan.reviewerName ?? "unknown")
        - Phone: \(plan.reviewerPhone ?? "unknown")

        ## Assets

        - Metadata applied: \(plan.metadataApplied ? "yes" : "no")
        - Remaining metadata diffs: \(plan.metadataRemainingDiffCount.map(String.init) ?? "unknown")
        - Blocking metadata diffs: \(plan.metadataRemainingBlockingDiffCount.map(String.init) ?? "unknown")
        - Composed screenshot artifacts: \(plan.screenshotArtifactCount)
        - Readiness checklist: \(plan.readinessReady ? "ready" : "not ready")

        ## App Privacy

        - State: \(plan.appPrivacyState ?? "unknown")
        - Source: \(plan.appPrivacySource ?? "unknown")
        - Ready for submission: \(appPrivacyReady)

        Next action(s):

        \(appPrivacyNextActions)

        ## Metadata Notes

        \(metadataFindings)

        ## Findings

        \(findings)

        ## Boundary

        AscendKit MVP does not execute remote review submission. Use this handoff to complete the final submit-for-review action manually in App Store Connect.
        """
    }
}
