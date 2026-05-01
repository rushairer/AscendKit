import Foundation

public struct SubmissionChecklistItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var satisfied: Bool
    public var note: String?

    public init(id: String, title: String, satisfied: Bool, note: String? = nil) {
        self.id = id
        self.title = title
        self.satisfied = satisfied
        self.note = note
    }
}

public struct SubmissionReadinessReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var items: [SubmissionChecklistItem]

    public init(generatedAt: Date = Date(), items: [SubmissionChecklistItem]) {
        self.generatedAt = generatedAt
        self.items = items
    }

    public var ready: Bool {
        items.allSatisfy(\.satisfied)
    }
}

public enum AppPrivacyState: String, Codable, Equatable, Sendable {
    case unknown
    case publishedDataNotCollected
    case requiresManualAppStoreConnect
}

public struct AppPrivacyStatus: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var state: AppPrivacyState
    public var source: String
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        state: AppPrivacyState,
        source: String,
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.state = state
        self.source = source
        self.findings = findings
    }

    public var readyForSubmission: Bool {
        state == .publishedDataNotCollected
    }
}

public struct SubmissionReadinessEvaluator {
    public init() {}

    public func evaluate(
        manifest: ReleaseManifest,
        doctorReport: DoctorReport? = nil,
        reviewInfo: ReviewInfo? = nil,
        metadataLintReports: [MetadataLintReport] = [],
        screenshotImportManifest: ScreenshotImportManifest? = nil,
        screenshotCopyLintReport: ScreenshotCompositionCopyLintReport? = nil,
        screenshotCompositionManifest: ScreenshotCompositionManifest? = nil,
        ascLookupPlan: ASCLookupPlan? = nil,
        appPrivacyStatus: AppPrivacyStatus? = nil,
        buildCandidatesReport: BuildCandidatesReport? = nil,
        iapValidationReport: IAPValidationReport? = nil
    ) -> SubmissionReadinessReport {
        let hasAppTarget = manifest.targets.contains { $0.isAppStoreApplication && $0.bundleIdentifier != nil }
        let hasDoctorBlockers = doctorReport?.hasBlockers ?? false
        let hasDoctorReport = doctorReport != nil
        let metadataLintFindingCount = metadataLintReports.reduce(0) { $0 + $1.findings.count }
        let hasMetadataLint = !metadataLintReports.isEmpty
        let screenshotArtifactCount = screenshotImportManifest?.artifacts.count ?? 0
        let composedScreenshotArtifactCount = screenshotCompositionManifest?.artifacts.count ?? 0
        let requiresScreenshotCopyLint = screenshotCompositionManifest?.mode == .framedPoster || screenshotCopyLintReport != nil
        let ascLookupPlanReady = ascLookupPlan?.authConfigured == true && (ascLookupPlan?.findings.isEmpty ?? false)
        let releaseTargets = manifest.targets.filter(\.isAppStoreApplication)
        let selectedBuild = releaseTargets.compactMap { target -> BuildCandidate? in
            guard let version = target.version.marketingVersion,
                  let buildNumber = target.version.buildNumber else {
                return nil
            }
            return buildCandidatesReport?.preferredCandidate(version: version, buildNumber: buildNumber)
        }.first
        let matchingProcessedBuild = selectedBuild != nil
        var items: [SubmissionChecklistItem] = [
            .init(id: "manifest.app-target", title: "Release manifest has an app target", satisfied: hasAppTarget),
            .init(
                id: "doctor.report",
                title: "Release doctor report exists",
                satisfied: hasDoctorReport,
                note: hasDoctorReport ? nil : "Run doctor release before final readiness."
            ),
            .init(id: "doctor.no-blockers", title: "Release doctor has no blockers", satisfied: hasDoctorReport && !hasDoctorBlockers)
        ]

        items.append(.init(
            id: "metadata.lint",
            title: "Metadata has been linted without findings",
            satisfied: hasMetadataLint && metadataLintFindingCount == 0,
            note: hasMetadataLint ? "\(metadataLintFindingCount) metadata lint finding(s)." : "Run metadata lint for release locales."
        ))

        items.append(.init(
            id: "screenshots.import",
            title: "Screenshot import manifest exists",
            satisfied: screenshotArtifactCount > 0,
            note: screenshotArtifactCount > 0 ? "\(screenshotArtifactCount) screenshot artifact(s) imported." : "Run screenshots plan/readiness/import or defer screenshot execution explicitly in a later workflow."
        ))

        items.append(.init(
            id: "screenshots.composition",
            title: "Screenshot composition manifest exists",
            satisfied: composedScreenshotArtifactCount > 0,
            note: composedScreenshotArtifactCount > 0 ? "\(composedScreenshotArtifactCount) composed screenshot artifact(s)." : "Run screenshots compose to prepare the final local screenshot artifact set."
        ))

        if requiresScreenshotCopyLint {
            items.append(.init(
                id: "screenshots.copy-lint",
                title: "Screenshot copy has been linted without findings",
                satisfied: screenshotCopyLintReport?.valid == true,
                note: screenshotCopyLintReport.map { report in
                    report.valid
                        ? "\(report.copyItemCount) screenshot copy item(s) linted."
                        : "\(report.findings.count) screenshot copy lint finding(s)."
                } ?? "Run screenshots copy lint before final readiness."
            ))
        }

        items.append(.init(
            id: "asc.lookup-plan",
            title: "ASC lookup dry-run plan is ready",
            satisfied: ascLookupPlanReady,
            note: ascLookupPlan.map { plan in
                plan.findings.isEmpty ? "\(plan.steps.count) ASC lookup step(s) planned." : "\(plan.findings.count) ASC lookup planning finding(s)."
            } ?? "Run asc auth init/check, then asc lookup plan."
        ))

        items.append(.init(
            id: "build.processable",
            title: "Processable build candidate is recorded",
            satisfied: matchingProcessedBuild,
            note: selectedBuild.map { "Selected ASC build \($0.version) (\($0.buildNumber))." }
                ?? "Import an observed processed build candidate for the release version/build."
        ))

        items.append(.init(
            id: "app-privacy.published",
            title: "App Privacy answers are published",
            satisfied: appPrivacyStatus?.readyForSubmission == true,
            note: appPrivacyStatus.map { status in
                if status.readyForSubmission {
                    return "App Privacy status: \(status.state.rawValue) via \(status.source)."
                }
                return (status.findings + [
                    "Run asc privacy status to inspect the recorded handoff state.",
                    "Use App Store Connect UI to publish App Privacy answers, then run asc privacy confirm-manual --data-not-collected."
                ]).joined(separator: " ")
            } ?? "Run asc privacy status to inspect the recorded handoff state. Run asc privacy set-not-collected, or complete App Privacy in App Store Connect UI and run asc privacy confirm-manual --data-not-collected."
        ))

        if let iapValidationReport {
            items.append(.init(
                id: "iap.validation",
                title: "Local IAP templates validate",
                satisfied: iapValidationReport.valid,
                note: iapValidationReport.valid ? nil : iapValidationReport.findings.joined(separator: " ")
            ))
        }

        if let reviewInfo {
            items.append(.init(
                id: "review.contact",
                title: "Reviewer contact information is complete",
                satisfied: reviewInfo.contact.isComplete,
                note: reviewInfo.contact.isComplete ? nil : "Provide reviewer first name, last name, email, and phone."
            ))
            items.append(.init(
                id: "review.access",
                title: "Reviewer access instructions are complete",
                satisfied: reviewInfo.access.isComplete,
                note: reviewInfo.access.isComplete ? nil : "If login is required, provide a secret reference and review instructions."
            ))
        } else {
            items.append(.init(
                id: "review.info",
                title: "Reviewer information file exists",
                satisfied: false,
                note: "Run submit review-info init and complete reviewer-info.json."
            ))
        }

        return SubmissionReadinessReport(items: items)
    }
}
