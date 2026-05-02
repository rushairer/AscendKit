import Testing
@testable import AscendKitCore

@Suite("CLI smoke")
struct CLISmokeTests {
    @Test("reports current semantic version")
    func reportsCurrentSemanticVersion() {
        #expect(AscendKitVersion.current == "0.12.1")
    }

    @Test("core JSON encoder produces sorted manifest output")
    func jsonEncoderWorksForCLIValues() throws {
        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [],
            targets: []
        )

        let output = try AscendKitJSON.encodeString(manifest)

        #expect(output.contains("\"releaseID\" : \"demo\""))
        #expect(output.contains("\"schemaVersion\" : 1"))
    }

    @Test("command catalog renders complete help without duplicate usage lines")
    func commandCatalogRendersCompleteHelp() {
        let usageLines = AscendKitCommandCatalog.usageLines
        let help = AscendKitCommandCatalog.helpText

        #expect(Set(usageLines).count == usageLines.count)
        #expect(help.hasPrefix("AscendKit\n\nUsage:"))
        for line in usageLines {
            #expect(help.contains("  \(line)"))
        }
    }

    @Test("agent-facing docs mention required handoff commands")
    func agentDocsMentionRequiredHandoffCommands() throws {
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let playbook = try String(contentsOfFile: "docs/agent-release-playbook.md", encoding: .utf8)
        let requiredFragments = [
            "workspace summary",
            "workspace hygiene",
            "workspace gitignore",
            "workspace export-summary",
            "workspace validate-handoff",
            "workspace next-steps"
        ]

        for fragment in requiredFragments {
            #expect(readme.contains(fragment))
            #expect(playbook.contains(fragment))
        }
    }

    @Test("release packaging script and install docs stay discoverable")
    func releasePackagingScriptAndDocsStayDiscoverable() throws {
        let script = try String(contentsOfFile: "scripts/package-release.sh", encoding: .utf8)
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let releaseWorkflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)

        #expect(script.contains("swift build -c release --product ascendkit"))
        #expect(script.contains("shasum -a 256"))
        #expect(script.contains("bin/ascendkit"))
        #expect(readme.contains("scripts/package-release.sh"))
        #expect(readme.contains("GitHub release archives"))
        #expect(readme.contains("install -m 0755 bin/ascendkit"))
        #expect(ciWorkflow.contains("swift test"))
        #expect(ciWorkflow.contains("scripts/package-release.sh"))
        #expect(releaseWorkflow.contains("softprops/action-gh-release"))
        #expect(releaseWorkflow.contains("dist/*.tar.gz.sha256"))
    }
}
