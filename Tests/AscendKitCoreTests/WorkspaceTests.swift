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
