import Foundation

public enum AgentReleasePhase: String, Codable, Equatable, Sendable, CaseIterable {
    case intake
    case screenshotsCapture
    case screenshotsUpload
    case buildSelection
    case metadataSync
    case complianceAndPrivacy
    case readyToSubmit
    case waitingForReview
    case complete
}

public struct AgentAdviseReport: Codable, Equatable, Sendable {
    public var ascendKitVersion: String?
    public var generatedAt: Date
    public var releaseID: String
    public var workspacePath: String
    public var phase: AgentReleasePhase
    public var readyForNextStep: Bool
    public var statusSummary: String
    public var blockers: [String]
    public var ignorableWarnings: [String]
    public var recommendedCommand: String
    public var agentPrompt: String

    public init(
        ascendKitVersion: String? = AscendKitVersion.current,
        generatedAt: Date = Date(),
        releaseID: String,
        workspacePath: String,
        phase: AgentReleasePhase,
        readyForNextStep: Bool,
        statusSummary: String,
        blockers: [String] = [],
        ignorableWarnings: [String] = [],
        recommendedCommand: String,
        agentPrompt: String
    ) {
        self.ascendKitVersion = ascendKitVersion
        self.generatedAt = generatedAt
        self.releaseID = releaseID
        self.workspacePath = workspacePath
        self.phase = phase
        self.readyForNextStep = readyForNextStep
        self.statusSummary = statusSummary
        self.blockers = blockers
        self.ignorableWarnings = ignorableWarnings
        self.recommendedCommand = recommendedCommand
        self.agentPrompt = agentPrompt
    }
}

public struct AgentAdvisor {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func advise(workspace: ReleaseWorkspace) -> AgentAdviseReport {
        let summaryReader = ReleaseWorkspaceSummaryReader(fileManager: fileManager)
        let summary = summaryReader.read(workspace: workspace)
        let paths = workspace.paths

        var blockers: [String] = []
        var ignorableWarnings: [String] = []

        // Standard ignorable warnings that agents often get tripped up on
        ignorableWarnings.append("HTTP 409 on content-rights (contentRightsDeclaration) is safe to ignore if already declared on App Store Connect.")
        ignorableWarnings.append("HTTP 409 on primary category or age rating declaration is safe to ignore if already set/locked.")
        ignorableWarnings.append("HTTP 409 on build export compliance is safe to ignore if usesNonExemptEncryption is already false.")
        ignorableWarnings.append("Skipping Iris dataUsages on HTTP 401 is safe if App Privacy is publishedDataNotCollected or manually confirmed.")

        // 1. Check if already submitted or complete
        if let submissionResult = load(ReviewSubmissionExecutionResult.self, path: paths.reviewSubmissionResult),
           submissionResult.submitted {
            return AgentAdviseReport(
                releaseID: workspace.releaseID,
                workspacePath: paths.root,
                phase: .waitingForReview,
                readyForNextStep: true,
                statusSummary: "Review submission has been executed successfully and is in review queue.",
                blockers: [],
                ignorableWarnings: ignorableWarnings,
                recommendedCommand: "ascendkit workspace summary --workspace \"\(paths.root)\" --json",
                agentPrompt: "Release \(workspace.releaseID) has been submitted for review. Monitor App Store Connect for approval. Do not attempt to resubmit or alter the version unless rejected."
            )
        }

        // 2. Check intake / manifest
        guard fileManager.fileExists(atPath: paths.manifest) else {
            return AgentAdviseReport(
                releaseID: workspace.releaseID,
                workspacePath: paths.root,
                phase: .intake,
                readyForNextStep: false,
                statusSummary: "Release manifest does not exist.",
                blockers: ["Release manifest does not exist."],
                ignorableWarnings: ignorableWarnings,
                recommendedCommand: "ascendkit intake init --app-root . --release-id \(workspace.releaseID)",
                agentPrompt: "Initialize the release workspace by running intake init to discover targets, app info, and entitlements."
            )
        }

        // 3. Check screenshots
        let hasScreenshotPlan = fileManager.fileExists(atPath: paths.screenshotPlan)
        let hasComposition = fileManager.fileExists(atPath: paths.screenshotCompositionManifest)
        let hasUploadResult = fileManager.fileExists(atPath: paths.screenshotUploadResult)

        if !hasComposition && !hasUploadResult {
            let cmd = hasScreenshotPlan
                ? "ascendkit screenshots capture-plan --workspace \"\(paths.root)\""
                : "ascendkit screenshots plan --workspace \"\(paths.root)\""
            return AgentAdviseReport(
                releaseID: workspace.releaseID,
                workspacePath: paths.root,
                phase: .screenshotsCapture,
                readyForNextStep: false,
                statusSummary: "Screenshots need to be planned, captured, imported, or composed.",
                blockers: ["Screenshot composition manifest is missing."],
                ignorableWarnings: ignorableWarnings,
                recommendedCommand: cmd,
                agentPrompt: "Prepare release screenshots. Run capture or import commands, then compose with framed posters before uploading to App Store Connect."
            )
        }

