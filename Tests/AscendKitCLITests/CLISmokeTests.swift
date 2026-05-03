import Testing
@testable import AscendKitCore

@Suite("CLI smoke")
struct CLISmokeTests {
    @Test("reports current semantic version")
    func reportsCurrentSemanticVersion() {
        #expect(AscendKitVersion.current == "1.4.0")
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
        #expect(!output.contains("brew tap rushairer/ascendkit https://github.com/rushairer/AscendKit"))
        #expect(output.contains("ascendkit --version && ascendkit version --json"))
    }

    @Test("README release version references stay aligned")
    func readmeReleaseVersionReferencesStayAligned() throws {
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)
        let formula = try String(contentsOfFile: "Formula/ascendkit.rb", encoding: .utf8)
        let version = AscendKitVersion.current

        #expect(readme.contains("Current documented release: `v\(version)`"))
        #expect(readme.contains("scripts/install-ascendkit.sh --version \(version)"))
        #expect(readme.contains("scripts/verify-release-assets.sh --version \(version)"))
        #expect(changelog.contains("## \(version) - "))
        #expect(formula.contains("releases/download/v\(version)/ascendkit-\(version)-macos-universal.tar.gz"))

        let checksumPattern = #"sha256 "[0-9a-f]{64}""#
        #expect(formula.range(of: checksumPattern, options: .regularExpression) != nil)
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

    @Test("v1 command surface groups stay represented in help")
    func v1CommandSurfaceGroupsStayRepresentedInHelp() throws {
        let commandSurface = try String(contentsOfFile: "docs/v1-command-surface.md", encoding: .utf8)
        let usageLines = AscendKitCommandCatalog.usageLines
        let stableGroups = [
            "version",
            "workspace",
            "intake",
            "doctor",
            "metadata",
            "screenshots",
            "asc auth",
            "asc lookup",
            "asc apps",
            "asc builds",
            "asc metadata",
            "asc pricing",
            "asc privacy",
            "submit",
            "iap"
        ]

        for group in stableGroups {
            #expect(commandSurface.contains("- `\(group)`"))
            #expect(usageLines.contains { $0.hasPrefix("ascendkit \(group) ") || $0 == "ascendkit \(group) [--json]" })
        }
    }

    @Test("agent-facing docs mention required handoff commands")
    func agentDocsMentionRequiredHandoffCommands() throws {
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let playbook = try String(contentsOfFile: "docs/agent-release-playbook.md", encoding: .utf8)
        let commandSurface = try String(contentsOfFile: "docs/v1-command-surface.md", encoding: .utf8)
        let automationBoundaries = try String(contentsOfFile: "docs/automation-boundaries.md", encoding: .utf8)
        let architecture = try String(contentsOfFile: "docs/architecture.md", encoding: .utf8)
        let releaseReadiness = try String(contentsOfFile: "docs/v1-release-readiness.md", encoding: .utf8)
        let growthRoadmap = try String(contentsOfFile: "docs/app-store-growth-copilot-roadmap.md", encoding: .utf8)
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
        #expect(playbook.contains("ascendKitVersion"))
        #expect(readme.contains("ascendKitVersion"))
        #expect(readme.contains("## AI Agent Quick Start"))
        #expect(readme.contains("AscendKit repository: https://github.com/rushairer/AscendKit"))
        #expect(readme.contains("First, learn AscendKit from its README and docs/agent-release-playbook.md."))
        #expect(readme.contains("use the installed ascendkit binary, not swift run"))
        #expect(readme.contains("Keep binary upload out of scope. Xcode Cloud handles binary upload."))
        #expect(readme.contains("Do not execute final remote review submission."))
        #expect(readme.contains("screenshots scaffold-uitests"))
        #expect(readme.contains("scripts/create-agent-handoff-prompt.sh"))
        #expect(readme.contains("docs/v1-release-readiness.md"))
        #expect(readme.contains("docs/app-store-growth-copilot-roadmap.md"))
        #expect(readme.contains("ascendkit screenshots doctor --workspace \"$WORKSPACE\" --json"))
        #expect(readme.contains("ascendkit screenshots scaffold-uitests --workspace \"$WORKSPACE\" --json"))
        #expect(readme.contains("deterministic UI-test-driven screenshots"))
        #expect(growthRoadmap.contains("Screenshot Studio"))
        #expect(growthRoadmap.contains("UI Test"))
        #expect(growthRoadmap.contains("iOS and iPadOS"))
        #expect(growthRoadmap.contains("macOS and visionOS"))
        #expect(growthRoadmap.contains("tvOS and watchOS"))
        #expect(growthRoadmap.contains("Read-Only ASC Analytics Reports"))
        #expect(growthRoadmap.contains("No automatic price changes"))
        #expect(growthRoadmap.contains("Do not start ASC analytics implementation until v1.6 and v1.7 screenshot workflows are stable."))
        #expect(readme.contains("v1 command surface is stable for `1.x`"))
        #expect(!readme.contains("release-candidate hardening"))
        #expect(!readme.contains("Until AscendKit has a dedicated tap repository"))
        #expect(commandSurface.contains("`swift run ascendkit ...` is a contributor-only"))
        #expect(commandSurface.contains("docs/v1-release-readiness.md"))
        #expect(commandSurface.contains("metadata import-fastlane"))
        #expect(commandSurface.contains("submit execute --confirm-remote-submission"))
        #expect(releaseReadiness.contains("Remote review submission execution remains boundary-disabled."))
        #expect(releaseReadiness.contains("Fastlane commands remain migration helpers only"))
        #expect(releaseReadiness.contains("Homebrew reinstall from the synced formula reports the tagged version"))
        #expect(releaseReadiness.contains("scripts/v1-representative-app-smoke.sh --app-root PATH"))
        #expect(releaseReadiness.contains("scripts/sync-homebrew-tap.sh --commit --push"))
        #expect(releaseReadiness.contains("scripts/v1-release-readiness.sh --version VERSION --app-root PATH"))

        let v1Docs = [readme, playbook, commandSurface, automationBoundaries, architecture, releaseReadiness]
        let retiredCommandFragments = [
            "metadata sync",
            "submit review --",
            "doctor release --autofix-safe",
            "--private-key-provider env|file|keychain"
        ]
        for doc in v1Docs {
            for fragment in retiredCommandFragments {
                #expect(!doc.contains(fragment))
            }
        }
    }

