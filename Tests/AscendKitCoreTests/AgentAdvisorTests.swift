import Foundation
import Testing
@testable import AscendKitCore

@Suite("Agent advisor")
struct AgentAdvisorTests {
    @Test("advise on missing manifest returns intake phase")
    func adviseMissingManifestReturnsIntake() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workspace = ReleaseWorkspace(releaseID: "test-intake", root: tempDir)
        let report = AgentAdvisor().advise(workspace: workspace)

        #expect(report.phase == AgentReleasePhase.intake)
        #expect(!report.readyForNextStep)
        #expect(report.blockers.contains("Release manifest does not exist."))
        #expect(report.recommendedCommand.contains("intake init"))
        #expect(report.ignorableWarnings.contains { $0.contains("409 on content-rights") })
    }

    @Test("advise on submitted workspace returns waitingForReview phase")
    func adviseSubmittedWorkspaceReturnsWaitingForReview() throws {
        let root = try TemporaryDirectory()
        let manifest = ReleaseManifest(
            releaseID: "test-submitted",
            appSlug: "demo",
            projects: [],
            targets: []
        )
        let workspace = try ReleaseWorkspaceStore().createWorkspace(baseDirectory: root.url, manifest: manifest)
        let reviewDir = URL(fileURLWithPath: workspace.paths.root).appendingPathComponent("review")
        try FileManager.default.createDirectory(at: reviewDir, withIntermediateDirectories: true)

        let result = ReviewSubmissionExecutionResult(
            executed: true,
            appStoreVersionID: "ver-123",
            buildID: "bld-456",
            reviewSubmissionID: "sub-789",
            submitted: true
        )
        let data = try AscendKitJSON.encoder.encode(result)
        try data.write(to: URL(fileURLWithPath: workspace.paths.reviewSubmissionResult))

        let report = AgentAdvisor().advise(workspace: workspace)

        #expect(report.phase == AgentReleasePhase.waitingForReview)
        #expect(report.readyForNextStep)
        #expect(report.blockers.isEmpty)
        #expect(report.agentPrompt.contains("submitted for review"))
    }
}
