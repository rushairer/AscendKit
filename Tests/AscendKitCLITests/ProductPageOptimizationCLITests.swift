import Foundation
import Testing
@testable import AscendKitCore

@Suite("PPO CLI")
struct ProductPageOptimizationCLITests {
    @Test("plans mutations without ASC credentials", arguments: [
        ["create", "--app-id", "app-1", "--name", "Benefits first", "--traffic-proportion", "50"],
        ["start", "--experiment-id", "exp-1"],
        ["screenshot-order-by-prefix", "--set-id", "set-1", "--localization-id", "loc-1", "--prefixes", "02,01"],
        ["promote", "--version-id", "version-1", "--treatment-id", "treatment-1"],
        ["review-submit", "--review-submission-id", "review-1", "--confirm-remote-mutation"]
    ])
    func plansWithoutCredentials(arguments: [String]) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ppo-cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try ReleaseWorkspaceStore().createWorkspace(baseDirectory: root, manifest: ReleaseManifest(releaseID: "ppo", appSlug: "demo", projects: [], targets: []))
        let output = try run(arguments: ["asc", "ppo"] + arguments + ["--workspace", workspace.paths.root, "--json"])
        #expect(output.status == 0)
        let result = try AscendKitJSON.decoder.decode(PPOJSONValue.self, from: Data(output.stdout.utf8))
        #expect(result["executed"] == .bool(false))
        #expect(result["plan"]?["action"] == .string(arguments[0]))
        #expect(FileManager.default.fileExists(atPath: workspace.paths.root + "/asc/ppo/plan.json"))
        #expect(FileManager.default.fileExists(atPath: workspace.paths.root + "/asc/ppo/result.json"))
        #expect(!FileManager.default.fileExists(atPath: workspace.paths.ascAuthConfig))
        let audit = try String(contentsOfFile: workspace.paths.auditEvents, encoding: .utf8)
        #expect(audit.contains("ppoPlanned"))
        #expect(!audit.contains("ppoExecuted"))
    }

    @Test("rejects misspelled and duplicate options", arguments: [
        ["--experiment-id", "exp-1", "--confirm-remote-mutaton"],
        ["--experiment-id", "exp-1", "--experiment-id", "exp-2"],
        ["--experiment-id", "exp-1", "--extra", "ignored"]
    ])
    func rejectsInvalidOptions(arguments: [String]) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ppo-cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try ReleaseWorkspaceStore().createWorkspace(baseDirectory: root, manifest: ReleaseManifest(releaseID: "ppo", appSlug: "demo", projects: [], targets: []))
        let output = try run(arguments: ["asc", "ppo", "start"] + arguments + ["--workspace", workspace.paths.root, "--json"])
        #expect(output.status == 2)
        #expect(!output.stderr.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: workspace.paths.root + "/asc/ppo/plan.json"))
    }

    private func run(arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ".build/debug/ascendkit").standardizedFileURL
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