    @Test("release packaging script and install docs stay discoverable")
    func releasePackagingScriptAndDocsStayDiscoverable() throws {
        let script = try String(contentsOfFile: "scripts/package-release.sh", encoding: .utf8)
        let preflightScript = try String(contentsOfFile: "scripts/preflight-public-release.sh", encoding: .utf8)
        let installScript = try String(contentsOfFile: "scripts/install-ascendkit.sh", encoding: .utf8)
        let verifyScript = try String(contentsOfFile: "scripts/verify-release-assets.sh", encoding: .utf8)
        let formulaScript = try String(contentsOfFile: "scripts/update-homebrew-formula.sh", encoding: .utf8)
        let formulaVerifyScript = try String(contentsOfFile: "scripts/verify-homebrew-formula.sh", encoding: .utf8)
        let homebrewDiagnoseScript = try String(contentsOfFile: "scripts/diagnose-homebrew-install.sh", encoding: .utf8)
        let handoffPromptScript = try String(contentsOfFile: "scripts/create-agent-handoff-prompt.sh", encoding: .utf8)
        let representativeSmokeScript = try String(contentsOfFile: "scripts/v1-representative-app-smoke.sh", encoding: .utf8)
        let tapSyncScript = try String(contentsOfFile: "scripts/sync-homebrew-tap.sh", encoding: .utf8)
        let v1ReadinessScript = try String(contentsOfFile: "scripts/v1-release-readiness.sh", encoding: .utf8)
        let finalizerScript = try String(contentsOfFile: "scripts/finalize-homebrew-release.sh", encoding: .utf8)
        let formula = try String(contentsOfFile: "Formula/ascendkit.rb", encoding: .utf8)
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let cli = try String(contentsOfFile: "Sources/AscendKitCLI/main.swift", encoding: .utf8)
        let ciWorkflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let releaseWorkflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)

