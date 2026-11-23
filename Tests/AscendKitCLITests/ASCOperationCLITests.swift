import Foundation
import Testing
@testable import AscendKitCore

@Suite("Public ASC CLI")
struct ASCOperationCLITests {
    @Test("plans an app-scoped mutation using cached app lookup and no ASC credentials")
    func plansWithoutCredentials() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("asc-cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(
            baseDirectory: root,
            manifest: ReleaseManifest(releaseID: "asc", appSlug: "demo", projects: [], targets: [])
        )
        let lookup = ASCAppsLookupReport(bundleIDs: ["com.example.demo"], apps: [
            ASCObservedApp(id: "app-1", name: "Demo", bundleID: "com.example.demo", sku: "demo", primaryLocale: "en-US")
        ], findings: [])
        try store.save(lookup, to: URL(fileURLWithPath: workspace.paths.ascApps))
        let base = ["asc", "subscriptions", "invitation-mode-set", "--workspace", workspace.paths.root,
                    "--group-purchase-invitation-mode", "DEVELOPER_HOSTED", "--json"]
        let output = try runAscendKitCLI(arguments: base)
        #expect(output.status == 0)
        let result = try AscendKitJSON.decoder.decode(PPOJSONValue.self, from: Data(output.stdout.utf8))
        #expect(result["executed"] == .bool(false))
        #expect(result["plan"]?["path"] == .string("v1/apps/app-1"))
        let directory = workspace.paths.root + "/asc/subscriptions/invitation-mode-set"
        #expect(FileManager.default.fileExists(atPath: directory + "/plan.json"))
        #expect(FileManager.default.fileExists(atPath: directory + "/result.json"))
        let audit = try String(contentsOfFile: workspace.paths.auditEvents, encoding: .utf8)
        #expect(audit.contains("ascOperationPlanned"))

        let invalid = try runAscendKitCLI(arguments: base + ["--confirm-remote-submission"])
        #expect(invalid.status == 2)
        #expect(invalid.stderr.contains("applies to review-submit"))
        let confirmed = try runAscendKitCLI(arguments: base + ["--confirm-remote-mutation"])
        #expect(confirmed.status == 2)
        #expect(confirmed.stderr.contains("ASC auth config is missing"))
    }

    @Test("discovers every new ASC domain without a workspace and exposes the same guide in agent advice")
    func discoversAgentCapabilities() throws {
        let discovery = try runAscendKitCLI(arguments: ["asc", "capabilities", "--json"])
        #expect(discovery.status == 0)
        let guidance = try AscendKitJSON.decoder.decode(ASCAgentGuidance.self, from: Data(discovery.stdout.utf8))
        #expect(guidance.capabilities.map(\.domain).sorted() == ASCOperationPlanner.domains)
        #expect(guidance.chinaMainlandAppCompliance.contains("App Store Connect > App Compliance"))
        for capability in guidance.capabilities {
            let start = capability.startCommand.split(separator: " ").prefix(5).joined(separator: " ")
            #expect(ASCOperationPlanner.usage(for: capability.domain).contains { $0.hasPrefix(start + " ") })
            let action = capability.startCommand.split(separator: " ")[3]
            let plan = try ASCOperationPlanner().plan(domain: capability.domain, action: String(action), options: ["app-id": "app-1"])
            #expect(!plan.mutatesRemote)
            #expect(AscendKitCommandCatalog.usageLines.contains(capability.helpCommand))
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("asc-capabilities-cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try ReleaseWorkspaceStore().createWorkspace(
            baseDirectory: root,
            manifest: ReleaseManifest(releaseID: "asc", appSlug: "demo", projects: [], targets: [])
        )
        let advice = try runAscendKitCLI(arguments: ["agent", "advise", "--workspace", workspace.paths.root, "--json"])
        #expect(advice.status == 0)
        let report = try AscendKitJSON.decoder.decode(AgentAdviseReport.self, from: Data(advice.stdout.utf8))
        #expect(report.phase == .screenshotsCapture)
        #expect(report.ascCapabilities == guidance)
    }

    @Test("each recent domain has unique, discoverable commands")
    func listsHelp() throws {
        for domain in ASCOperationPlanner.domains {
            let actions = ASCOperationPlanner.usage(for: domain)
            let names = actions.map { $0.split(separator: " ").dropFirst(3).first }
            #expect(Set(names).count == names.count)
            #expect(AscendKitCommandCatalog.usageLines.contains("ascendkit asc \(domain) --help"))
        }
        let help = try runAscendKitCLI(arguments: ["asc", "age-rating", "--help"])
        #expect(help.status == 0)
        #expect(help.stdout.contains("--shared-location true|false"))
        #expect(help.stdout.contains("--confirm-remote-mutation"))
    }
}
