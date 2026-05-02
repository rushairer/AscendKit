import Testing
@testable import AscendKitCore

@Suite("CLI smoke")
struct CLISmokeTests {
    @Test("reports current semantic version")
    func reportsCurrentSemanticVersion() {
        #expect(AscendKitVersion.current == "0.19.0")
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
        #expect(output.contains("brew tap rushairer/ascendkit"))
        #expect(output.contains("brew install ascendkit"))
        #expect(output.contains("scripts/verify-release-assets.sh --version 9.8.7"))
    }

    @Test("README release version references stay aligned")
    func readmeReleaseVersionReferencesStayAligned() throws {
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let formula = try String(contentsOfFile: "Formula/ascendkit.rb", encoding: .utf8)
        let version = AscendKitVersion.current

        #expect(readme.contains("Current documented release: `v\(version)`"))
        #expect(readme.contains("scripts/install-ascendkit.sh --version \(version)"))
        #expect(readme.contains("scripts/verify-release-assets.sh --version \(version)"))
        #expect(formula.contains("releases/download/v\(version)/ascendkit-\(version)-macos-arm64.tar.gz"))
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
        let commandSurface = try String(contentsOfFile: "docs/v1-command-surface.md", encoding: .utf8)
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
        #expect(!playbook.contains("swift run ascendkit"))
        #expect(playbook.contains("brew install ascendkit"))
        #expect(commandSurface.contains("`swift run ascendkit ...` is a contributor-only"))
        #expect(commandSurface.contains("metadata import-fastlane"))
        #expect(commandSurface.contains("submit execute --confirm-remote-submission"))
    }

    @Test("release packaging script and install docs stay discoverable")
    func releasePackagingScriptAndDocsStayDiscoverable() throws {
        let script = try String(contentsOfFile: "scripts/package-release.sh", encoding: .utf8)
        let preflightScript = try String(contentsOfFile: "scripts/preflight-public-release.sh", encoding: .utf8)
        let installScript = try String(contentsOfFile: "scripts/install-ascendkit.sh", encoding: .utf8)
        let verifyScript = try String(contentsOfFile: "scripts/verify-release-assets.sh", encoding: .utf8)
        let formulaScript = try String(contentsOfFile: "scripts/update-homebrew-formula.sh", encoding: .utf8)
        let formulaVerifyScript = try String(contentsOfFile: "scripts/verify-homebrew-formula.sh", encoding: .utf8)
        let formula = try String(contentsOfFile: "Formula/ascendkit.rb", encoding: .utf8)
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let releaseWorkflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)

        #expect(script.contains("swift build -c release --product ascendkit"))
        #expect(script.contains("shasum -a 256"))
        #expect(script.contains("bin/ascendkit"))
        #expect(script.contains("install-ascendkit.sh"))
        #expect(preflightScript.contains("swift test"))
        #expect(preflightScript.contains("swift run ascendkit version --json"))
        #expect(preflightScript.contains("scripts/package-release.sh"))
        #expect(preflightScript.contains("scripts/update-homebrew-formula.sh"))
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
        #expect(formulaVerifyScript.contains("Formula/ascendkit.rb"))
        #expect(formulaVerifyScript.contains("sha256"))
        #expect(formulaVerifyScript.contains("gh release view"))
        #expect(formula.contains("class Ascendkit < Formula"))
        #expect(formula.contains("bin.install \"bin/ascendkit\""))
        #expect(readme.contains("scripts/package-release.sh"))
        #expect(readme.contains("scripts/preflight-public-release.sh"))
        #expect(readme.contains("scripts/install-ascendkit.sh"))
        #expect(readme.contains("scripts/verify-release-assets.sh"))
        #expect(readme.contains("scripts/update-homebrew-formula.sh"))
        #expect(readme.contains("scripts/verify-homebrew-formula.sh"))
        #expect(readme.contains("brew tap rushairer/ascendkit"))
        #expect(readme.contains("brew install ascendkit"))
        #expect(readme.contains("ascendkit version --json"))
        #expect(readme.contains("swift run ascendkit --help"))
        #expect(readme.contains("GitHub release archives"))
        #expect(ciWorkflow.contains("swift test"))
        #expect(ciWorkflow.contains("actions/checkout@v5"))
        #expect(ciWorkflow.contains("bash -n"))
        #expect(ciWorkflow.contains("scripts/package-release.sh"))
        #expect(ciWorkflow.contains("cd dist && shasum -a 256 -c *.tar.gz.sha256"))
        #expect(releaseWorkflow.contains("actions/checkout@v5"))
        #expect(releaseWorkflow.contains("gh release create"))
        #expect(releaseWorkflow.contains("gh release upload"))
        #expect(releaseWorkflow.contains("scripts/update-homebrew-formula.sh"))
        #expect(releaseWorkflow.contains("scripts/verify-homebrew-formula.sh"))
        #expect(releaseWorkflow.contains("scripts/install-ascendkit.sh"))
        #expect(releaseWorkflow.contains("scripts/verify-release-assets.sh"))
        #expect(releaseWorkflow.contains("cd dist && shasum -a 256 -c *.tar.gz.sha256"))
    }
}
