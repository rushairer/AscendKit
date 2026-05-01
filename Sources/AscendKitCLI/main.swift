import AscendKitCore
import Foundation

@main
struct AscendKitCommand {
    static func main() async {
        do {
            let runner = CLIRunner(arguments: Array(CommandLine.arguments.dropFirst()))
            let output = try await runner.run()
            if !output.isEmpty {
                print(output)
            }
        } catch let error as AscendKitError {
            fputs("ascendkit: \(error.description)\n", stderr)
            Foundation.exit(2)
        } catch {
            fputs("ascendkit: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}

struct CLIRunner {
    var arguments: [String]
    var fileManager: FileManager = .default

    func run() async throws -> String {
        if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") {
            return Self.help
        }

        let json = arguments.contains("--json")
        let args = arguments.filter { $0 != "--json" }
        guard let group = args.first else { return Self.help }
        let tail = Array(args.dropFirst())

        switch group {
        case "workspace":
            return try workspace(tail, json: json)
        case "intake":
            return try intake(tail, json: json)
        case "doctor":
            return try doctor(tail, json: json)
        case "metadata":
            return try metadata(tail, json: json)
        case "screenshots":
            return try await screenshots(tail, json: json)
        case "asc":
            return try await asc(tail, json: json)
        case "submit":
            return try await submit(tail, json: json)
        case "iap":
            return try iap(tail, json: json)
        default:
            throw AscendKitError.invalidArguments("Unknown command group: \(group)")
        }
    }

    private func workspace(_ args: [String], json: Bool) throws -> String {
        switch args.first {
        case "status":
            let workspace = try loadWorkspace(from: args)
            let status = WorkspaceStatusReader(fileManager: fileManager).read(workspace: workspace)
            return try render(status, json: json) {
                "Workspace \(status.releaseID): \(status.completeStepCount)/\(status.steps.count) step file(s) present"
            }
        case "audit":
            let workspace = try loadWorkspace(from: args)
            let records = try AuditLogReader(fileManager: fileManager).read(workspace: workspace)
            return try render(records, json: json) {
                if records.isEmpty {
                    return "No audit events found"
                }
                return records.map { "\($0.timestamp): \($0.action.rawValue) - \($0.summary)" }.joined(separator: "\n")
            }
        case "list":
            let root = URL(fileURLWithPath: value(after: "--root", in: args) ?? fileManager.currentDirectoryPath)
            let list = WorkspaceLister(fileManager: fileManager).list(baseDirectory: root)
            return try render(list, json: json) {
                if list.releases.isEmpty {
                    return "No release workspaces found under \(root.path)"
                }
                return list.releases.map {
                    "\($0.releaseID): \($0.completeStepCount)/\($0.totalStepCount) step file(s) present"
                }.joined(separator: "\n")
            }
        default:
            throw AscendKitError.invalidArguments("Usage: ascendkit workspace status|audit --workspace PATH [--json] OR ascendkit workspace list [--root PATH] [--json]")
        }
    }

    private func intake(_ args: [String], json: Bool) throws -> String {
        guard args.first == "inspect" else {
            throw AscendKitError.invalidArguments("Usage: ascendkit intake inspect [--project PATH] [--workspace PATH] [--release-id ID] [--save]")
        }

        let options = IntakeOptions(
            searchRoot: value(after: "--root", in: args) ?? fileManager.currentDirectoryPath,
            explicitProjectPath: value(after: "--project", in: args),
            explicitWorkspacePath: value(after: "--workspace", in: args),
            releaseID: value(after: "--release-id", in: args)
        )
        let report = try ProjectDiscovery(fileManager: fileManager).inspect(options: options)

        if args.contains("--save") {
            let store = ReleaseWorkspaceStore(fileManager: fileManager)
            let base = URL(fileURLWithPath: options.searchRoot)
            let workspace = try store.createWorkspace(baseDirectory: base, manifest: report.manifest)
            try store.save(report, to: URL(fileURLWithPath: workspace.paths.intake))
        }

        return try render(report, json: json) {
            "Release \(report.manifest.releaseID): \(report.manifest.targets.count) target(s), \(report.manifest.projects.count) project reference(s)"
        }
    }

    private func doctor(_ args: [String], json: Bool) throws -> String {
        guard args.first == "release" else {
            throw AscendKitError.invalidArguments("Usage: ascendkit doctor release --workspace PATH")
        }
        let workspace = try loadWorkspace(from: args)
        let store = ReleaseWorkspaceStore(fileManager: fileManager)
        let manifest = try store.loadManifest(from: workspace)
        let metadata = try loadIfExists(AppMetadata.self, path: workspace.paths.metadataSource)
        let screenshotPlan = try loadIfExists(ScreenshotPlan.self, path: workspace.paths.screenshotPlan)
        let screenshotImportManifest = try loadIfExists(ScreenshotImportManifest.self, path: workspace.paths.screenshotImportManifest)
        let iapValidationReport = try loadIfExists(IAPValidationReport.self, path: workspace.paths.iapValidation)
        let report = ReleaseDoctor(fileManager: fileManager).run(
            manifest: manifest,
            metadata: metadata,
            screenshotPlan: screenshotPlan,
            screenshotImportManifest: screenshotImportManifest,
            iapValidationReport: iapValidationReport
        )
        try store.save(report, to: URL(fileURLWithPath: workspace.paths.doctorReport))
        try store.appendAudit(.init(action: .doctorRan, summary: "Ran release doctor"), to: workspace)
        return try render(report, json: json) {
            "Doctor complete: \(report.findings.count) finding(s), blockers: \(report.hasBlockers ? "yes" : "no")"
        }
    }

    private func metadata(_ args: [String], json: Bool) throws -> String {
        guard let subcommand = args.first else {
            throw AscendKitError.invalidArguments("Usage: ascendkit metadata init|import-fastlane|lint --workspace PATH")
        }
        let workspace = try loadWorkspace(from: args)
        let store = ReleaseWorkspaceStore(fileManager: fileManager)
        let locale = value(after: "--locale", in: args) ?? "en-US"
        let sourceURL = metadataURL(locale: locale, workspace: workspace)
        let lintURL = metadataLintURL(locale: locale, workspace: workspace)

        switch subcommand {
        case "import-fastlane":
            guard let sourcePath = value(after: "--source", in: args) else {
                throw AscendKitError.invalidArguments("Usage: ascendkit metadata import-fastlane --workspace PATH --source PATH [--json]")
            }
            let sourceRoot = URL(fileURLWithPath: sourcePath)
            let imported = try FastlaneMetadataImporter(fileManager: fileManager).loadAll(from: sourceRoot)
            for metadata in imported {
                try store.save(metadata, to: metadataURL(locale: metadata.locale, workspace: workspace))
            }
            try store.appendAudit(.init(action: .metadataInitialized, summary: "Imported fastlane metadata"), to: workspace)
            return try render(imported, json: json) {
                "Imported fastlane metadata for \(imported.count) locale(s)."
            }
        case "init":
            var metadata = AppMetadata.template
            metadata.locale = locale
            try store.save(metadata, to: sourceURL)
            try store.appendAudit(.init(action: .metadataInitialized, summary: "Initialized \(locale) metadata template"), to: workspace)
            return try render(metadata, json: json) { "Metadata template written to \(sourceURL.path)" }
        case "status":
            let catalog = MetadataCatalogReader(fileManager: fileManager).read(workspace: workspace)
            return try render(catalog, json: json) {
                if catalog.bundles.isEmpty {
                    return "No local metadata bundles found"
                }
                return catalog.bundles.map { bundle in
                    let lint = bundle.lintFindingCount.map { ", \($0) lint finding(s)" } ?? ""
                    return "\(bundle.kind.rawValue)/\(bundle.locale)\(lint)"
                }.joined(separator: "\n")
            }
        case "lint":
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw AscendKitError.fileNotFound(sourceURL.path)
            }
            let metadata = try AscendKitJSON.decoder.decode(AppMetadata.self, from: Data(contentsOf: sourceURL))
            let report = MetadataLinter().lint(metadata: metadata)
            try store.save(report, to: lintURL)
            try store.appendAudit(.init(action: .metadataLinted, summary: "Linted \(locale) metadata"), to: workspace)
            return try render(report, json: json) { "Metadata lint complete: \(report.findings.count) finding(s)" }
        case "diff":
            let localMetadata = try loadLocalMetadata(workspace: workspace)
            let observed = try loadIfExists(MetadataObservedState.self, path: workspace.paths.ascObservedState)
            let report = MetadataDiffEngine().diff(local: localMetadata, observed: observed)
            try store.save(report, to: URL(fileURLWithPath: workspace.paths.ascDiff))
            try store.appendAudit(.init(action: .metadataDiffed, summary: "Diffed local metadata against observed state"), to: workspace)
            return try render(report, json: json) {
                "Metadata diff complete: \(report.changedCount) changed/missing field(s)"
            }
        case "sync":
            throw AscendKitError.unsupported("metadata sync is reserved for a later ASC dry-run/apply slice.")
        default:
            throw AscendKitError.invalidArguments("Unknown metadata command: \(subcommand)")
        }
    }

    private func screenshots(_ args: [String], json: Bool) async throws -> String {
        guard let subcommand = args.first else {
            throw AscendKitError.invalidArguments("Usage: ascendkit screenshots plan|readiness|upload-plan|upload --workspace PATH")
        }
        let workspace = try loadWorkspace(from: args)
        let store = ReleaseWorkspaceStore(fileManager: fileManager)
        let planURL = URL(fileURLWithPath: workspace.paths.screenshotPlan)

        switch subcommand {
        case "plan":
            let manifest = try store.loadManifest(from: workspace)
            let input = ScreenshotPlanningInput(
                appCategory: value(after: "--category", in: args) ?? "App",
                targetAudience: value(after: "--audience", in: args) ?? "target users",
                positioning: value(after: "--positioning", in: args) ?? "",
                keyFeatures: list(after: "--features", in: args),
                importantScreens: list(after: "--screens", in: args),
                platforms: platformList(after: "--platforms", in: args, default: Array(Set(manifest.targets.map(\.platform).filter { $0 != .unknown }))),
                locales: list(after: "--locales", in: args, default: ["en-US"])
            )
            let plan = ScreenshotPlan.makeDeterministicPlan(
                from: input,
                sourceDirectory: value(after: "--source", in: args)
            )
            try store.save(plan, to: planURL)
            try store.appendAudit(.init(action: .screenshotPlanSaved, summary: "Saved screenshot plan"), to: workspace)
            return try render(plan, json: json) { "Screenshot plan written with \(plan.items.count) planned screen(s)" }
        case "readiness":
            guard fileManager.fileExists(atPath: planURL.path) else {
                throw AscendKitError.fileNotFound(planURL.path)
            }
            let plan = try AscendKitJSON.decoder.decode(ScreenshotPlan.self, from: Data(contentsOf: planURL))
            let source = value(after: "--source", in: args).map { URL(fileURLWithPath: $0) }
            let result = ScreenshotReadinessEvaluator(fileManager: fileManager).evaluate(plan: plan, sourceDirectory: source)
            try store.appendAudit(.init(action: .screenshotReadinessChecked, summary: "Checked screenshot readiness"), to: workspace)
            return try render(result, json: json) { "Screenshot readiness: \(result.ready ? "ready" : "not ready") with \(result.findings.count) finding(s)" }
        case "import":
            guard fileManager.fileExists(atPath: planURL.path) else {
                throw AscendKitError.fileNotFound(planURL.path)
            }
            guard let sourcePath = value(after: "--source", in: args) else {
                throw AscendKitError.invalidArguments("Usage: ascendkit screenshots import --workspace PATH --source PATH [--json]")
            }
            let plan = try AscendKitJSON.decoder.decode(ScreenshotPlan.self, from: Data(contentsOf: planURL))
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let readiness = ScreenshotReadinessEvaluator(fileManager: fileManager).evaluate(plan: plan, sourceDirectory: sourceURL)
            guard readiness.ready else {
                return try render(readiness, json: json) {
                    "Screenshot import is not ready: \(readiness.findings.count) finding(s)"
                }
            }
            let manifest = ScreenshotImporter(fileManager: fileManager).makeManifest(plan: plan, sourceDirectory: sourceURL)
            try store.save(manifest, to: URL(fileURLWithPath: workspace.paths.screenshotImportManifest))
            try store.appendAudit(.init(action: .screenshotImportManifestSaved, summary: "Saved screenshot import manifest"), to: workspace)
            return try render(manifest, json: json) {
                "Screenshot import manifest saved with \(manifest.artifacts.count) artifact(s)"
            }
        case "import-fastlane":
            guard let sourcePath = value(after: "--source", in: args) else {
                throw AscendKitError.invalidArguments("Usage: ascendkit screenshots import-fastlane --workspace PATH --source PATH [--locales en-US,zh-Hans] [--json]")
            }
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let manifest = ScreenshotImporter(fileManager: fileManager).makeFastlaneManifest(
                sourceDirectory: sourceURL,
                locales: list(after: "--locales", in: args)
            )
            guard !manifest.artifacts.isEmpty else {
                throw AscendKitError.invalidState("No fastlane screenshots found under \(sourceURL.path)")
            }
            try store.save(manifest, to: URL(fileURLWithPath: workspace.paths.screenshotImportManifest))
            try store.appendAudit(.init(action: .screenshotImportManifestSaved, summary: "Imported fastlane screenshot manifest"), to: workspace)
            return try render(manifest, json: json) {
                "Fastlane screenshot import manifest saved with \(manifest.artifacts.count) artifact(s)"
            }
        case "compose":
            guard let importManifest = try loadIfExists(ScreenshotImportManifest.self, path: workspace.paths.screenshotImportManifest) else {
                throw AscendKitError.fileNotFound(workspace.paths.screenshotImportManifest)
            }
            let mode = ScreenshotCompositionMode(rawValue: value(after: "--mode", in: args) ?? "storeReadyCopy") ?? .storeReadyCopy
            let outputRoot = URL(fileURLWithPath: workspace.paths.root).appendingPathComponent("screenshots/composed")
            let manifest = try ScreenshotComposer(fileManager: fileManager).compose(
                importManifest: importManifest,
                outputRoot: outputRoot,
                mode: mode
            )
            try store.save(manifest, to: URL(fileURLWithPath: workspace.paths.screenshotCompositionManifest))
            try store.appendAudit(.init(action: .screenshotCompositionManifestSaved, summary: "Saved screenshot composition manifest"), to: workspace)
            return try render(manifest, json: json) {
                "Screenshot composition manifest saved with \(manifest.artifacts.count) artifact(s)"
            }
        case "upload-plan":
            let importManifest = try loadIfExists(ScreenshotImportManifest.self, path: workspace.paths.screenshotImportManifest)
            let compositionManifest = try loadIfExists(ScreenshotCompositionManifest.self, path: workspace.paths.screenshotCompositionManifest)
            let observedState = try loadIfExists(MetadataObservedState.self, path: workspace.paths.ascObservedState)
            let plan = ScreenshotUploadPlanBuilder().build(
                importManifest: importManifest,
                compositionManifest: compositionManifest,
                observedState: observedState,
                displayTypeOverride: value(after: "--display-type", in: args),
                replaceExistingRemoteScreenshots: args.contains("--replace-existing")
            )
            try store.save(plan, to: URL(fileURLWithPath: workspace.paths.screenshotUploadPlan))
            try store.appendAudit(
                .init(
                    action: .screenshotUploadPlanned,
                    summary: "Planned ASC screenshot upload",
                    details: ["items": "\(plan.items.count)"]
                ),
                to: workspace
            )
            return try render(plan, json: json) {
                "Screenshot upload plan saved with \(plan.items.count) item(s) and \(plan.findings.count) finding(s); no ASC mutation was made."
            }
        case "upload":
            let result = try await executeScreenshotUpload(
                workspace: workspace,
                store: store,
                confirmed: args.contains("--confirm-remote-mutation"),
                replaceExisting: args.contains("--replace-existing")
            )
            return try render(result, json: json) {
                result.executed
                    ? "Screenshot upload completed with \(result.uploadedCount) uploaded screenshot(s)."
                    : "Screenshot upload was not executed: \(result.findings.joined(separator: " "))"
            }
        case "capture":
            throw AscendKitError.unsupported("screenshots capture is deferred; first wave supports planning, import readiness, import manifests, and local composition organization.")
        default:
            throw AscendKitError.invalidArguments("Unknown screenshots command: \(subcommand)")
        }
    }

    private func executeScreenshotUpload(
        workspace: ReleaseWorkspace,
        store: ReleaseWorkspaceStore,
        confirmed: Bool,
        replaceExisting: Bool
    ) async throws -> ScreenshotUploadExecutionResult {
        let plan: ScreenshotUploadPlan
        if replaceExisting {
            let existingPlan = try loadIfExists(ScreenshotUploadPlan.self, path: workspace.paths.screenshotUploadPlan)
            plan = ScreenshotUploadPlanBuilder().build(
                importManifest: try loadIfExists(ScreenshotImportManifest.self, path: workspace.paths.screenshotImportManifest),
                compositionManifest: try loadIfExists(ScreenshotCompositionManifest.self, path: workspace.paths.screenshotCompositionManifest),
                observedState: try loadIfExists(MetadataObservedState.self, path: workspace.paths.ascObservedState),
                displayTypeOverride: existingPlan?.items.first?.displayType,
                replaceExistingRemoteScreenshots: true
            )
        } else {
            plan = try loadIfExists(ScreenshotUploadPlan.self, path: workspace.paths.screenshotUploadPlan)
                ?? ScreenshotUploadPlanBuilder().build(
                    importManifest: try loadIfExists(ScreenshotImportManifest.self, path: workspace.paths.screenshotImportManifest),
                    compositionManifest: try loadIfExists(ScreenshotCompositionManifest.self, path: workspace.paths.screenshotCompositionManifest),
                    observedState: try loadIfExists(MetadataObservedState.self, path: workspace.paths.ascObservedState)
                )
        }
        try store.save(plan, to: URL(fileURLWithPath: workspace.paths.screenshotUploadPlan))
        guard confirmed else {
            let result = ScreenshotUploadExecutionResult(
                executed: false,
                findings: ["Missing --confirm-remote-mutation. No screenshot upload request was executed."]
            )
            try store.save(result, to: URL(fileURLWithPath: workspace.paths.screenshotUploadResult))
            return result
        }
        guard let authConfig = try loadIfExists(ASCAuthConfig.self, path: workspace.paths.ascAuthConfig) else {
            throw AscendKitError.invalidState("ASC auth config is missing. Run asc auth init first.")
        }
        let authStatus = ASCAuthStatus(config: authConfig)
        guard authStatus.configured else {
            throw AscendKitError.invalidState("ASC auth config is not ready: \(authStatus.findings.joined(separator: " "))")
        }
        let privateKey = try ASCSecretResolver(fileManager: fileManager).resolve(authConfig.privateKey)
        let token = try ASCJWTSigner().token(config: authConfig, privateKeyPEM: privateKey)
        let result = try await ASCAPIClient().executeScreenshotUpload(
            plan: plan,
            confirmRemoteMutation: confirmed,
            token: token
        )
        try store.save(result, to: URL(fileURLWithPath: workspace.paths.screenshotUploadResult))
        try store.appendAudit(
            .init(
                action: .screenshotUploadExecuted,
                summary: "Executed ASC screenshot upload",
                details: ["uploaded": "\(result.uploadedCount)"]
            ),
            to: workspace
        )
        return result
    }

    private func asc(_ args: [String], json: Bool) async throws -> String {
        guard let domain = args.first else {
            throw AscendKitError.invalidArguments("Usage: ascendkit asc builds list|import OR ascendkit asc metadata import")
        }
        if domain == "metadata" {
            return try await ascMetadata(args, json: json)
        }
        if domain == "auth" {
            return try ascAuth(args, json: json)
        }
        if domain == "lookup" {
            return try await ascLookup(args, json: json)
        }
        if domain == "apps" {
            return try await ascApps(args, json: json)
        }
        if domain == "pricing" {
            return try await ascPricing(args, json: json)
        }
        if domain == "privacy" {
            return try await ascPrivacy(args, json: json)
        }
        guard domain == "builds" else {
            throw AscendKitError.invalidArguments("Usage: ascendkit asc auth init|check OR ascendkit asc lookup plan|apps OR ascendkit asc apps lookup OR ascendkit asc builds list|import OR ascendkit asc metadata import OR ascendkit asc pricing set-free OR ascendkit asc privacy set-not-collected")
        }
        switch args.dropFirst().first {
        case "observe":
            let workspace = try loadWorkspace(from: args)
            let store = ReleaseWorkspaceStore(fileManager: fileManager)
            let report = try await observeASCBuilds(workspace: workspace, store: store)
            return try render(report, json: json) {
                "Observed \(report.candidates.count) ASC build candidate(s), \(report.processableCandidates.count) processable."
            }
        case "list":
            if let workspacePath = value(after: "--workspace", in: args) {
                let workspace = try ReleaseWorkspaceStore(fileManager: fileManager).loadWorkspace(root: URL(fileURLWithPath: workspacePath))
                let report = try loadIfExists(BuildCandidatesReport.self, path: workspace.paths.buildCandidates)
                    ?? BuildCandidatesReport(source: "workspace", candidates: [])
                return try render(report, json: json) {
                    "\(report.candidates.count) build candidate(s), \(report.processableCandidates.count) processable"
                }
            }
            let note = ASCCapabilityNote(
                domain: "build discovery",
                operation: "list eligible builds",
                status: .planned,
                caveats: ["First wave does not authenticate with App Store Connect or perform remote requests."],
                fallbackStrategy: "Use Xcode Cloud and App Store Connect manually, then record selected build state locally in a later slice."
            )
            return try render(note, json: json) {
                "ASC build lookup is planned; no remote request was made."
            }
        case "import":
            let workspace = try loadWorkspace(from: args)
            guard let id = value(after: "--id", in: args),
                  let version = value(after: "--version", in: args),
                  let buildNumber = value(after: "--build", in: args) else {
                throw AscendKitError.invalidArguments("Usage: ascendkit asc builds import --workspace PATH --id ID --version VERSION --build BUILD [--state STATE] [--json]")
            }
            let candidate = BuildCandidate(
                id: id,
                version: version,
                buildNumber: buildNumber,
                processingState: value(after: "--state", in: args) ?? "unknown"
            )
            let existing = try loadIfExists(BuildCandidatesReport.self, path: workspace.paths.buildCandidates)
            let candidates = upsert(candidate: candidate, into: existing?.candidates ?? [])
            let report = BuildCandidatesReport(source: "manual-import", candidates: candidates)
            let store = ReleaseWorkspaceStore(fileManager: fileManager)
            try store.save(report, to: URL(fileURLWithPath: workspace.paths.buildCandidates))
            try store.appendAudit(.init(action: .buildCandidatesImported, summary: "Imported build candidate"), to: workspace)
            return try render(report, json: json) {
                "Imported \(report.candidates.count) build candidate(s)"
            }
        default:
            throw AscendKitError.invalidArguments("Usage: ascendkit asc builds observe --workspace PATH [--json] OR ascendkit asc builds list [--workspace PATH] [--json] OR ascendkit asc builds import --workspace PATH --id ID --version VERSION --build BUILD [--state STATE] [--json]")
        }
    }

    private func observeASCBuilds(workspace: ReleaseWorkspace, store: ReleaseWorkspaceStore) async throws -> BuildCandidatesReport {
        guard let authConfig = try loadIfExists(ASCAuthConfig.self, path: workspace.paths.ascAuthConfig) else {
            throw AscendKitError.invalidState("ASC auth config is missing. Run asc auth init first.")
        }
        let authStatus = ASCAuthStatus(config: authConfig)
        guard authStatus.configured else {
            throw AscendKitError.invalidState("ASC auth config is not ready: \(authStatus.findings.joined(separator: " "))")
        }
        guard let appsReport = try loadIfExists(ASCAppsLookupReport.self, path: workspace.paths.ascApps),
              let app = appsReport.apps.first else {
            throw AscendKitError.invalidState("ASC app lookup observation is missing. Run asc apps lookup first.")
        }
        let manifest = try store.loadManifest(from: workspace)
        let target = manifest.targets.first(where: \.isAppStoreApplication)
        let privateKey = try ASCSecretResolver(fileManager: fileManager).resolve(authConfig.privateKey)
        let token = try ASCJWTSigner().token(config: authConfig, privateKeyPEM: privateKey)
        let report = try await ASCAPIClient().lookupBuilds(
            appID: app.id,
            version: target?.version.marketingVersion,
            buildNumber: target?.version.buildNumber,
            token: token
        )
        try store.save(report, to: URL(fileURLWithPath: workspace.paths.buildCandidates))
        try store.appendAudit(
            .init(
                action: .buildCandidatesImported,
                summary: "Observed ASC build candidates",
                details: ["candidates": "\(report.candidates.count)"]
            ),
            to: workspace
        )
        return report
    }

    private func ascAuth(_ args: [String], json: Bool) throws -> String {
        guard let subcommand = args.dropFirst().first else {
            throw AscendKitError.invalidArguments("Usage: ascendkit asc auth init|check --workspace PATH")
        }

        switch subcommand {
        case "init":
            let workspace = try loadWorkspace(from: args)
            let store = ReleaseWorkspaceStore(fileManager: fileManager)
            let config: ASCAuthConfig
            if let profileName = value(after: "--profile", in: args) {
                config = try ASCAuthProfileStore(fileManager: fileManager).load(name: profileName).config
            } else if let issuerID = value(after: "--issuer-id", in: args),
                  let keyID = value(after: "--key-id", in: args),
                  let providerValue = value(after: "--private-key-provider", in: args),
                  let provider = secretProvider(from: providerValue),
                      let privateKeyRef = value(after: "--private-key-ref", in: args) {
                config = ASCAuthConfig(
                    issuerID: issuerID,
                    keyID: keyID,
                    privateKey: SecretRef(provider: provider, identifier: privateKeyRef)
                )
            } else {
                throw AscendKitError.invalidArguments("Usage: ascendkit asc auth init --workspace PATH (--profile NAME | --issuer-id ID --key-id ID --private-key-provider env|file|keychain --private-key-ref REF) [--json]")
            }
            let status = ASCAuthStatus(config: config)
            try store.save(config, to: URL(fileURLWithPath: workspace.paths.ascAuthConfig))
            try store.appendAudit(.init(action: .ascAuthInitialized, summary: "Initialized ASC auth config"), to: workspace)
            return try render(status, json: json) {
                status.configured ? "ASC auth config saved with redacted secret reference." : "ASC auth config saved but has \(status.findings.count) finding(s)."
            }
        case "check":
            let workspace = try loadWorkspace(from: args)
            let store = ReleaseWorkspaceStore(fileManager: fileManager)
            let config = try loadIfExists(ASCAuthConfig.self, path: workspace.paths.ascAuthConfig)
            let status = ASCAuthStatus(config: config)
            try store.appendAudit(.init(action: .ascAuthChecked, summary: "Checked ASC auth config"), to: workspace)
            return try render(status, json: json) {
                status.configured ? "ASC auth config is present." : "ASC auth config is not ready: \(status.findings.joined(separator: " "))"
            }
        case "save-profile":
            guard let name = value(after: "--name", in: args),
                  let issuerID = value(after: "--issuer-id", in: args),
                  let keyID = value(after: "--key-id", in: args),
                  let providerValue = value(after: "--private-key-provider", in: args),
                  let provider = secretProvider(from: providerValue),
                  let privateKeyRef = value(after: "--private-key-ref", in: args) else {
                throw AscendKitError.invalidArguments("Usage: ascendkit asc auth save-profile --name NAME --issuer-id ID --key-id ID --private-key-provider env|file|keychain --private-key-ref REF [--json]")
            }
            let profile = ASCAuthProfile(
                name: name,
                config: ASCAuthConfig(
                    issuerID: issuerID,
                    keyID: keyID,
                    privateKey: SecretRef(provider: provider, identifier: privateKeyRef)
                )
            )
            let url = try ASCAuthProfileStore(fileManager: fileManager).save(profile)
            let status = ASCAuthStatus(config: profile.config)
            return try render(status, json: json) {
                "ASC auth profile saved to \(url.path) with owner-only permissions."
            }
        case "profiles":
            let profiles = ASCAuthProfileStore(fileManager: fileManager).list().map { profile in
                ASCAuthStatus(config: profile.config)
            }
            return try render(profiles, json: json) {
                "\(profiles.count) ASC auth profile(s) found."
            }
        default:
            throw AscendKitError.invalidArguments("Usage: ascendkit asc auth init|check|save-profile|profiles")
        }
    }

    private func ascLookup(_ args: [String], json: Bool) async throws -> String {
        guard let subcommand = args.dropFirst().first else {
            throw AscendKitError.invalidArguments("Usage: ascendkit asc lookup plan|apps --workspace PATH [--json]")
        }
        let workspace = try loadWorkspace(from: args)
        let store = ReleaseWorkspaceStore(fileManager: fileManager)
        let manifest = try store.loadManifest(from: workspace)

        switch subcommand {
        case "plan":
            let authConfig = try loadIfExists(ASCAuthConfig.self, path: workspace.paths.ascAuthConfig)
            let authStatus = ASCAuthStatus(config: authConfig)
            let plan = ASCLookupPlanBuilder().build(manifest: manifest, authStatus: authStatus)
            try store.save(plan, to: URL(fileURLWithPath: workspace.paths.ascLookupPlan))
            try store.appendAudit(.init(action: .ascLookupPlanned, summary: "Planned ASC lookup dry run"), to: workspace)
            return try render(plan, json: json) {
                "ASC lookup dry-run plan saved with \(plan.steps.count) step(s) and \(plan.findings.count) finding(s)."
            }
        case "apps":
            let report = try await performASCAppsLookup(workspace: workspace, manifest: manifest, store: store)
            return try render(report, json: json) {
                "ASC apps lookup observed \(report.apps.count) app(s) with \(report.findings.count) finding(s); no ASC mutation was made."
            }
        default:
            throw AscendKitError.invalidArguments("Usage: ascendkit asc lookup plan|apps --workspace PATH [--json]")
        }
    }

    private func ascApps(_ args: [String], json: Bool) async throws -> String {
        guard args.dropFirst().first == "lookup" else {
            throw AscendKitError.invalidArguments("Usage: ascendkit asc apps lookup --workspace PATH [--json]")
        }
        let workspace = try loadWorkspace(from: args)
        let store = ReleaseWorkspaceStore(fileManager: fileManager)
        let manifest = try store.loadManifest(from: workspace)
        let report = try await performASCAppsLookup(workspace: workspace, manifest: manifest, store: store)
        return try render(report, json: json) {
            "ASC apps lookup observed \(report.apps.count) app(s) with \(report.findings.count) finding(s); no ASC mutation was made."
        }
    }

    private func performASCAppsLookup(
        workspace: ReleaseWorkspace,
        manifest: ReleaseManifest,
        store: ReleaseWorkspaceStore
    ) async throws -> ASCAppsLookupReport {
        guard let authConfig = try loadIfExists(ASCAuthConfig.self, path: workspace.paths.ascAuthConfig) else {
            throw AscendKitError.invalidState("ASC auth config is missing. Run asc auth init first.")
        }
        let authStatus = ASCAuthStatus(config: authConfig)
        guard authStatus.configured else {
            throw AscendKitError.invalidState("ASC auth config is not ready: \(authStatus.findings.joined(separator: " "))")
        }
        let bundleIDs = orderedUnique(
            manifest.targets
                .filter(\.isAppStoreApplication)
                .compactMap(\.bundleIdentifier)
                .filter { !$0.isEmpty }
        )
        let privateKey = try ASCSecretResolver(fileManager: fileManager).resolve(authConfig.privateKey)
        let token = try ASCJWTSigner().token(config: authConfig, privateKeyPEM: privateKey)
        let report = try await ASCAPIClient().lookupApps(bundleIDs: bundleIDs, token: token)
        try store.save(report, to: URL(fileURLWithPath: workspace.paths.ascApps))
        try store.appendAudit(
            .init(
                action: .ascAppsObserved,
                summary: "Observed ASC apps lookup",
                details: ["bundleIDs": bundleIDs.joined(separator: ",")]
            ),
            to: workspace
        )
        return report
    }

    private func ascMetadata(_ args: [String], json: Bool) async throws -> String {
        guard let subcommand = args.dropFirst().first else {
            throw AscendKitError.invalidArguments("Usage: ascendkit asc metadata import|observe|plan|requests|apply --workspace PATH [--file PATH] [--json]")
        }
        let workspace = try loadWorkspace(from: args)
        let store = ReleaseWorkspaceStore(fileManager: fileManager)

        switch subcommand {
        case "import":
            guard let filePath = value(after: "--file", in: args) else {
                throw AscendKitError.invalidArguments("Usage: ascendkit asc metadata import --workspace PATH --file PATH [--json]")
            }
            let sourceURL = URL(fileURLWithPath: filePath)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw AscendKitError.fileNotFound(sourceURL.path)
            }
            let observed = try AscendKitJSON.decoder.decode(MetadataObservedState.self, from: Data(contentsOf: sourceURL))
            try store.save(observed, to: URL(fileURLWithPath: workspace.paths.ascObservedState))
            try store.appendAudit(.init(action: .ascObservedStateImported, summary: "Imported ASC observed metadata state"), to: workspace)
            return try render(observed, json: json) {
                "Imported observed metadata for \(observed.metadataByLocale.count) locale(s); no ASC mutation was made."
            }
        case "observe":
            let observed = try await observeASCMetadata(workspace: workspace, store: store)
            return try render(observed, json: json) {
                "Observed ASC metadata for \(observed.metadataByLocale.count) locale(s); no ASC mutation was made."
            }
        case "plan":
            let plan = try planASCMetadata(workspace: workspace, store: store)
            return try render(plan, json: json) {
                "ASC metadata dry-run plan saved with \(plan.operations.count) operation(s); no ASC mutation was made."
            }
        case "requests":
            let requestPlan = try planASCMetadataRequests(workspace: workspace, store: store)
            return try render(requestPlan, json: json) {
                "ASC metadata request dry-run plan saved with \(requestPlan.requests.count) request(s); no ASC mutation was made."
            }
        case "apply":
            let result = try await applyASCMetadata(workspace: workspace, store: store, confirmed: args.contains("--confirm-remote-mutation"))
            return try render(result, json: json) {
                result.applied
                    ? "ASC metadata apply completed with \(result.responses.count) response(s)."
                    : "ASC metadata apply was not executed: \(result.findings.joined(separator: " "))"
            }
        default:
            throw AscendKitError.invalidArguments("Usage: ascendkit asc metadata import|observe|plan|requests|apply --workspace PATH [--file PATH] [--json]")
        }
    }

    private func planASCMetadata(workspace: ReleaseWorkspace, store: ReleaseWorkspaceStore) throws -> ASCMetadataMutationPlan {
        let localMetadata = try loadLocalMetadata(workspace: workspace)
        let observed = try loadIfExists(MetadataObservedState.self, path: workspace.paths.ascObservedState)
        let plan = ASCMetadataMutationPlanner().plan(local: localMetadata, observed: observed)
        try store.save(plan, to: URL(fileURLWithPath: workspace.paths.ascMetadataPlan))
        try store.appendAudit(
            .init(
                action: .ascMetadataPlanned,
                summary: "Planned ASC metadata dry-run mutation",
                details: ["operations": "\(plan.operations.count)"]
            ),
            to: workspace
        )
        return plan
    }

    private func planASCMetadataRequests(workspace: ReleaseWorkspace, store: ReleaseWorkspaceStore) throws -> ASCMetadataRequestPlan {
        let mutationPlan = try loadIfExists(ASCMetadataMutationPlan.self, path: workspace.paths.ascMetadataPlan)
            ?? planASCMetadata(workspace: workspace, store: store)
        let requestPlan = ASCMetadataRequestPlanBuilder().build(from: mutationPlan)
        try store.save(requestPlan, to: URL(fileURLWithPath: workspace.paths.ascMetadataRequests))
        try store.appendAudit(
            .init(
                action: .ascMetadataRequestsPlanned,
                summary: "Planned ASC metadata request dry run",
                details: ["requests": "\(requestPlan.requests.count)"]
            ),
            to: workspace
        )
        return requestPlan
    }

    private func applyASCMetadata(
        workspace: ReleaseWorkspace,
        store: ReleaseWorkspaceStore,
        confirmed: Bool
    ) async throws -> ASCMetadataApplyResult {
        guard confirmed else {
            let result = ASCMetadataApplyResult(
                applied: false,
                findings: ["Missing --confirm-remote-mutation. No remote request was executed."]
            )
            try store.save(result, to: URL(fileURLWithPath: workspace.paths.ascMetadataApplyResult))
            return result
        }
        guard let authConfig = try loadIfExists(ASCAuthConfig.self, path: workspace.paths.ascAuthConfig) else {
            throw AscendKitError.invalidState("ASC auth config is missing. Run asc auth init first.")
        }
        let authStatus = ASCAuthStatus(config: authConfig)
        guard authStatus.configured else {
            throw AscendKitError.invalidState("ASC auth config is not ready: \(authStatus.findings.joined(separator: " "))")
        }
        let requestPlan = try loadIfExists(ASCMetadataRequestPlan.self, path: workspace.paths.ascMetadataRequests)
            ?? planASCMetadataRequests(workspace: workspace, store: store)
        let privateKey = try ASCSecretResolver(fileManager: fileManager).resolve(authConfig.privateKey)
        let token = try ASCJWTSigner().token(config: authConfig, privateKeyPEM: privateKey)
        let result = try await ASCAPIClient().applyMetadataRequests(requestPlan, token: token)
        try store.save(result, to: URL(fileURLWithPath: workspace.paths.ascMetadataApplyResult))
        try store.appendAudit(
            .init(
                action: .ascMetadataApplied,
                summary: "Applied ASC metadata remote mutations",
                details: ["responses": "\(result.responses.count)"]
            ),
            to: workspace
        )
        return result
    }

    private func observeASCMetadata(workspace: ReleaseWorkspace, store: ReleaseWorkspaceStore) async throws -> MetadataObservedState {
        guard let authConfig = try loadIfExists(ASCAuthConfig.self, path: workspace.paths.ascAuthConfig) else {
            throw AscendKitError.invalidState("ASC auth config is missing. Run asc auth init first.")
        }
        let authStatus = ASCAuthStatus(config: authConfig)
        guard authStatus.configured else {
            throw AscendKitError.invalidState("ASC auth config is not ready: \(authStatus.findings.joined(separator: " "))")
        }
        guard let appsReport = try loadIfExists(ASCAppsLookupReport.self, path: workspace.paths.ascApps),
              let app = appsReport.apps.first else {
            throw AscendKitError.invalidState("ASC app lookup observation is missing. Run asc apps lookup first.")
        }
        let manifest = try store.loadManifest(from: workspace)
        let target = manifest.targets.first(where: \.isAppStoreApplication)
        let versionString = target?.version.marketingVersion
        let privateKey = try ASCSecretResolver(fileManager: fileManager).resolve(authConfig.privateKey)
        let token = try ASCJWTSigner().token(config: authConfig, privateKeyPEM: privateKey)
        let observed = try await ASCAPIClient().observeMetadata(
            appID: app.id,
            versionString: versionString,
            platform: target?.platform,
            token: token
        )
        try store.save(observed, to: URL(fileURLWithPath: workspace.paths.ascObservedState))
        try store.appendAudit(
            .init(
                action: .ascObservedStateImported,
                summary: "Observed ASC metadata state",
                details: ["appID": app.id]
            ),
            to: workspace
        )
        return observed
    }

    private func ascPricing(_ args: [String], json: Bool) async throws -> String {
        guard args.dropFirst().first == "set-free" else {
            throw AscendKitError.invalidArguments("Usage: ascendkit asc pricing set-free --workspace PATH [--app-id ID] [--base-territory USA] [--confirm-remote-mutation] [--json]")
        }
        let workspace = try loadWorkspace(from: args)
        let store = ReleaseWorkspaceStore(fileManager: fileManager)
        guard let authConfig = try loadIfExists(ASCAuthConfig.self, path: workspace.paths.ascAuthConfig) else {
            throw AscendKitError.invalidState("ASC auth config is missing. Run asc auth init first.")
        }
        let authStatus = ASCAuthStatus(config: authConfig)
        guard authStatus.configured else {
            throw AscendKitError.invalidState("ASC auth config is not ready: \(authStatus.findings.joined(separator: " "))")
        }

        let appID: String
        if let explicitAppID = value(after: "--app-id", in: args), !explicitAppID.isEmpty {
            appID = explicitAppID
        } else {
            guard let appsReport = try loadIfExists(ASCAppsLookupReport.self, path: workspace.paths.ascApps),
                  let observedAppID = appsReport.apps.first?.id else {
                throw AscendKitError.invalidState("ASC app ID is missing. Run asc apps lookup first or pass --app-id.")
            }
            appID = observedAppID
        }

        let baseTerritory = value(after: "--base-territory", in: args) ?? "USA"
        let privateKey = try ASCSecretResolver(fileManager: fileManager).resolve(authConfig.privateKey)
        let token = try ASCJWTSigner().token(config: authConfig, privateKeyPEM: privateKey)
        let result = try await ASCAPIClient().setFreeAppPricing(
            appID: appID,
            baseTerritory: baseTerritory,
            confirmRemoteMutation: args.contains("--confirm-remote-mutation"),
            token: token
        )
        try store.save(result, to: URL(fileURLWithPath: workspace.paths.ascPricingResult))
        try store.appendAudit(
            .init(
                action: .ascPricingApplied,
                summary: result.executed ? "Set ASC app pricing to free" : "Planned ASC app pricing mutation",
                details: [
                    "appID": appID,
                    "baseTerritory": baseTerritory,
                    "executed": "\(result.executed)"
                ]
            ),
            to: workspace
        )
        return try render(result, json: json) {
            result.executed
                ? "ASC free pricing was set for app \(appID)."
                : "ASC free pricing was planned but not executed; pass --confirm-remote-mutation to apply it."
        }
    }

    private func ascPrivacy(_ args: [String], json: Bool) async throws -> String {
        guard args.dropFirst().first == "set-not-collected" else {
            throw AscendKitError.invalidArguments("Usage: ascendkit asc privacy set-not-collected --workspace PATH [--app-id ID] --confirm-remote-mutation [--json]")
        }
        guard args.contains("--confirm-remote-mutation") else {
            let responses: [ReviewSubmissionExecutionResponse] = []
            return try render(responses, json: json) {
                "ASC app privacy was not changed: pass --confirm-remote-mutation to publish Data Not Collected answers."
            }
        }

        let workspace = try loadWorkspace(from: args)
        let store = ReleaseWorkspaceStore(fileManager: fileManager)
        guard let authConfig = try loadIfExists(ASCAuthConfig.self, path: workspace.paths.ascAuthConfig) else {
            throw AscendKitError.invalidState("ASC auth config is missing. Run asc auth init first.")
        }
        let authStatus = ASCAuthStatus(config: authConfig)
        guard authStatus.configured else {
            throw AscendKitError.invalidState("ASC auth config is not ready: \(authStatus.findings.joined(separator: " "))")
        }

        let appID: String
        if let explicitAppID = value(after: "--app-id", in: args), !explicitAppID.isEmpty {
            appID = explicitAppID
        } else {
            guard let appsReport = try loadIfExists(ASCAppsLookupReport.self, path: workspace.paths.ascApps),
                  let observedAppID = appsReport.apps.first?.id else {
                throw AscendKitError.invalidState("ASC app ID is missing. Run asc apps lookup first or pass --app-id.")
            }
            appID = observedAppID
        }

        let privateKey = try ASCSecretResolver(fileManager: fileManager).resolve(authConfig.privateKey)
        let token = try ASCJWTSigner().token(config: authConfig, privateKeyPEM: privateKey)
        let responses: [ReviewSubmissionExecutionResponse]
        do {
            responses = try await ASCAPIClient().publishDataNotCollectedPrivacyAnswers(appID: appID, token: token)
        } catch AscendKitError.invalidState(let message) where message.contains("HTTP 401") || message.contains("NOT_AUTHORIZED") {
            responses = [
                ReviewSubmissionExecutionResponse(
                    id: "app-privacy.data-not-collected.skip-iris-unauthorized",
                    method: "SKIP",
                    path: "/iris/v1/apps/\(appID)/dataUsages",
                    statusCode: 401
                )
            ]
        }
        try store.appendAudit(
            .init(
                action: .reviewSubmissionPlanned,
                summary: responses.contains(where: { $0.statusCode == 401 })
                    ? "Skipped ASC app privacy publish because IRIS rejected API key auth"
                    : "Published ASC app privacy Data Not Collected answers",
                details: ["appID": appID, "responses": "\(responses.count)"]
            ),
            to: workspace
        )
        return try render(responses, json: json) {
            responses.contains(where: { $0.statusCode == 401 })
                ? "ASC app privacy could not be published with API key auth; use App Store Connect UI or Apple ID web session support."
                : "ASC app privacy Data Not Collected answers published with \(responses.count) response(s)."
        }
    }

    private func submit(_ args: [String], json: Bool) async throws -> String {
        guard args.first == "readiness" || args.first == "prepare" || args.first == "review-plan" || args.first == "handoff" || args.first == "execute" else {
            if args.first == "review-info", args.dropFirst().first == "init" {
                let workspace = try loadWorkspace(from: args)
                let store = ReleaseWorkspaceStore(fileManager: fileManager)
                let reviewInfo = ReviewInfo.template
                try store.save(reviewInfo, to: URL(fileURLWithPath: workspace.paths.reviewInfo))
                try store.appendAudit(.init(action: .reviewInfoInitialized, summary: "Initialized reviewer info template"), to: workspace)
                return try render(reviewInfo, json: json) {
                    "Reviewer info template written to \(workspace.paths.reviewInfo)"
                }
            }
            if args.first == "review-info", args.dropFirst().first == "set" {
                let workspace = try loadWorkspace(from: args)
                let store = ReleaseWorkspaceStore(fileManager: fileManager)
                guard let firstName = value(after: "--first-name", in: args),
                      let lastName = value(after: "--last-name", in: args),
                      let email = value(after: "--email", in: args),
                      let phone = value(after: "--phone", in: args) else {
                    throw AscendKitError.invalidArguments("Usage: ascendkit submit review-info set --workspace PATH --first-name NAME --last-name NAME --email EMAIL --phone PHONE [--notes TEXT] [--requires-login true|false]")
                }
                let requiresLogin = value(after: "--requires-login", in: args) == "true"
                let credentialReference = value(after: "--credential-ref", in: args).map {
                    SecretRef(provider: .environment, identifier: $0)
                }
                let reviewInfo = ReviewInfo(
                    contact: ReviewerContact(firstName: firstName, lastName: lastName, email: email, phone: phone),
                    access: ReviewerAccess(
                        requiresLogin: requiresLogin,
                        credentialReference: credentialReference,
                        instructions: value(after: "--access-instructions", in: args) ?? ""
                    ),
                    notes: value(after: "--notes", in: args) ?? ""
                )
                try store.save(reviewInfo, to: URL(fileURLWithPath: workspace.paths.reviewInfo))
                try store.appendAudit(.init(action: .reviewInfoInitialized, summary: "Updated reviewer info"), to: workspace)
                return try render(reviewInfo, json: json) {
                    "Reviewer info updated at \(workspace.paths.reviewInfo)"
                }
            }
            throw AscendKitError.invalidArguments("Usage: ascendkit submit readiness|prepare|review-plan|handoff|execute --workspace PATH OR ascendkit submit review-info init --workspace PATH")
        }
        let workspace = try loadWorkspace(from: args)
        let store = ReleaseWorkspaceStore(fileManager: fileManager)
        let context = try loadSubmissionContext(workspace: workspace)
        let report = SubmissionReadinessEvaluator().evaluate(
            manifest: context.manifest,
            doctorReport: context.doctorReport,
            reviewInfo: context.reviewInfo,
            metadataLintReports: context.metadataLintReports,
            screenshotImportManifest: context.screenshotImportManifest,
            screenshotCompositionManifest: context.screenshotCompositionManifest,
            ascLookupPlan: context.ascLookupPlan,
            buildCandidatesReport: context.buildCandidatesReport,
            iapValidationReport: context.iapValidationReport
        )
        try store.save(report, to: URL(fileURLWithPath: workspace.paths.readiness))
        try store.appendAudit(.init(action: .submissionReadinessChecked, summary: "Checked submission readiness"), to: workspace)

        if args.first == "prepare" {
            let preparation = SubmissionPreparationBuilder().build(
                manifest: context.manifest,
                readiness: report,
                metadataLintReports: context.metadataLintReports,
                screenshotImportManifest: context.screenshotImportManifest,
                screenshotCompositionManifest: context.screenshotCompositionManifest,
                ascLookupPlan: context.ascLookupPlan,
                buildCandidatesReport: context.buildCandidatesReport,
                iapValidationReport: context.iapValidationReport,
                reviewInfo: context.reviewInfo
            )
            try store.save(preparation, to: URL(fileURLWithPath: workspace.paths.reviewChecklist))
            try store.appendAudit(.init(action: .submissionPreparationSaved, summary: "Saved submission preparation checklist"), to: workspace)
            return try render(preparation, json: json) {
                "Submission preparation saved: \(preparation.ready ? "ready" : "not ready")"
            }
        }

        if args.first == "review-plan" {
            let plan = try buildReviewSubmissionPlan(workspace: workspace, context: context, readiness: report)
            try store.save(plan, to: URL(fileURLWithPath: workspace.paths.reviewSubmissionPlan))
            try store.appendAudit(.init(action: .reviewSubmissionPlanned, summary: "Planned review submission handoff"), to: workspace)
            return try render(plan, json: json) {
                "Review submission plan saved; remote submission execution remains disabled."
            }
        }

        if args.first == "handoff" {
            let plan = try buildReviewSubmissionPlan(workspace: workspace, context: context, readiness: report)
            try store.save(plan, to: URL(fileURLWithPath: workspace.paths.reviewSubmissionPlan))
            let markdown = ReviewHandoffMarkdown().render(plan: plan)
            let url = URL(fileURLWithPath: workspace.paths.reviewHandoffMarkdown)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            try store.appendAudit(.init(action: .reviewHandoffWritten, summary: "Wrote review handoff markdown"), to: workspace)
            return try render(plan, json: json) {
                "Review handoff written to \(url.path); remote submission execution remains disabled."
            }
        }

        if args.first == "execute" {
            let plan = try buildReviewSubmissionPlan(workspace: workspace, context: context, readiness: report)
            guard args.contains("--confirm-remote-submission") else {
                let result = ReviewSubmissionExecutionResult(
                    executed: false,
                    appStoreVersionID: try loadIfExists(MetadataObservedState.self, path: workspace.paths.ascObservedState)?.appStoreVersionID,
                    buildID: plan.selectedBuildID,
                    findings: ["Missing --confirm-remote-submission. No remote review submission request was executed."]
                )
                try store.save(result, to: URL(fileURLWithPath: workspace.paths.reviewSubmissionResult))
                return try render(result, json: json) {
                    "Review submission execution was not run: pass --confirm-remote-submission to execute remote mutation."
                }
            }
            guard plan.readyForManualReviewSubmission else {
                throw AscendKitError.invalidState("Review submission plan is not ready: \(plan.findings.joined(separator: " "))")
            }
            guard let reviewInfo = context.reviewInfo else {
                throw AscendKitError.invalidState("Reviewer info is missing.")
            }
            guard let authConfig = try loadIfExists(ASCAuthConfig.self, path: workspace.paths.ascAuthConfig) else {
                throw AscendKitError.invalidState("ASC auth config is missing. Run asc auth init first.")
            }
            let authStatus = ASCAuthStatus(config: authConfig)
            guard authStatus.configured else {
                throw AscendKitError.invalidState("ASC auth config is not ready: \(authStatus.findings.joined(separator: " "))")
            }
            guard let observed = try loadIfExists(MetadataObservedState.self, path: workspace.paths.ascObservedState),
                  let appStoreVersionID = observed.appStoreVersionID else {
                throw AscendKitError.invalidState("ASC observed appStoreVersionID is missing. Run asc metadata observe first.")
            }
            guard let appID = plan.appID else {
                throw AscendKitError.invalidState("ASC app ID is missing. Run asc apps lookup first.")
            }
            guard let buildID = plan.selectedBuildID else {
                throw AscendKitError.invalidState("Selected ASC build ID is missing. Run asc builds observe first.")
            }
            let platform = context.manifest.targets.first(where: \.isAppStoreApplication)?.platform ?? .iOS
            let privateKey = try ASCSecretResolver(fileManager: fileManager).resolve(authConfig.privateKey)
            let token = try ASCJWTSigner().token(config: authConfig, privateKeyPEM: privateKey)
            let result = try await ASCAPIClient().executeReviewSubmission(
                appID: appID,
                appInfoID: observed.appInfoID,
                appStoreVersionID: appStoreVersionID,
                buildID: buildID,
                platform: platform,
                reviewInfo: reviewInfo,
                token: token
            )
            try store.save(result, to: URL(fileURLWithPath: workspace.paths.reviewSubmissionResult))
            try store.appendAudit(
                .init(
                    action: .reviewSubmissionExecuted,
                    summary: "Executed remote review submission",
                    details: ["submitted": "\(result.submitted)"]
                ),
                to: workspace
            )
            return try render(result, json: json) {
                result.submitted
                    ? "Review submission executed and submitted."
                    : "Review submission execution finished but submission is not marked submitted."
            }
        }

        return try render(report, json: json) {
            "Submission readiness: \(report.ready ? "ready" : "not ready")"
        }
    }

    private func buildReviewSubmissionPlan(
        workspace: ReleaseWorkspace,
        context: SubmissionContext,
        readiness: SubmissionReadinessReport
    ) throws -> ReviewSubmissionPlan {
        let appsLookup = try loadIfExists(ASCAppsLookupReport.self, path: workspace.paths.ascApps)
        let metadataApply = try loadIfExists(ASCMetadataApplyResult.self, path: workspace.paths.ascMetadataApplyResult)
        let metadataDiff = try loadIfExists(MetadataDiffReport.self, path: workspace.paths.ascDiff)
        return ReviewSubmissionPlanBuilder().build(
            manifest: context.manifest,
            reviewInfo: context.reviewInfo,
            readiness: readiness,
            screenshotCompositionManifest: context.screenshotCompositionManifest,
            appsLookupReport: appsLookup,
            metadataApplyResult: metadataApply,
            metadataDiffReport: metadataDiff,
            buildCandidatesReport: context.buildCandidatesReport
        )
    }

    private struct SubmissionContext {
        var manifest: ReleaseManifest
        var doctorReport: DoctorReport?
        var reviewInfo: ReviewInfo?
        var metadataLintReports: [MetadataLintReport]
        var screenshotImportManifest: ScreenshotImportManifest?
        var screenshotCompositionManifest: ScreenshotCompositionManifest?
        var ascLookupPlan: ASCLookupPlan?
        var buildCandidatesReport: BuildCandidatesReport?
        var iapValidationReport: IAPValidationReport?
    }

    private func loadSubmissionContext(workspace: ReleaseWorkspace) throws -> SubmissionContext {
        let store = ReleaseWorkspaceStore(fileManager: fileManager)
        let manifest = try store.loadManifest(from: workspace)
        let doctorReport = try loadIfExists(DoctorReport.self, path: workspace.paths.doctorReport)
        let reviewInfo = try loadIfExists(ReviewInfo.self, path: workspace.paths.reviewInfo)
        let metadataLintReports = try loadMetadataLintReports(workspace: workspace)
        let screenshotImportManifest = try loadIfExists(ScreenshotImportManifest.self, path: workspace.paths.screenshotImportManifest)
        let screenshotCompositionManifest = try loadIfExists(ScreenshotCompositionManifest.self, path: workspace.paths.screenshotCompositionManifest)
        let ascLookupPlan = try loadIfExists(ASCLookupPlan.self, path: workspace.paths.ascLookupPlan)
        let buildCandidatesReport = try loadIfExists(BuildCandidatesReport.self, path: workspace.paths.buildCandidates)
        let iapValidationReport = try loadIfExists(IAPValidationReport.self, path: workspace.paths.iapValidation)
        return SubmissionContext(
            manifest: manifest,
            doctorReport: doctorReport,
            reviewInfo: reviewInfo,
            metadataLintReports: metadataLintReports,
            screenshotImportManifest: screenshotImportManifest,
            screenshotCompositionManifest: screenshotCompositionManifest,
            ascLookupPlan: ascLookupPlan,
            buildCandidatesReport: buildCandidatesReport,
            iapValidationReport: iapValidationReport
        )
    }

    private func iap(_ args: [String], json: Bool) throws -> String {
        guard let subcommand = args.first else {
            throw AscendKitError.invalidArguments("Usage: ascendkit iap template init --workspace PATH OR ascendkit iap validate --workspace PATH")
        }
        let workspace = try loadWorkspace(from: args)
        let store = ReleaseWorkspaceStore(fileManager: fileManager)
        switch subcommand {
        case "template":
            guard args.dropFirst().first == "init" else {
                throw AscendKitError.invalidArguments("Usage: ascendkit iap template init --workspace PATH")
            }
            let manifest = try store.loadManifest(from: workspace)
            let bundleID = manifest.targets.first(where: \.isReleaseApplication)?.bundleIdentifier ?? "com.example.app"
            let templates = SubscriptionTemplateFactory.starter(appBundleID: bundleID)
            try store.save(templates, to: URL(fileURLWithPath: workspace.paths.iapSubscriptions))
            try store.appendAudit(.init(action: .iapTemplateInitialized, summary: "Initialized local IAP subscription templates"), to: workspace)
            return try render(templates, json: json) { "IAP subscription templates written locally; no ASC mutation was made." }
        case "validate":
            let templates = try loadIfExists([SubscriptionTemplate].self, path: workspace.paths.iapSubscriptions) ?? []
            let report = IAPValidationReport(templates: templates)
            try store.save(report, to: URL(fileURLWithPath: workspace.paths.iapValidation))
            try store.appendAudit(.init(action: .iapValidated, summary: "Validated local IAP subscription templates"), to: workspace)
            return try render(report, json: json) { "IAP template validation: \(report.valid ? "valid" : "invalid")" }
        default:
            throw AscendKitError.invalidArguments("Unknown iap command: \(subcommand)")
        }
    }

    private func loadWorkspace(from args: [String]) throws -> ReleaseWorkspace {
        guard let path = value(after: "--workspace", in: args) else {
            throw AscendKitError.invalidArguments("Missing --workspace PATH")
        }
        return try ReleaseWorkspaceStore(fileManager: fileManager).loadWorkspace(root: URL(fileURLWithPath: path))
    }

    private func loadIfExists<T: Decodable>(_ type: T.Type, path: String) throws -> T? {
        guard fileManager.fileExists(atPath: path) else {
            return nil
        }
        return try AscendKitJSON.decoder.decode(T.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    private func metadataURL(locale: String, workspace: ReleaseWorkspace) -> URL {
        let root = URL(fileURLWithPath: workspace.paths.root).appendingPathComponent("metadata")
        let directory = locale == "en-US" ? root.appendingPathComponent("source") : root.appendingPathComponent("localized")
        return directory.appendingPathComponent("\(locale).json")
    }

    private func metadataLintURL(locale: String, workspace: ReleaseWorkspace) -> URL {
        URL(fileURLWithPath: workspace.paths.root)
            .appendingPathComponent("metadata/lint")
            .appendingPathComponent("\(locale).json")
    }

    private func loadMetadataLintReports(workspace: ReleaseWorkspace) throws -> [MetadataLintReport] {
        let lintDirectory = URL(fileURLWithPath: workspace.paths.root).appendingPathComponent("metadata/lint")
        guard let contents = try? fileManager.contentsOfDirectory(at: lintDirectory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        return try contents
            .filter { $0.pathExtension == "json" }
            .map { try AscendKitJSON.decoder.decode(MetadataLintReport.self, from: Data(contentsOf: $0)) }
    }

    private func loadLocalMetadata(workspace: ReleaseWorkspace) throws -> [AppMetadata] {
        let metadataRoot = URL(fileURLWithPath: workspace.paths.root).appendingPathComponent("metadata")
        let directories = [
            metadataRoot.appendingPathComponent("source"),
            metadataRoot.appendingPathComponent("localized")
        ]
        var metadata: [AppMetadata] = []
        for directory in directories {
            guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
                continue
            }
            for url in contents where url.pathExtension == "json" {
                metadata.append(try AscendKitJSON.decoder.decode(AppMetadata.self, from: Data(contentsOf: url)))
            }
        }
        return metadata.sorted { $0.locale < $1.locale }
    }

    private func upsert(candidate: BuildCandidate, into candidates: [BuildCandidate]) -> [BuildCandidate] {
        var result = candidates.filter { $0.id != candidate.id }
        result.append(candidate)
        return result.sorted { lhs, rhs in
            if lhs.version == rhs.version {
                return lhs.buildNumber < rhs.buildNumber
            }
            return lhs.version < rhs.version
        }
    }

    private func render<T: Encodable>(_ value: T, json: Bool, text: () -> String) throws -> String {
        if json {
            return try AscendKitJSON.encodeString(value)
        }
        return text()
    }

    private func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
            return nil
        }
        return args[index + 1]
    }

    private func list(after flag: String, in args: [String], default defaultValue: [String] = []) -> [String] {
        guard let value = value(after: flag, in: args), !value.isEmpty else {
            return defaultValue
        }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func platformList(after flag: String, in args: [String], default defaultValue: [ApplePlatform]) -> [ApplePlatform] {
        let values = list(after: flag, in: args)
        guard !values.isEmpty else {
            return defaultValue
        }
        return values.map { value in
            ApplePlatform(rawValue: value) ?? .unknown
        }
        .filter { $0 != .unknown }
    }

    private func secretProvider(from value: String) -> SecretProvider? {
        if value == "env" {
            return .environment
        }
        return SecretProvider(rawValue: value)
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    static let help = """
    AscendKit

    Usage:
      ascendkit workspace status --workspace PATH [--json]
      ascendkit workspace audit --workspace PATH [--json]
      ascendkit workspace list [--root PATH] [--json]
      ascendkit intake inspect [--root PATH] [--project PATH] [--workspace PATH] [--release-id ID] [--save] [--json]
      ascendkit doctor release --workspace PATH [--json]
      ascendkit metadata init --workspace PATH [--locale en-US] [--json]
      ascendkit metadata import-fastlane --workspace PATH --source PATH [--json]
      ascendkit metadata status --workspace PATH [--json]
      ascendkit metadata lint --workspace PATH [--locale en-US] [--json]
      ascendkit metadata diff --workspace PATH [--json]
      ascendkit screenshots plan --workspace PATH [--screens A,B] [--features A,B] [--platforms iOS,macOS] [--locales en-US] [--json]
      ascendkit screenshots readiness --workspace PATH [--source PATH] [--json]
      ascendkit screenshots import --workspace PATH --source PATH [--json]
      ascendkit screenshots import-fastlane --workspace PATH --source PATH [--locales en-US,zh-Hans] [--json]
      ascendkit screenshots compose --workspace PATH [--mode storeReadyCopy|poster|deviceFrame] [--json]
      ascendkit screenshots upload-plan --workspace PATH [--display-type APP_IPHONE_67] [--replace-existing] [--json]
      ascendkit screenshots upload --workspace PATH [--replace-existing] --confirm-remote-mutation [--json]
      ascendkit asc auth save-profile --name NAME --issuer-id ID --key-id ID --private-key-provider env|file|keychain --private-key-ref REF [--json]
      ascendkit asc auth profiles [--json]
      ascendkit asc auth init --workspace PATH --issuer-id ID --key-id ID --private-key-provider env|file|keychain --private-key-ref REF [--json]
      ascendkit asc auth init --workspace PATH --profile NAME [--json]
      ascendkit asc auth check --workspace PATH [--json]
      ascendkit asc lookup plan --workspace PATH [--json]
      ascendkit asc lookup apps --workspace PATH [--json]
      ascendkit asc apps lookup --workspace PATH [--json]
      ascendkit asc builds observe --workspace PATH [--json]
      ascendkit asc builds list [--workspace PATH] [--json]
      ascendkit asc builds import --workspace PATH --id ID --version VERSION --build BUILD [--state STATE] [--json]
      ascendkit asc metadata import --workspace PATH --file PATH [--json]
      ascendkit asc metadata observe --workspace PATH [--json]
      ascendkit asc metadata plan --workspace PATH [--json]
      ascendkit asc metadata requests --workspace PATH [--json]
      ascendkit asc metadata apply --workspace PATH --confirm-remote-mutation [--json]
      ascendkit asc pricing set-free --workspace PATH [--app-id ID] [--base-territory USA] [--confirm-remote-mutation] [--json]
      ascendkit asc privacy set-not-collected --workspace PATH [--app-id ID] --confirm-remote-mutation [--json]
      ascendkit submit readiness --workspace PATH [--json]
      ascendkit submit prepare --workspace PATH [--json]
      ascendkit submit review-plan --workspace PATH [--json]
      ascendkit submit handoff --workspace PATH [--json]
      ascendkit submit execute --workspace PATH --confirm-remote-submission [--json]
      ascendkit submit review-info init --workspace PATH [--json]
      ascendkit submit review-info set --workspace PATH --first-name NAME --last-name NAME --email EMAIL --phone PHONE [--notes TEXT] [--requires-login true|false] [--credential-ref ENV_VAR] [--access-instructions TEXT] [--json]
      ascendkit iap template init --workspace PATH [--json]
      ascendkit iap validate --workspace PATH [--json]
    """
}
