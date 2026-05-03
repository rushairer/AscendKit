import Testing
@testable import AscendKitCore

@Suite("Agent handoff prompt")
struct AgentHandoffPromptTests {
    @Test("builds concrete guarded prompt")
    func buildsConcreteGuardedPrompt() throws {
        let report = try AgentHandoffPromptBuilder().build(
            request: AgentHandoffPromptRequest(
                appRoot: "/tmp/AscendKitSmokeApp",
                releaseID: "smoke-1.0-b1",
                ascProfile: "smoke-profile",
                playbookReference: "https://example.com/playbook.md"
            ),
            outputPath: "/tmp/ascendkit-agent-prompt.txt"
        )

        #expect(report.appRoot == "/tmp/AscendKitSmokeApp")
        #expect(report.workspacePath == "/tmp/AscendKitSmokeApp/.ascendkit/releases/smoke-1.0-b1")
        #expect(report.outputPath == "/tmp/ascendkit-agent-prompt.txt")
        #expect(report.prompt.contains("App project root: /tmp/AscendKitSmokeApp"))
        #expect(report.prompt.contains("ASC profile: smoke-profile"))
        #expect(report.prompt.contains("Stop: replace AscendKit prompt placeholders before running release commands."))
        #expect(report.prompt.contains("ascendkit workspace next-steps --workspace \"$WORKSPACE\" --json"))
        #expect(!report.prompt.contains("__ASCENDKIT_"))
        #expect(!report.prompt.contains("<<ABSOLUTE_APP_PROJECT_ROOT>>"))
    }

    @Test("refuses placeholder and sample inputs")
    func refusesPlaceholderAndSampleInputs() throws {
        #expect(throws: AscendKitError.invalidArguments("Refusing --app-root: '/path/to/App' is a sample value. Provide the real app-specific value.")) {
            try AgentHandoffPromptBuilder().build(
                request: AgentHandoffPromptRequest(
                    appRoot: "/path/to/App",
                    releaseID: "smoke-1.0-b1",
                    ascProfile: "smoke-profile"
                )
            )
        }

        #expect(throws: AscendKitError.invalidArguments("Refusing --release-id: replace <<...>> placeholders with a real value before generating an agent prompt.")) {
            try AgentHandoffPromptBuilder().build(
                request: AgentHandoffPromptRequest(
                    appRoot: "/tmp/AscendKitSmokeApp",
                    releaseID: "<<RELEASE_ID_FOR_THIS_APP_VERSION>>",
                    ascProfile: "smoke-profile"
                )
            )
        }
    }

    @Test("requires absolute app root")
    func requiresAbsoluteAppRoot() throws {
        #expect(throws: AscendKitError.invalidArguments("Refusing --app-root: provide an absolute path to the real app project root.")) {
            try AgentHandoffPromptBuilder().build(
                request: AgentHandoffPromptRequest(
                    appRoot: "RelativeApp",
                    releaseID: "smoke-1.0-b1",
                    ascProfile: "smoke-profile"
                )
            )
        }
    }
}
