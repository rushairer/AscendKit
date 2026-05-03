import Foundation

public struct AgentHandoffPromptRequest: Codable, Equatable, Sendable {
    public var appRoot: String
    public var releaseID: String
    public var ascProfile: String
    public var playbookReference: String

    public init(
        appRoot: String,
        releaseID: String,
        ascProfile: String,
        playbookReference: String = "https://github.com/rushairer/AscendKit/blob/main/docs/agent-release-playbook.md"
    ) {
        self.appRoot = appRoot
        self.releaseID = releaseID
        self.ascProfile = ascProfile
        self.playbookReference = playbookReference
    }
}

public struct AgentHandoffPromptReport: Codable, Equatable, Sendable {
    public var ascendKitVersion: String?
    public var appRoot: String
    public var releaseID: String
    public var workspacePath: String
    public var ascProfile: String
    public var playbookReference: String
    public var prompt: String
    public var safetyBoundaries: [String]
    public var outputPath: String?

    public init(
        ascendKitVersion: String? = AscendKitVersion.current,
        appRoot: String,
        releaseID: String,
        workspacePath: String,
        ascProfile: String,
        playbookReference: String,
        prompt: String,
        safetyBoundaries: [String],
        outputPath: String? = nil
    ) {
        self.ascendKitVersion = ascendKitVersion
        self.appRoot = appRoot
        self.releaseID = releaseID
        self.workspacePath = workspacePath
        self.ascProfile = ascProfile
        self.playbookReference = playbookReference
        self.prompt = prompt
        self.safetyBoundaries = safetyBoundaries
        self.outputPath = outputPath
    }
}

public struct AgentHandoffPromptBuilder: Sendable {
    public init() {}

    public func build(request: AgentHandoffPromptRequest, outputPath: String? = nil) throws -> AgentHandoffPromptReport {
        try validate(request: request)

        let appRoot = request.appRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let releaseID = request.releaseID.trimmingCharacters(in: .whitespacesAndNewlines)
        let ascProfile = request.ascProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        let playbook = request.playbookReference.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = "\(appRoot.removingTrailingSlashes())/.ascendkit/releases/\(releaseID)"
        let safetyBoundaries = [
            "Do not commit secrets, .ascendkit workspaces, screenshots, reviewer info, ASC identifiers, App Store Connect credentials, or generated release artifacts.",
            "Do not upload binaries. Xcode Cloud handles binary upload.",
            "Do not execute final remote review submission. AscendKit stops at submit handoff; complete final submission manually in App Store Connect.",
            "Before any remote ASC mutation, run the corresponding dry-run or plan command and inspect JSON output.",
            "Use --confirm-remote-mutation only for the specific intended ASC metadata, pricing, privacy, or screenshot mutation.",
            "If App Privacy cannot be published through the API, stop at the documented App Store Connect UI handoff and ask the user to confirm when it is published."
        ]

        let prompt = """
        Use AscendKit to prepare this Apple app for App Store submission.

        App project root: \(appRoot)
        Release id: \(releaseID)
        Release workspace: \(workspace)
        ASC profile: \(ascProfile)
        AscendKit playbook: \(playbook)

        These are concrete values supplied by the user or maintainer. Do not replace them with sample values. If any path, release id, or ASC profile appears invalid, stop and ask the user instead of guessing.

        Follow the playbook exactly. Use the installed ascendkit binary from PATH, not swift run, unless you are contributing to AscendKit itself.

        Safety boundaries:
        \(safetyBoundaries.map { "- \($0)" }.joined(separator: "\n"))

        Start with these shell commands:

        APP_ROOT="\(appRoot)"
        RELEASE_ID="\(releaseID)"
        WORKSPACE="\(workspace)"
        ASC_PROFILE="\(ascProfile)"

        case "$APP_ROOT $RELEASE_ID $ASC_PROFILE" in
          *'<<'*'>>'*)
            echo "Stop: replace AscendKit prompt placeholders before running release commands." >&2
            exit 64
            ;;
        esac

        ascendkit --version
        ascendkit intake inspect --root "$APP_ROOT" --release-id "$RELEASE_ID" --save --json
        ascendkit workspace gitignore --workspace "$WORKSPACE" --fix --json
        ascendkit workspace next-steps --workspace "$WORKSPACE" --json

        During the work, prefer workspace next-steps --json, workspace summary --json, workspace validate-handoff --json, and workspace export-summary --json over ad-hoc prose.

        Finish by reporting:
        - AscendKit version used.
        - Bundle id, app version, build number, and selected ASC build.
        - Metadata locales applied.
        - Screenshot display types uploaded or exact screenshot blockers.
        - Pricing result.
        - App Privacy status.
        - Review handoff status or exact remaining blockers.
        - Validation commands run.
        """

        return AgentHandoffPromptReport(
            appRoot: appRoot,
            releaseID: releaseID,
            workspacePath: workspace,
            ascProfile: ascProfile,
            playbookReference: playbook,
            prompt: prompt,
            safetyBoundaries: safetyBoundaries,
            outputPath: outputPath
        )
    }

    private func validate(request: AgentHandoffPromptRequest) throws {
        let appRoot = request.appRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let releaseID = request.releaseID.trimmingCharacters(in: .whitespacesAndNewlines)
        let ascProfile = request.ascProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        let playbook = request.playbookReference.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !appRoot.isEmpty, !releaseID.isEmpty, !ascProfile.isEmpty else {
            throw AscendKitError.invalidArguments("Missing required --app-root, --release-id, or --asc-profile.")
        }
        guard appRoot.hasPrefix("/") else {
            throw AscendKitError.invalidArguments("Refusing --app-root: provide an absolute path to the real app project root.")
        }
        guard !playbook.isEmpty else {
            throw AscendKitError.invalidArguments("Refusing --playbook: provide a local path or URL to the AscendKit agent release playbook.")
        }

        try rejectSampleValue(label: "--app-root", value: appRoot, samples: [
            "/path/to/App",
            "/absolute/path/to/MyApp",
            "/Users/me/Projects/RealApp",
            "/real/path/to/App",
            "/absolute/path/to/the/real/app"
        ])
        try rejectSampleValue(label: "--release-id", value: releaseID, samples: [
            "app-1.0-b1",
            "myapp-1.0-b1",
            "realapp-1.0-b1",
            "real-app-1.0-b1",
            "real-release-id-for-this-version"
        ])
        try rejectSampleValue(label: "--asc-profile", value: ascProfile, samples: [
            "PROFILE_NAME",
            "real-profile",
            "real-profile-name",
            "real-asc-profile-name"
        ])
    }

    private func rejectSampleValue(label: String, value: String, samples: [String]) throws {
        if value.contains("<<") && value.contains(">>") {
            throw AscendKitError.invalidArguments("Refusing \(label): replace <<...>> placeholders with a real value before generating an agent prompt.")
        }
        if samples.contains(value) {
            throw AscendKitError.invalidArguments("Refusing \(label): '\(value)' is a sample value. Provide the real app-specific value.")
        }
    }
}

private extension String {
    func removingTrailingSlashes() -> String {
        var result = self
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