        if !hasUploadResult {
            return AgentAdviseReport(
                releaseID: workspace.releaseID,
                workspacePath: paths.root,
                phase: .screenshotsUpload,
                readyForNextStep: false,
                statusSummary: "Composed screenshots exist but have not been uploaded to App Store Connect.",
                blockers: ["Screenshot upload result is missing."],
                ignorableWarnings: ignorableWarnings,
                recommendedCommand: "ascendkit screenshots upload-plan --workspace \"\(paths.root)\"",
                agentPrompt: "Generate a screenshot upload plan and execute upload to App Store Connect. Ensure all uploaded screenshots reach COMPLETE delivery status."
            )
        }

        // 4. Check build candidates
        let hasBuildCandidates = fileManager.fileExists(atPath: paths.buildCandidates)
        let reviewPlan = load(ReviewSubmissionPlan.self, path: paths.reviewSubmissionPlan)
        let selectedBuildID = reviewPlan?.selectedBuildID

        if !hasBuildCandidates || selectedBuildID == nil {
            return AgentAdviseReport(
                releaseID: workspace.releaseID,
                workspacePath: paths.root,
                phase: .buildSelection,
                readyForNextStep: false,
                statusSummary: "A valid Xcode Cloud build candidate must be observed and selected.",
                blockers: ["No selected build candidate recorded in the workspace."],
                ignorableWarnings: ignorableWarnings,
                recommendedCommand: "ascendkit asc builds observe --workspace \"\(paths.root)\"",
                agentPrompt: "Query App Store Connect for eligible Xcode Cloud builds. Select a build candidate whose processingState is VALID before submitting."
            )
        }

        // 5. Check metadata diffs & whatsNew
        let metadataStatus = ASCMetadataStatusBuilder().build(
            applyResult: load(ASCMetadataApplyResult.self, path: paths.ascMetadataApplyResult),
            diffReport: load(MetadataDiffReport.self, path: paths.ascDiff)
        )
        if let blockingDiffs = metadataStatus.blockingDiffCount, blockingDiffs > 0 {
            blockers.append("\(blockingDiffs) blocking metadata difference(s) remain unsynced.")
            return AgentAdviseReport(
                releaseID: workspace.releaseID,
                workspacePath: paths.root,
                phase: .metadataSync,
                readyForNextStep: false,
                statusSummary: "Localized metadata differences need to be applied to App Store Connect.",
                blockers: blockers,
                ignorableWarnings: ignorableWarnings,
                recommendedCommand: "ascendkit asc metadata plan --workspace \"\(paths.root)\"",
                agentPrompt: "Sync localized metadata differences to App Store Connect. Ensure promotionalText and whatsNew are populated across all supported locales."
            )
        }

        // 6. Check compliance & review details
        let appPrivacyStatus = load(AppPrivacyStatus.self, path: paths.ascPrivacyStatus)
        if appPrivacyStatus?.readyForSubmission != true {
            blockers.append("App Privacy answers are not confirmed or published.")
            return AgentAdviseReport(
                releaseID: workspace.releaseID,
                workspacePath: paths.root,
                phase: .complianceAndPrivacy,
                readyForNextStep: false,
                statusSummary: "App Privacy declarations must be confirmed.",
                blockers: blockers,
                ignorableWarnings: ignorableWarnings,
                recommendedCommand: "ascendkit asc privacy confirm-manual --workspace \"\(paths.root)\" --data-not-collected",
                agentPrompt: "Confirm App Privacy status before submission. If no user data is collected, confirm data-not-collected."
            )
        }

        // 7. Ready to submit
        if summary.readyForManualReviewSubmission == true && summary.remoteSubmissionExecutionAllowed == true {
            return AgentAdviseReport(
                releaseID: workspace.releaseID,
                workspacePath: paths.root,
                phase: .readyToSubmit,
                readyForNextStep: true,
                statusSummary: "All preflight checks, builds, screenshots, metadata, and privacy requirements are satisfied. Ready to submit.",
                blockers: [],
                ignorableWarnings: ignorableWarnings,
                recommendedCommand: "ascendkit submit execute --workspace \"\(paths.root)\" --confirm-remote-submission",
                agentPrompt: "Execute final review submission with `ascendkit submit execute --workspace \"\(paths.root)\" --confirm-remote-submission`. Verify the version transitions to WAITING_FOR_REVIEW with releaseType=AFTER_APPROVAL."
            )
        }

        // Default: inspection or preflight needed
        return AgentAdviseReport(
            releaseID: workspace.releaseID,
            workspacePath: paths.root,
            phase: .readyToSubmit,
            readyForNextStep: false,
            statusSummary: "Run submission preflight to verify all readiness conditions.",
            blockers: summary.nextActions.filter { $0.severity == .blocker }.map { $0.title },
            ignorableWarnings: ignorableWarnings,
            recommendedCommand: "ascendkit submit preflight --workspace \"\(paths.root)\" --remote --json",
            agentPrompt: "Run submit preflight with remote verification to identify any remaining release blockers."
        )
    }

    private func load<T: Decodable>(_ type: T.Type, path: String) -> T? {
        guard fileManager.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? AscendKitJSON.decoder.decode(T.self, from: data)
    }
}