        #expect(script.contains("swift build -c release --product ascendkit"))
        #expect(script.contains("--arch arm64 --arch x86_64"))
        #expect(script.contains("macos-${PACKAGE_ARCH}"))
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
        #expect(installScript.contains("macos-universal"))
        #expect(installScript.contains("macos-${ARCH}"))
        #expect(installScript.contains("--retry 3"))
        #expect(installScript.contains("--retry-all-errors"))
        #expect(installScript.contains("gh release download"))
        #expect(installScript.contains("releases/latest"))
        #expect(verifyScript.contains("gh release view"))
        #expect(verifyScript.contains("macos-universal"))
        #expect(verifyScript.contains("install-ascendkit.sh --version"))
        #expect(verifyScript.contains("ascendkit.rb"))
        #expect(formulaScript.contains("gh release view"))
        #expect(formulaScript.contains("gh release download"))
        #expect(formulaScript.contains("Refusing to fall back to the local archive"))
        #expect(formulaScript.contains("Formula SHA-256 source:"))
        #expect(formulaScript.contains("macos-universal"))
        #expect(formulaScript.contains("FORMULA_PATH="))
        #expect(formulaScript.contains("ascendkit.rb"))
        #expect(formulaVerifyScript.contains("Formula/ascendkit.rb"))
        #expect(formulaVerifyScript.contains("sha256"))
        #expect(formulaVerifyScript.contains("macos-universal"))
        #expect(formulaVerifyScript.contains("gh release view"))
        #expect(homebrewDiagnoseScript.contains("brew --repo"))
        #expect(homebrewDiagnoseScript.contains("ls-remote origin"))
        #expect(homebrewDiagnoseScript.contains("Tap checkout is not aligned"))
        #expect(homebrewDiagnoseScript.contains("git -C ${TAP_REPO} pull --ff-only"))
        #expect(homebrewDiagnoseScript.contains("brew reinstall ${TAP}/${FORMULA_NAME}"))
        #expect(homebrewDiagnoseScript.contains("Formula SHA-256 does not match"))
        #expect(homebrewDiagnoseScript.contains("lipo -archs"))
        #expect(homebrewDiagnoseScript.contains("macos-universal"))
        #expect(handoffPromptScript.contains("Use AscendKit to prepare this Apple app"))
        #expect(handoffPromptScript.contains("Do not upload binaries"))
        #expect(handoffPromptScript.contains("workspace next-steps --workspace"))
        #expect(handoffPromptScript.contains("submit handoff"))
        #expect(representativeSmokeScript.contains("ASCENDKIT_BIN"))
        #expect(representativeSmokeScript.contains("intake inspect"))
        #expect(representativeSmokeScript.contains("submit readiness"))
        #expect(representativeSmokeScript.contains("workspace validate-handoff"))
        #expect(tapSyncScript.contains("ASCENDKIT_HOMEBREW_TAP_DIR"))
        #expect(tapSyncScript.contains("homebrew-ascendkit"))
        #expect(tapSyncScript.contains("Formula/ascendkit.rb"))
        #expect(v1ReadinessScript.contains("scripts/preflight-public-release.sh"))
        #expect(v1ReadinessScript.contains("scripts/verify-release-assets.sh --version"))
        #expect(v1ReadinessScript.contains("brew reinstall rushairer/ascendkit/ascendkit"))
        #expect(v1ReadinessScript.contains("scripts/diagnose-homebrew-install.sh --version"))
        #expect(v1ReadinessScript.contains("scripts/v1-representative-app-smoke.sh"))
        #expect(finalizerScript.contains("scripts/update-homebrew-formula.sh"))
        #expect(finalizerScript.contains("scripts/verify-homebrew-formula.sh --version"))
        #expect(finalizerScript.contains("scripts/sync-homebrew-tap.sh"))
        #expect(finalizerScript.contains("scripts/diagnose-homebrew-install.sh --version"))
        #expect(finalizerScript.contains("HOMEBREW_NO_AUTO_UPDATE=1 brew reinstall"))
        #expect(formula.contains("class Ascendkit < Formula"))
        #expect(formula.contains("bin.install \"bin/ascendkit\""))
        #expect(readme.contains("scripts/package-release.sh"))
        #expect(readme.contains("scripts/preflight-public-release.sh"))
        #expect(readme.contains("scripts/install-ascendkit.sh"))
        #expect(readme.contains("scripts/verify-release-assets.sh"))
        #expect(readme.contains("scripts/update-homebrew-formula.sh"))
        #expect(readme.contains("scripts/verify-homebrew-formula.sh"))
        #expect(readme.contains("scripts/diagnose-homebrew-install.sh"))
        #expect(readme.contains("scripts/create-agent-handoff-prompt.sh"))
        #expect(readme.contains("scripts/v1-representative-app-smoke.sh"))
        #expect(readme.contains("scripts/sync-homebrew-tap.sh"))
        #expect(readme.contains("scripts/v1-release-readiness.sh"))
        #expect(readme.contains("scripts/finalize-homebrew-release.sh"))
        #expect(readme.contains("brew tap rushairer/ascendkit"))
        #expect(readme.contains("brew install ascendkit"))
        #expect(readme.contains("ascendkit version --json"))
        #expect(readme.contains("screenshots doctor"))
        #expect(readme.contains("screenshots scaffold-uitests"))
        #expect(readme.contains("swift run ascendkit --help"))
        #expect(readme.contains("GitHub release archives"))
        #expect(cli.contains("AscendKit version:"))
        #expect(ciWorkflow.contains("swift test"))
        #expect(ciWorkflow.contains("actions/checkout@v5"))
        #expect(ciWorkflow.contains("bash -n"))
        #expect(ciWorkflow.contains("scripts/package-release.sh"))
        #expect(ciWorkflow.contains("scripts/diagnose-homebrew-install.sh"))
        #expect(ciWorkflow.contains("scripts/create-agent-handoff-prompt.sh"))
        #expect(ciWorkflow.contains("scripts/v1-release-readiness.sh"))
        #expect(ciWorkflow.contains("scripts/sync-homebrew-tap.sh"))
        #expect(ciWorkflow.contains("scripts/finalize-homebrew-release.sh"))
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
