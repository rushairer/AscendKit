import Foundation
import Testing
@testable import AscendKitCore

@Suite("Release workspace")
struct WorkspaceTests {
    @Test("creates durable workspace layout and manifest")
    func createsWorkspace() throws {
        let root = try TemporaryDirectory()
        let manifest = ReleaseManifest(
            releaseID: "demo-1.0-b1",
            appSlug: "demo",
            projects: [],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "1")
                )
            ]
        )

        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(baseDirectory: root.url, manifest: manifest)
        let loaded = try store.loadManifest(from: workspace)

        #expect(loaded.releaseID == "demo-1.0-b1")
        #expect(FileManager.default.fileExists(atPath: workspace.paths.auditEvents))
        #expect(FileManager.default.fileExists(atPath: workspace.paths.metadataSource.deletingLastPathComponent))
    }

    @Test("reports persisted workspace step status")
    func reportsWorkspaceStatus() throws {
        let root = try TemporaryDirectory()
        let manifest = ReleaseManifest(
            releaseID: "demo-status",
            appSlug: "demo",
            projects: [],
            targets: []
        )
        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(baseDirectory: root.url, manifest: manifest)
        try store.save(AppMetadata.template, to: URL(fileURLWithPath: workspace.paths.metadataSource))

        let status = WorkspaceStatusReader().read(workspace: workspace)

        #expect(status.ascendKitVersion == AscendKitVersion.current)
        #expect(status.steps.first { $0.id == "manifest" }?.state == .present)
        #expect(status.steps.first { $0.id == "metadata-source" }?.state == .present)
        #expect(status.steps.first { $0.id == "doctor" }?.state == .missing)
    }

    @Test("summarizes release next actions")
    func summarizesReleaseNextActions() throws {
        let root = try TemporaryDirectory()
        let manifest = ReleaseManifest(
            releaseID: "demo-summary",
            appSlug: "demo",
            projects: [],
            targets: []
        )
        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(baseDirectory: root.url, manifest: manifest)
        try store.save(
            ScreenshotPlan(
                inputPath: .uiTestCapture,
                platforms: [.iOS],
                locales: ["en-US"],
                items: [
                    ScreenshotPlanItem(id: "home", screenName: "Home", order: 1, purpose: "Show home"),
                    ScreenshotPlanItem(id: "settings", screenName: "Settings", order: 2, purpose: "Show settings")
                ]
            ),
            to: URL(fileURLWithPath: workspace.paths.screenshotPlan)
        )
        try store.save(
            SubmissionReadinessReport(items: [
                SubmissionChecklistItem(id: "app-privacy.published", title: "App Privacy answers are published", satisfied: false, note: "Run asc privacy status.")
            ]),
            to: URL(fileURLWithPath: workspace.paths.readiness)
        )
        try store.save(
            ReviewSubmissionPlan(
                releaseID: "demo-summary",
                appID: "app-1",
                selectedBuildID: "build-1",
                selectedBuildVersion: "1.0",
                selectedBuildNumber: "1",
                reviewerName: "Ada Lovelace",
                reviewerPhone: "+15555555555",
                metadataApplied: true,
                screenshotArtifactCount: 1,
                appPrivacyState: "unknown",
                appPrivacySource: "workspace",
                appPrivacyReadyForSubmission: false,
                appPrivacyNextActions: ["Run asc privacy status."],
                readinessReady: false,
                readyForManualReviewSubmission: false,
                findings: ["Submission readiness is not complete."]
            ),
            to: URL(fileURLWithPath: workspace.paths.reviewSubmissionPlan)
        )
        try store.save(
            ScreenshotImportManifest(
                sourceDirectory: "/tmp/screenshots",
                artifacts: [
                    ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/screenshots/01.png", fileName: "01.png")
                ]
            ),
            to: URL(fileURLWithPath: workspace.paths.screenshotImportManifest)
        )
        try store.save(
            ScreenshotCompositionManifest(
                mode: .framedPoster,
                artifacts: [
                    ScreenshotCompositionArtifact(
                        locale: "en-US",
                        platform: .iOS,
                        inputPath: "/tmp/screenshots/01.png",
                        outputPath: "/tmp/composed/01.png",
                        mode: .framedPoster
                    )
                ]
            ),
            to: URL(fileURLWithPath: workspace.paths.screenshotCompositionManifest)
        )

        let summary = ReleaseWorkspaceSummaryReader().read(workspace: workspace)

        #expect(summary.submissionReadinessReady == false)
        #expect(summary.readyForManualReviewSubmission == false)
        #expect(summary.appPrivacyReadyForSubmission == false)
        #expect(summary.appPrivacyState == "unknown")
        #expect(summary.screenshotWorkflowReadyForUploadPlan == false)
        #expect(summary.nextActions.contains { $0.id == "readiness.app-privacy.published" })
        #expect(summary.nextActions.contains { $0.detail == "Submission readiness is not complete." })
        #expect(summary.nextActions.contains { $0.detail.contains("asc privacy set-not-collected") })
        #expect(summary.nextActions.contains { $0.id.hasPrefix("screenshots.coverage.finding.") })
        #expect(summary.nextActions.contains { $0.id == "workspace.hygiene.public-commit" })
    }

    @Test("scans workspace hygiene without exposing contents")
    func scansWorkspaceHygiene() throws {
        let root = try TemporaryDirectory()
        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(
            baseDirectory: root.url,
            manifest: ReleaseManifest(releaseID: "hygiene-demo", appSlug: "demo", projects: [], targets: [])
        )
        let keyURL = URL(fileURLWithPath: workspace.paths.root)
            .appendingPathComponent("asc/AuthKey_TEST.p8")
        try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----".write(to: keyURL, atomically: true, encoding: .utf8)
        let screenshotURL = URL(fileURLWithPath: workspace.paths.root)
            .appendingPathComponent("screenshots/output/home.png")
        try FileManager.default.createDirectory(at: screenshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: screenshotURL)

        let report = WorkspaceHygieneScanner().scan(workspace: workspace)

        #expect(report.ascendKitVersion == AscendKitVersion.current)
        #expect(report.safeForPublicCommit == false)
        #expect(report.findings.contains { $0.id == "workspace.local-artifacts" })
        #expect(report.findings.contains { $0.id.hasPrefix("workspace.secret-key-file.") && $0.path == "asc/AuthKey_TEST.p8" })
        #expect(report.findings.contains { $0.id.hasPrefix("workspace.sensitive-content.") && $0.path == "asc/AuthKey_TEST.p8" })
        #expect(report.findings.contains { $0.id.hasPrefix("workspace.screenshot-artifact.") && $0.path == "screenshots/output/home.png" })
        #expect(report.findings.allSatisfy { !$0.reason.contains("fixture") })
    }

    @Test("checks and fixes project gitignore for workspace artifacts")
    func checksAndFixesProjectGitignore() throws {
        let root = try TemporaryDirectory()
        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(
            baseDirectory: root.url,
            manifest: ReleaseManifest(releaseID: "gitignore-demo", appSlug: "demo", projects: [], targets: [])
        )
        let gitignoreURL = root.url.appendingPathComponent(".gitignore")
        try "DerivedData/\n".write(to: gitignoreURL, atomically: true, encoding: .utf8)

        let guardrail = WorkspaceGitignoreGuard()
        let missingReport = try guardrail.check(workspace: workspace)

        #expect(missingReport.ascendKitVersion == AscendKitVersion.current)
        #expect(missingReport.hasAscendKitRule == false)
        #expect(missingReport.changed == false)
        #expect(missingReport.projectRoot == root.url.standardizedFileURL.path)
        #expect(missingReport.nextActions.contains { $0.contains("--fix") })

        let fixedReport = try guardrail.check(workspace: workspace, fix: true)
        let fixedContent = try String(contentsOf: gitignoreURL, encoding: .utf8)

        #expect(fixedReport.hasAscendKitRule == true)
        #expect(fixedReport.changed == true)
        #expect(fixedContent.contains(".ascendkit/"))

        let idempotentReport = try guardrail.check(workspace: workspace, fix: true)
        let idempotentContent = try String(contentsOf: gitignoreURL, encoding: .utf8)

        #expect(idempotentReport.hasAscendKitRule == true)
        #expect(idempotentReport.changed == false)
        #expect(idempotentContent.components(separatedBy: ".ascendkit/").count == 2)
    }

    @Test("exports sanitized workspace summary without raw workspace paths")
    func exportsSanitizedWorkspaceSummary() throws {
        let root = try TemporaryDirectory()
        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(
            baseDirectory: root.url,
            manifest: ReleaseManifest(releaseID: "export-demo", appSlug: "demo", projects: [], targets: [])
        )
        let exportURL = root.url.appendingPathComponent("handoff/summary.json")

        let report = try SanitizedWorkspaceSummaryExporter().export(workspace: workspace, outputURL: exportURL)
        let exportedData = try Data(contentsOf: exportURL)
        let exportedText = String(decoding: exportedData, as: UTF8.self)
        let decoded = try AscendKitJSON.decoder.decode(SanitizedWorkspaceSummaryExport.self, from: exportedData)

        #expect(report.releaseID == "export-demo")
        #expect(report.ascendKitVersion == AscendKitVersion.current)
        #expect(decoded.ascendKitVersion == AscendKitVersion.current)
        #expect(decoded.exportPath == "summary.json")
        #expect(decoded.steps.contains { $0.id == "manifest" && $0.relativePath == "manifest.json" })
        #expect(decoded.hygieneFindings.contains { $0.id == "workspace.local-artifacts" })
        #expect(decoded.handoffCommands.contains {
            $0.id == "agent-prompt" &&
                $0.command == "ascendkit agent prompt --workspace PATH --asc-profile ASC_PROFILE --output FILE"
        })
        #expect(decoded.handoffCommands.contains {
            $0.id == "next-steps" &&
                $0.command == "ascendkit workspace next-steps --workspace PATH --json"
        })
        #expect(decoded.handoffCommands.contains {
            $0.id == "validate-handoff" &&
                $0.command.contains("--export FILE")
        })
        #expect(decoded.safetyBoundaries.contains { $0.contains("Do not upload binaries") })
        #expect(decoded.safetyBoundaries.contains { $0.contains("submit handoff") })
        #expect(decoded.notes.contains { $0.contains("does not include screenshots") })
        #expect(!exportedText.contains(workspace.paths.root))
        #expect(!exportedText.contains(root.url.standardizedFileURL.path))
    }

    @Test("validates agent handoff separately from release readiness")
    func validatesAgentHandoff() throws {
        let root = try TemporaryDirectory()
        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(
            baseDirectory: root.url,
            manifest: ReleaseManifest(releaseID: "handoff-demo", appSlug: "demo", projects: [], targets: [])
        )

        let blocked = try HandoffValidator().validate(workspace: workspace)

        #expect(blocked.readyForAgentHandoff == false)
        #expect(blocked.releaseBlockerCount > 0)
        #expect(blocked.items.contains { $0.id == "workspace.gitignore.missing" && $0.severity == .blocker })
        #expect(blocked.items.contains { $0.id == "release.blockers.present" && $0.severity == .warning })
        #expect(blocked.handoffInstructions.contains { $0.contains("handoff is blocked") })
        #expect(blocked.handoffInstructions.contains { $0.contains("workspace export-summary") })
        #expect(blocked.handoffInstructions.contains { $0.contains("agent prompt --workspace") })

        _ = try WorkspaceGitignoreGuard().check(workspace: workspace, fix: true)
        let exportURL = root.url.appendingPathComponent("handoff/export.json")
        let ready = try HandoffValidator().validate(workspace: workspace, exportURL: exportURL)

        #expect(ready.readyForAgentHandoff == true)
        #expect(ready.ascendKitVersion == AscendKitVersion.current)
        #expect(ready.releaseBlockerCount > 0)
        #expect(ready.sanitizedExportPath == "export.json")
        #expect(ready.items.contains { $0.id == "workspace.export-summary.generated" && $0.severity == .pass })
        #expect(ready.items.contains { $0.id == "release.blockers.present" && $0.severity == .warning })
        #expect(ready.handoffInstructions.contains { $0.contains("handoff is safe") })
        #expect(ready.handoffInstructions.contains { $0.contains("export.json") })
        #expect(ready.handoffInstructions.contains { $0.contains("workspace next-steps") })
        #expect(FileManager.default.fileExists(atPath: exportURL.path))
    }

    @Test("plans structured next steps from workspace summary")
    func plansStructuredNextSteps() throws {
        let root = try TemporaryDirectory()
        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(
            baseDirectory: root.url,
            manifest: ReleaseManifest(releaseID: "next-steps-demo", appSlug: "demo", projects: [], targets: [])
        )

        let plan = WorkspaceNextStepsPlanner().plan(workspace: workspace)

        #expect(plan.releaseID == "next-steps-demo")
        #expect(plan.ascendKitVersion == AscendKitVersion.current)
        #expect(plan.blockerCount > 0)
        #expect(plan.steps.first?.severity == .blocker)
        #expect(plan.steps.contains {
            $0.sourceActionID == "readiness.missing" &&
                $0.command == "submit readiness --workspace PATH --json"
        })
        #expect(plan.steps.contains {
            $0.sourceActionID == "readiness.missing" &&
                $0.executableCommand == "ascendkit submit readiness --workspace '\(workspace.paths.root)' --json"
        })
        #expect(plan.steps.contains {
            $0.sourceActionID == "review-plan.missing" &&
                $0.command == "submit review-plan --workspace PATH --json"
        })
        #expect(plan.steps.contains {
            $0.sourceActionID == "workspace.hygiene.public-commit" &&
                $0.command == "workspace hygiene --workspace PATH --json"
        })
        #expect(plan.steps.contains {
            $0.sourceActionID == "workspace.hygiene.public-commit" &&
                $0.executableCommand == "ascendkit workspace hygiene --workspace '\(workspace.paths.root)' --json"
        })
        #expect(plan.steps.allSatisfy { step in
            step.sourceActionID.hasPrefix("review-plan.") == false ||
                step.detail.contains("App Privacy") == false ||
                step.command == "asc privacy status --workspace PATH --json"
        })
    }

    @Test("workspace next steps include screenshot upload recovery commands")
    func workspaceNextStepsIncludeScreenshotUploadRecoveryCommands() throws {
        let root = try TemporaryDirectory()
        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(
            baseDirectory: root.url,
            manifest: ReleaseManifest(releaseID: "upload-recovery-demo", appSlug: "demo", projects: [], targets: [])
        )
        try store.save(
            ScreenshotUploadPlan(
                sourceKind: .composed,
                items: [
                    ScreenshotUploadPlanItem(
                        locale: "en-US",
                        platform: .iOS,
                        displayType: "APP_IPHONE_67",
                        appStoreVersionLocalizationID: "version-loc-1",
                        sourcePath: "/tmp/home.png",
                        fileName: "home.png",
                        order: 1
                    )
                ]
            ),
            to: URL(fileURLWithPath: workspace.paths.screenshotUploadPlan)
        )
        try store.save(
            ScreenshotUploadExecutionResult(
                executed: true,
                uploadedCount: 1,
                items: [
                    ScreenshotUploadExecutionItem(
                        planItemID: "en-US:iOS:APP_IPHONE_67:1:home.png",
                        appScreenshotSetID: "set-1",
                        appScreenshotID: "screenshot-1",
                        fileName: "home.png",
                        checksum: "checksum-1",
                        assetDeliveryState: "FAILED"
                    )
                ]
            ),
            to: URL(fileURLWithPath: workspace.paths.screenshotUploadResult)
        )

        let summary = ReleaseWorkspaceSummaryReader().read(workspace: workspace)
        let plan = WorkspaceNextStepsPlanner().plan(workspace: workspace)

        #expect(summary.nextActions.contains {
            $0.id == "screenshots.upload.recovery-command.2" &&
                $0.detail == "screenshots upload-plan --workspace PATH --replace-existing --json"
        })
        #expect(plan.steps.contains {
            $0.sourceActionID == "screenshots.upload.recovery-command.2" &&
                $0.command == "screenshots upload-plan --workspace PATH --replace-existing --json"
        })
        #expect(plan.steps.contains {
            $0.sourceActionID == "screenshots.upload.recovery-command.3" &&
                $0.command == "screenshots upload --workspace PATH --replace-existing --confirm-remote-mutation --json"
        })
        #expect(plan.steps.contains {
            $0.sourceActionID == "screenshots.upload.recovery-command.3" &&
                $0.executableCommand == "ascendkit screenshots upload --workspace '\(workspace.paths.root)' --replace-existing --confirm-remote-mutation --json"
        })
    }

    @Test("workspace next steps include screenshot upload ready commands")
    func workspaceNextStepsIncludeScreenshotUploadReadyCommands() throws {
        let root = try TemporaryDirectory()
        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(
            baseDirectory: root.url,
            manifest: ReleaseManifest(releaseID: "upload-ready-demo", appSlug: "demo", projects: [], targets: [])
        )
        try store.save(
            ScreenshotUploadPlan(
                sourceKind: .composed,
                items: [
                    ScreenshotUploadPlanItem(
                        locale: "en-US",
                        platform: .iOS,
                        displayType: "APP_IPHONE_67",
                        appStoreVersionLocalizationID: "version-loc-1",
                        sourcePath: "/tmp/home.png",
                        fileName: "home.png",
                        order: 1
                    )
                ]
            ),
            to: URL(fileURLWithPath: workspace.paths.screenshotUploadPlan)
        )
        try store.save(
            ScreenshotUploadExecutionResult(
                executed: true,
                uploadedCount: 1,
                items: [
                    ScreenshotUploadExecutionItem(
                        planItemID: "en-US:iOS:APP_IPHONE_67:1:home.png",
                        appScreenshotSetID: "set-1",
                        appScreenshotID: "screenshot-1",
                        fileName: "home.png",
                        checksum: "checksum-1",
                        assetDeliveryState: "COMPLETE"
                    )
                ]
            ),
            to: URL(fileURLWithPath: workspace.paths.screenshotUploadResult)
        )

        let plan = WorkspaceNextStepsPlanner().plan(workspace: workspace)

        #expect(plan.steps.contains {
            $0.sourceActionID == "screenshots.upload.ready-command.1" &&
                $0.command == "workspace summary --workspace PATH --json" &&
                $0.severity == .info
        })
        #expect(plan.steps.contains {
            $0.sourceActionID == "screenshots.upload.ready-command.2" &&
                $0.command == "submit readiness --workspace PATH --json" &&
                $0.severity == .info
        })
    }

    @Test("lists release workspaces under a project root")
    func listsReleaseWorkspaces() throws {
        let root = try TemporaryDirectory()
        let store = ReleaseWorkspaceStore()
        _ = try store.createWorkspace(
            baseDirectory: root.url,
            manifest: ReleaseManifest(releaseID: "demo-1", appSlug: "demo", projects: [], targets: [])
        )
        _ = try store.createWorkspace(
            baseDirectory: root.url,
            manifest: ReleaseManifest(releaseID: "demo-2", appSlug: "demo", projects: [], targets: [])
        )

        let list = WorkspaceLister().list(baseDirectory: root.url)

        #expect(list.ascendKitVersion == AscendKitVersion.current)
        #expect(Set(list.releases.map(\.releaseID)) == ["demo-1", "demo-2"])
        #expect(list.releases.allSatisfy { $0.totalStepCount == 34 })
        #expect(list.releases.allSatisfy { $0.completeStepCount >= 2 })
    }

    @Test("reads redacted audit records")
    func readsAuditRecords() throws {
        let root = try TemporaryDirectory()
        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(
            baseDirectory: root.url,
            manifest: ReleaseManifest(releaseID: "audit-demo", appSlug: "demo", projects: [], targets: [])
        )
        try store.appendAudit(
            AuditRecord(action: .buildCandidatesImported, summary: "Imported build", details: ["token": "super-secret-token"]),
            to: workspace
        )

        let records = try AuditLogReader().read(workspace: workspace)

        #expect(records.count == 2)
        #expect(records.last?.details["token"] == "su...en")
    }
}

extension String {
    fileprivate var deletingLastPathComponent: String {
        (self as NSString).deletingLastPathComponent
    }
}
