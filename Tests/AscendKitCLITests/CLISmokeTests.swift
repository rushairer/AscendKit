import Testing
@testable import AscendKitCore

@Suite("CLI smoke")
struct CLISmokeTests {
    @Test("reports current semantic version")
    func reportsCurrentSemanticVersion() {
        #expect(AscendKitVersion.current == "0.15.1")
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

    @Test("version report exposes install and verification commands")
    func versionReportExposesInstallAndVerificationCommands() throws {
        let report = AscendKitVersionReport(version: "9.8.7", platform: "macOS", architecture: "arm64")
        let output = try AscendKitJSON.encodeString(report)

        #expect(output.contains("\"version\" : \"9.8.7\""))
        #expect(output.contains("https://github.com/rushairer/AscendKit/releases/tag/v9.8.7"))
        #expect(output.contains("scripts/install-ascendkit.sh --version 9.8.7"))
        #expect(output.contains("scripts/verify-release-assets.sh --version 9.8.7"))
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
        let installScript = try String(contentsOfFile: "scripts/install-ascendkit.sh", encoding: .utf8)
        let verifyScript = try String(contentsOfFile: "scripts/verify-release-assets.sh", encoding: .utf8)
        let formulaScript = try String(contentsOfFile: "scripts/update-homebrew-formula.sh", encoding: .utf8)
        let formula = try String(contentsOfFile: "Formula/ascendkit.rb", encoding: .utf8)
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let releaseWorkflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)

        #expect(script.contains("swift build -c release --product ascendkit"))
        #expect(script.contains("shasum -a 256"))
        #expect(script.contains("bin/ascendkit"))
        #expect(script.contains("install-ascendkit.sh"))
        #expect(installScript.contains("ASCENDKIT_VERSION"))
        #expect(installScript.contains("EXPECTED_SHA"))
        #expect(installScript.contains("ACTUAL_SHA"))
        #expect(installScript.contains("--retry 3"))
        #expect(installScript.contains("--retry-all-errors"))
        #expect(installScript.contains("gh release download"))
        #expect(installScript.contains("releases/latest"))
        #expect(verifyScript.contains("gh release view"))
        #expect(verifyScript.contains("install-ascendkit.sh --version"))
        #expect(verifyScript.contains("ascendkit.rb"))
        #expect(formulaScript.contains("gh release view"))
        #expect(formulaScript.contains("FORMULA_PATH="))
        #expect(formulaScript.contains("ascendkit.rb"))
        #expect(formula.contains("class Ascendkit < Formula"))
        #expect(formula.contains("bin.install \"bin/ascendkit\""))
        #expect(readme.contains("scripts/package-release.sh"))
        #expect(readme.contains("scripts/install-ascendkit.sh"))
        #expect(readme.contains("scripts/verify-release-assets.sh"))
        #expect(readme.contains("scripts/update-homebrew-formula.sh"))
        #expect(readme.contains("ascendkit version --json"))
        #expect(readme.contains("GitHub release archives"))
        #expect(readme.contains("install -m 0755 bin/ascendkit"))
        #expect(ciWorkflow.contains("swift test"))
        #expect(ciWorkflow.contains("actions/checkout@v5"))
        #expect(ciWorkflow.contains("bash -n"))
        #expect(ciWorkflow.contains("scripts/package-release.sh"))
        #expect(ciWorkflow.contains("cd dist && shasum -a 256 -c *.tar.gz.sha256"))
        #expect(releaseWorkflow.contains("actions/checkout@v5"))
        #expect(releaseWorkflow.contains("gh release create"))
        #expect(releaseWorkflow.contains("gh release upload"))
        #expect(releaseWorkflow.contains("scripts/update-homebrew-formula.sh"))
        #expect(releaseWorkflow.contains("scripts/install-ascendkit.sh"))
        #expect(releaseWorkflow.contains("scripts/verify-release-assets.sh"))
        #expect(releaseWorkflow.contains("cd dist && shasum -a 256 -c *.tar.gz.sha256"))
    }
}
