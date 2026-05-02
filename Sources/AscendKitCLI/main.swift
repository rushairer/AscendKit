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
        if arguments == ["--version"] || arguments == ["-v"] {
            return "ascendkit \(AscendKitVersion.current)"
        }

        if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") {
            return Self.help
        }

        let json = arguments.contains("--json")
        let args = arguments.filter { $0 != "--json" }
        guard let group = args.first else { return Self.help }
        let tail = Array(args.dropFirst())

        switch group {
        case "version":
            return try version(json: json)
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

    private func version(json: Bool) throws -> String {
        let report = AscendKitVersionReport()
        return try render(report, json: json) {
            [
                "ascendkit \(report.version)",
                "Platform: \(report.platform) \(report.architecture)",
                "Release: \(report.releaseURL)",
                "Install: \(report.installCommand)",
                "Verify installed CLI: \(report.verifyCommand)"
            ].joined(separator: "\n")
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
        case "summary":
            let workspace = try loadWorkspace(from: args)
            let summary = ReleaseWorkspaceSummaryReader(fileManager: fileManager).read(workspace: workspace)
            return try render(summary, json: json) {
                renderReleaseWorkspaceSummaryText(summary)
            }
        case "hygiene":
            let workspace = try loadWorkspace(from: args)
            let report = WorkspaceHygieneScanner(fileManager: fileManager).scan(workspace: workspace)
            return try render(report, json: json) {
                renderWorkspaceHygieneText(report)
            }
        case "gitignore":
            let workspace = try loadWorkspace(from: args)
            let report = try WorkspaceGitignoreGuard(fileManager: fileManager).check(
                workspace: workspace,
                fix: args.contains("--fix")
            )
            return try render(report, json: json) {
                renderWorkspaceGitignoreText(report)
            }
        case "export-summary":
            let workspace = try loadWorkspace(from: args)
            guard let outputPath = value(after: "--output", in: args) else {
                throw AscendKitError.invalidArguments("Usage: ascendkit workspace export-summary --workspace PATH --output FILE [--json]")
            }
            let report = try SanitizedWorkspaceSummaryExporter(fileManager: fileManager).export(
                workspace: workspace,
                outputURL: URL(fileURLWithPath: outputPath)
            )
            return try render(report, json: json) {
                renderSanitizedWorkspaceSummaryExportText(report)
            }
        case "validate-handoff":
            let workspace = try loadWorkspace(from: args)
            let exportURL = value(after: "--export", in: args).map { URL(fileURLWithPath: $0) }
            let report = try HandoffValidator(fileManager: fileManager).validate(
                workspace: workspace,
                exportURL: exportURL
            )
            return try render(report, json: json) {
                renderHandoffValidationText(report)
            }
        case "next-steps":
            let workspace = try loadWorkspace(from: args)
            let plan = WorkspaceNextStepsPlanner(fileManager: fileManager).plan(workspace: workspace)
            return try render(plan, json: json) {
                renderWorkspaceNextStepsText(plan)
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
            throw AscendKitError.invalidArguments("Usage: ascendkit workspace status|summary|hygiene|gitignore|export-summary|validate-handoff|next-steps|audit --workspace PATH [--json] OR ascendkit workspace list [--root PATH] [--json]")
        }
    }

    private func renderReleaseWorkspaceSummaryText(_ summary: ReleaseWorkspaceSummary) -> String {
        var lines = [
            "Release workspace summary: \(summary.releaseID)",
            "Submission readiness: \(summary.submissionReadinessReady.map { $0 ? "ready" : "not ready" } ?? "unknown")",
            "Manual review submission: \(summary.readyForManualReviewSubmission.map { $0 ? "ready" : "not ready" } ?? "unknown")",
            "Remote submission execution allowed: \(summary.remoteSubmissionExecutionAllowed.map { $0 ? "yes" : "no" } ?? "unknown")",
            "App Privacy: \(summary.appPrivacyState ?? "unknown") (\(summary.appPrivacyReadyForSubmission.map { $0 ? "ready" : "not ready" } ?? "unknown"))",
            "Screenshot workflow upload-plan readiness: \(summary.screenshotWorkflowReadyForUploadPlan.map { $0 ? "ready" : "not ready" } ?? "unknown")"
        ]
        if summary.nextActions.isEmpty {
            lines.append("Next action(s): none")
        } else {
            lines.append("Next action(s):")
            lines.append(contentsOf: summary.nextActions.map {
                "- [\($0.severity.rawValue)] \($0.title): \($0.detail)"
            })
        }
        return lines.joined(separator: "\n")
    }

    private func renderWorkspaceHygieneText(_ report: WorkspaceHygieneReport) -> String {
        var lines = [
            "Workspace hygiene: \(report.safeForPublicCommit ? "safe" : "not safe") for public commit",
            "Findings: \(report.findings.count)"
        ]
        if !report.findings.isEmpty {
            lines.append("Finding(s):")
            lines.append(contentsOf: report.findings.map {
                "- [\($0.severity.rawValue)] \($0.path): \($0.reason)"
            })
        }
        if !report.nextActions.isEmpty {
            lines.append("Next action(s):")
            lines.append(contentsOf: report.nextActions.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    private func renderWorkspaceGitignoreText(_ report: WorkspaceGitignoreReport) -> String {
        var lines = [
            "Workspace gitignore: \(report.hasAscendKitRule ? "protected" : "missing .ascendkit/ rule")",
            "Changed: \(report.changed ? "yes" : "no")",
            "Project root: \(report.projectRoot ?? "unknown")",
            "Gitignore: \(report.gitignorePath ?? "unknown")"
        ]
        if !report.nextActions.isEmpty {
            lines.append("Next action(s):")
            lines.append(contentsOf: report.nextActions.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    private func renderSanitizedWorkspaceSummaryExportText(_ report: SanitizedWorkspaceSummaryExport) -> String {
        [
            "Sanitized workspace summary exported: \(report.exportPath)",
            "AscendKit version: \(report.ascendKitVersion ?? "unknown")",
            "Release: \(report.releaseID)",
            "Next action(s): \(report.nextActions.count)",
            "Workspace step(s): \(report.steps.count)",
            "Hygiene finding(s): \(report.hygieneFindings.count)",
            "Raw workspace safe for public commit: \(report.hygieneSafeForPublicCommit ? "yes" : "no")"
        ].joined(separator: "\n")
    }

    private func renderHandoffValidationText(_ report: HandoffValidationReport) -> String {
        var lines = [
            "Agent handoff: \(report.readyForAgentHandoff ? "ready" : "blocked")",
            "AscendKit version: \(report.ascendKitVersion ?? "unknown")",
            "Release: \(report.releaseID)",
            "Release blocker(s): \(report.releaseBlockerCount)",
            "Release warning(s): \(report.releaseWarningCount)"
        ]
        if let path = report.sanitizedExportPath {
            lines.append("Sanitized export: \(path)")
        }
        lines.append("Validation item(s):")
        lines.append(contentsOf: report.items.map { item in
            let next = item.nextAction.map { " Next: \($0)" } ?? ""
            return "- [\(item.severity.rawValue)] \(item.title): \(item.detail)\(next)"
        })
        return lines.joined(separator: "\n")
    }

    private func renderWorkspaceNextStepsText(_ plan: WorkspaceNextStepsPlan) -> String {
        var lines = [
            "Workspace next steps: \(plan.releaseID)",
            "AscendKit version: \(plan.ascendKitVersion ?? "unknown")",
            "Blocker(s): \(plan.blockerCount)",
            "Warning(s): \(plan.warningCount)"
        ]
        if plan.steps.isEmpty {
            lines.append("Next step(s): none")
        } else {
            lines.append("Next step(s):")
            lines.append(contentsOf: plan.steps.map { step in
                let command = step.command.map { " Command: \($0)" } ?? ""
                return "- [\(step.severity.rawValue)] \(step.title): \(step.detail)\(command)"
            })
        }
        return lines.joined(separator: "\n")
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
            throw AscendKitError.invalidArguments("Usage: ascendkit metadata init|import-fastlane|status|lint|diff --workspace PATH")
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
            throw AscendKitError.invalidArguments("metadata sync has been replaced by asc metadata plan and asc metadata apply --confirm-remote-mutation.")
        default:
            throw AscendKitError.invalidArguments("Unknown metadata command: \(subcommand)")
        }
    }

    private func screenshots(_ args: [String], json: Bool) async throws -> String {
        guard let subcommand = args.first else {
            throw AscendKitError.invalidArguments("Usage: ascendkit screenshots destinations|plan|copy|capture-plan|capture|workflow|readiness|compose|coverage|upload-plan|upload|upload-status --workspace PATH")
        }
        let workspace = try loadWorkspace(from: args)
        let store = ReleaseWorkspaceStore(fileManager: fileManager)
        let planURL = URL(fileURLWithPath: workspace.paths.screenshotPlan)

        switch subcommand {
        case "destinations":
            let manifest = try store.loadManifest(from: workspace)
            let screenshotPlan = try loadIfExists(ScreenshotPlan.self, path: workspace.paths.screenshotPlan)
            let platforms = screenshotPlan?.platforms ?? Array(Set(manifest.targets.map(\.platform).filter { $0 == .iOS || $0 == .iPadOS }))
            let report = try discoverScreenshotDestinations(platforms: platforms)
            return try render(report, json: json) {
                if report.recommendedDestinations.isEmpty {
                    return "No recommended screenshot destinations found: \(report.findings.joined(separator: " "))"
                }
                return report.recommendedDestinations.map {
                    "\($0.platform.rawValue): \($0.xcodebuildDestination)"
                }.joined(separator: "\n")
            }
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
            return try render(result, json: json) { renderScreenshotReadinessText(result) }
        case "copy":
            switch args.dropFirst().first {
            case "init":
                guard fileManager.fileExists(atPath: planURL.path) else {
                    throw AscendKitError.fileNotFound(planURL.path)
                }
                let plan = try AscendKitJSON.decoder.decode(ScreenshotPlan.self, from: Data(contentsOf: planURL))
                let locale = value(after: "--locale", in: args) ?? plan.locales.first ?? "en-US"
                let copy = ScreenshotCompositionCopyTemplateBuilder().build(plan: plan, locale: locale)
                let outputURL = URL(fileURLWithPath: value(after: "--output", in: args) ?? defaultScreenshotCopyPath(workspace: workspace, locale: locale))
                try store.save(copy, to: outputURL)
                try store.appendAudit(
                    .init(
                        action: .screenshotCopyInitialized,
                        summary: "Initialized screenshot composition copy",
                        details: ["items": "\(copy.items.count)", "path": outputURL.path]
                    ),
                    to: workspace
                )
                return try render(copy, json: json) {
                    "Screenshot copy template written to \(outputURL.path) with \(copy.items.count) item(s)."
                }
            case "refresh":
                guard fileManager.fileExists(atPath: planURL.path) else {
                    throw AscendKitError.fileNotFound(planURL.path)
                }
                let plan = try AscendKitJSON.decoder.decode(ScreenshotPlan.self, from: Data(contentsOf: planURL))
                let locale = value(after: "--locale", in: args) ?? plan.locales.first ?? "en-US"
                let copyPath = value(after: "--copy", in: args) ?? defaultScreenshotCopyPath(workspace: workspace, locale: locale)
                let outputURL = URL(fileURLWithPath: value(after: "--output", in: args) ?? copyPath)
                let existing = try loadIfExists(ScreenshotCompositionCopyManifest.self, path: copyPath)
                let copy = ScreenshotCompositionCopyTemplateBuilder().refresh(
                    plan: plan,
                    existing: existing,
                    locale: locale
                )
                try store.save(copy, to: outputURL)
                try store.appendAudit(
                    .init(
                        action: .screenshotCopyRefreshed,
                        summary: "Refreshed screenshot composition copy",
                        details: ["items": "\(copy.items.count)", "path": outputURL.path]
                    ),
                    to: workspace
                )
                return try render(copy, json: json) {
                    "Screenshot copy template refreshed at \(outputURL.path) with \(copy.items.count) item(s)."
                }
            case "lint":
                guard let importManifest = try loadIfExists(ScreenshotImportManifest.self, path: workspace.paths.screenshotImportManifest) else {
                    throw AscendKitError.fileNotFound(workspace.paths.screenshotImportManifest)
                }
                let locale = value(after: "--locale", in: args) ?? importManifest.artifacts.first?.locale ?? "en-US"
                let copyPath = value(after: "--copy", in: args) ?? defaultScreenshotCopyPath(workspace: workspace, locale: locale)
                guard let copyManifest = try loadScreenshotCompositionCopy(from: copyPath) else {
                    throw AscendKitError.fileNotFound(copyPath)
                }
                let report = ScreenshotCompositionCopyLinter().lint(
                    importManifest: importManifest,
                    copyManifest: copyManifest
                )
                try store.save(report, to: URL(fileURLWithPath: workspace.paths.screenshotCopyLint))
                try store.appendAudit(
                    .init(
                        action: .screenshotCopyLinted,
                        summary: "Linted screenshot composition copy",
                        details: ["findings": "\(report.findings.count)", "path": copyPath]
                    ),
                    to: workspace
                )
                return try render(report, json: json) {
                    renderScreenshotCopyLintText(report)
                }
            default:
                throw AscendKitError.invalidArguments("Usage: ascendkit screenshots copy init|refresh|lint --workspace PATH [--locale en-US] [--copy PATH] [--output PATH] [--json]")
            }
        case "capture-plan":
            guard fileManager.fileExists(atPath: planURL.path) else {
                throw AscendKitError.fileNotFound(planURL.path)
            }
            let manifest = try store.loadManifest(from: workspace)
            let plan = try AscendKitJSON.decoder.decode(ScreenshotPlan.self, from: Data(contentsOf: planURL))
            let destinationOverrides = repeatedValues(after: "--destination", in: args)
            let capturePlan = ScreenshotCapturePlanBuilder().build(
                manifest: manifest,
                screenshotPlan: plan,
                workspaceRoot: URL(fileURLWithPath: workspace.paths.root),
                scheme: value(after: "--scheme", in: args),
                configuration: value(after: "--configuration", in: args) ?? "Debug",
                destinationOverrides: destinationOverrides,
                discoveredDestinations: destinationOverrides.isEmpty
                    ? try discoverScreenshotDestinations(platforms: plan.platforms).recommendedDestinations
                    : []
            )
            try store.save(capturePlan, to: URL(fileURLWithPath: workspace.paths.screenshotCapturePlan))
            try store.appendAudit(
                .init(
                    action: .screenshotCapturePlanned,
                    summary: "Planned local screenshot capture",
                    details: ["commands": "\(capturePlan.commands.count)"]
                ),
                to: workspace
            )
            return try render(capturePlan, json: json) {
                "Screenshot capture plan saved with \(capturePlan.commands.count) xcodebuild command(s) and \(capturePlan.findings.count) finding(s)."
            }
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
            let mode = ScreenshotCompositionMode(rawValue: value(after: "--mode", in: args) ?? "storeReadyCopy") ?? .storeReadyCopy
            let manifest = try composeScreenshots(
                workspace: workspace,
                store: store,
                mode: mode,
                copyPath: value(after: "--copy", in: args)
            )
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
                renderScreenshotUploadPlanText(plan)
            }
        case "coverage":
            let report = ScreenshotCoverageBuilder().build(
                plan: try loadIfExists(ScreenshotPlan.self, path: workspace.paths.screenshotPlan),
                importManifest: try loadIfExists(ScreenshotImportManifest.self, path: workspace.paths.screenshotImportManifest),
                compositionManifest: try loadIfExists(ScreenshotCompositionManifest.self, path: workspace.paths.screenshotCompositionManifest),
                uploadPlan: try loadIfExists(ScreenshotUploadPlan.self, path: workspace.paths.screenshotUploadPlan)
            )
            return try render(report, json: json) {
                renderScreenshotCoverageText(report)
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
        case "upload-status":
            let status = ScreenshotUploadStatusBuilder().build(
                plan: try loadIfExists(ScreenshotUploadPlan.self, path: workspace.paths.screenshotUploadPlan),
                result: try loadIfExists(ScreenshotUploadExecutionResult.self, path: workspace.paths.screenshotUploadResult)
            )
            return try render(status, json: json) {
                renderScreenshotUploadStatusText(status)
            }
        case "capture":
            let result = try executeScreenshotCapture(workspace: workspace, store: store)
            return try render(result, json: json) {
                result.succeeded
                    ? "Screenshot capture completed with \(result.succeededCount) successful command(s)."
                    : "Screenshot capture finished with \(result.failedCount) failed command(s): \(result.findings.joined(separator: " "))"
            }
        case "workflow":
            switch args.dropFirst().first {
            case "run":
                let result = try runScreenshotWorkflow(workspace: workspace, store: store, args: args)
                return try render(result, json: json) {
                    result.succeeded
                        ? "Screenshot workflow completed with \(result.capturedFileCount) captured file(s) and \(result.composedArtifactCount) composed artifact(s)."
                        : "Screenshot workflow failed: \(result.findings.joined(separator: " "))"
                }
            case "status":
                let status = try screenshotWorkflowStatus(workspace: workspace)
                return try render(status, json: json) {
                    renderScreenshotWorkflowStatusText(status)
                }
            default:
                throw AscendKitError.invalidArguments("Usage: ascendkit screenshots workflow run|status --workspace PATH [--scheme SCHEME] [--configuration Debug] [--destination DESTINATION] [--mode storeReadyCopy|poster|deviceFrame|framedPoster] [--copy PATH] [--json]")
            }
        default:
            throw AscendKitError.invalidArguments("Unknown screenshots command: \(subcommand)")
        }
    }

    private func screenshotWorkflowStatus(workspace: ReleaseWorkspace) throws -> ScreenshotWorkflowStatusReport {
        try ScreenshotWorkflowStatusBuilder().build(
            capturePlan: loadIfExists(ScreenshotCapturePlan.self, path: workspace.paths.screenshotCapturePlan),
            captureResult: loadIfExists(ScreenshotCaptureExecutionResult.self, path: workspace.paths.screenshotCaptureResult),
            importManifest: loadIfExists(ScreenshotImportManifest.self, path: workspace.paths.screenshotImportManifest),
            copyLintReport: loadIfExists(ScreenshotCompositionCopyLintReport.self, path: workspace.paths.screenshotCopyLint),
            compositionManifest: loadIfExists(ScreenshotCompositionManifest.self, path: workspace.paths.screenshotCompositionManifest),
            workflowResult: loadIfExists(ScreenshotLocalWorkflowResult.self, path: workspace.paths.screenshotWorkflowResult),
            uploadPlan: loadIfExists(ScreenshotUploadPlan.self, path: workspace.paths.screenshotUploadPlan),
            paths: workspace.paths
        )
    }

    private func renderScreenshotWorkflowStatusText(_ status: ScreenshotWorkflowStatusReport) -> String {
        let header = status.readyForUploadPlan
            ? "Screenshot workflow ready for upload-plan."
            : "Screenshot workflow is not ready for upload-plan."
        let stepLines = status.steps.map { "\($0.id): \($0.state.rawValue)\($0.detail.map { " (\($0))" } ?? "")" }
        guard !status.findings.isEmpty else {
            return ([header] + stepLines).joined(separator: "\n")
        }
        let findingLines = status.findings.map { "- \($0)" }
        return ([header] + stepLines + ["Workflow finding(s):"] + findingLines).joined(separator: "\n")
    }

    private func renderScreenshotUploadPlanText(_ plan: ScreenshotUploadPlan) -> String {
        let header = "Screenshot upload plan saved with \(plan.items.count) item(s) and \(plan.findings.count) finding(s); no ASC mutation was made."
        guard !plan.findings.isEmpty else {
            return header
        }
        let lines = plan.findings.map { "- \($0)" }
        return ([header, "Upload planning finding(s):"] + lines).joined(separator: "\n")
    }

    private func renderScreenshotCoverageText(_ report: ScreenshotCoverageReport) -> String {
        let header = "Screenshot coverage: \(report.complete ? "complete" : "incomplete")"
        let entries = report.entries.map {
            let displayType = $0.displayType.map { "/\($0)" } ?? ""
            return "- \($0.locale)/\($0.platform.rawValue)\(displayType): expected \($0.expectedCount.map(String.init) ?? "unknown"), imported \($0.importedCount), composed \($0.composedCount), upload-plan \($0.uploadPlanCount)"
        }
        guard !report.findings.isEmpty else {
            return ([header] + entries).joined(separator: "\n")
        }
        return ([header] + entries + ["Finding(s):"] + report.findings.map { "- \($0)" }).joined(separator: "\n")
    }

    private func renderScreenshotUploadStatusText(_ status: ScreenshotUploadStatusReport) -> String {
        var lines = [
            "Screenshot upload status: \(status.uploadedCount) uploaded, \(status.failedCount) failed, \(status.deletedCount) deleted",
            "Planned screenshots: \(status.plannedCount.map(String.init) ?? "unknown")",
            "Executed: \(status.executed.map { $0 ? "yes" : "no" } ?? "unknown")",
            "Ready for retry: \(status.readyForRetry ? "yes" : "no")"
        ]
        if !status.retryPlanItemIDs.isEmpty {
            lines.append("Retry plan item(s):")
            lines.append(contentsOf: status.retryPlanItemIDs.map { "- \($0)" })
        }
        if !status.findings.isEmpty {
            lines.append("Finding(s):")
            lines.append(contentsOf: status.findings.map { "- \($0)" })
        }
        if !status.nextActions.isEmpty {
            lines.append("Next action(s):")
            lines.append(contentsOf: status.nextActions.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    private func renderScreenshotReadinessText(_ result: ScreenshotReadinessResult) -> String {
        let header = "Screenshot readiness: \(result.ready ? "ready" : "not ready") with \(result.findings.count) finding(s)"
        guard !result.findings.isEmpty else {
            return header
        }
        let lines = result.findings.map { finding in
            "- \(finding.severity.rawValue) \(finding.id): \(finding.message) Next: \(finding.nextAction)"
        }
        return ([header, "Screenshot readiness finding(s):"] + lines).joined(separator: "\n")
    }

    private func renderScreenshotCopyLintText(_ report: ScreenshotCompositionCopyLintReport) -> String {
        let header = "Screenshot copy lint \(report.valid ? "passed" : "failed") with \(report.findings.count) finding(s)."
        guard !report.findings.isEmpty else {
            return header
        }
        let lines = report.findings.map { "- \($0)" }
        return ([header, "Screenshot copy lint finding(s):"] + lines).joined(separator: "\n")
    }

    private func defaultScreenshotCopyPath(workspace: ReleaseWorkspace, locale: String) -> String {
        URL(fileURLWithPath: workspace.paths.root)
            .appendingPathComponent("screenshots/copy")
            .appendingPathComponent("\(locale).json")
            .path
    }

    private func runScreenshotWorkflow(workspace: ReleaseWorkspace, store: ReleaseWorkspaceStore, args: [String]) throws -> ScreenshotLocalWorkflowResult {
        guard let screenshotPlan = try loadIfExists(ScreenshotPlan.self, path: workspace.paths.screenshotPlan) else {
            throw AscendKitError.fileNotFound(workspace.paths.screenshotPlan)
        }
        let manifest = try store.loadManifest(from: workspace)
        let capturePlan = ScreenshotCapturePlanBuilder().build(
            manifest: manifest,
            screenshotPlan: screenshotPlan,
            workspaceRoot: URL(fileURLWithPath: workspace.paths.root),
            scheme: value(after: "--scheme", in: args),
            configuration: value(after: "--configuration", in: args) ?? "Debug",
            destinationOverrides: repeatedValues(after: "--destination", in: args),
            discoveredDestinations: repeatedValues(after: "--destination", in: args).isEmpty
                ? try discoverScreenshotDestinations(platforms: screenshotPlan.platforms).recommendedDestinations
                : []
        )
        try store.save(capturePlan, to: URL(fileURLWithPath: workspace.paths.screenshotCapturePlan))
        try store.appendAudit(
            .init(
                action: .screenshotCapturePlanned,
                summary: "Planned local screenshot capture for workflow",
                details: ["commands": "\(capturePlan.commands.count)"]
            ),
            to: workspace
        )

        let captureResult = try executeScreenshotCapture(workspace: workspace, store: store)
        let capturedFileCount = captureResult.items.flatMap(\.outputFiles).count
        guard captureResult.succeeded else {
            let result = ScreenshotLocalWorkflowResult(
                succeeded: false,
                capturePlanPath: workspace.paths.screenshotCapturePlan,
                captureResultPath: workspace.paths.screenshotCaptureResult,
                capturedFileCount: capturedFileCount,
                findings: captureResult.findings
            )
            try store.save(result, to: URL(fileURLWithPath: workspace.paths.screenshotWorkflowResult))
            try store.appendAudit(.init(action: .screenshotWorkflowRan, summary: "Screenshot workflow failed during capture"), to: workspace)
            return result
        }

        let mode = ScreenshotCompositionMode(rawValue: value(after: "--mode", in: args) ?? "framedPoster") ?? .framedPoster
        let copyPath = value(after: "--copy", in: args)
        if let copyPath {
            let copyLint = try refreshAndLintScreenshotCopy(
                workspace: workspace,
                store: store,
                screenshotPlan: screenshotPlan,
                copyPath: copyPath
            )
            guard copyLint.valid else {
                let result = ScreenshotLocalWorkflowResult(
                    succeeded: false,
                    capturePlanPath: workspace.paths.screenshotCapturePlan,
                    captureResultPath: workspace.paths.screenshotCaptureResult,
                    importManifestPath: workspace.paths.screenshotImportManifest,
                    compositionMode: mode,
                    capturedFileCount: capturedFileCount,
                    findings: copyLint.findings
                )
                try store.save(result, to: URL(fileURLWithPath: workspace.paths.screenshotWorkflowResult))
                try store.appendAudit(.init(action: .screenshotWorkflowRan, summary: "Screenshot workflow failed during copy lint"), to: workspace)
                return result
            }
        }
        let composition = try composeScreenshots(
            workspace: workspace,
            store: store,
            mode: mode,
            copyPath: copyPath
        )
        let result = ScreenshotLocalWorkflowResult(
            succeeded: true,
            capturePlanPath: workspace.paths.screenshotCapturePlan,
            captureResultPath: workspace.paths.screenshotCaptureResult,
            importManifestPath: workspace.paths.screenshotImportManifest,
            compositionManifestPath: workspace.paths.screenshotCompositionManifest,
            compositionMode: mode,
            capturedFileCount: capturedFileCount,
            composedArtifactCount: composition.artifacts.count
        )
        try store.save(result, to: URL(fileURLWithPath: workspace.paths.screenshotWorkflowResult))
        try store.appendAudit(
            .init(
                action: .screenshotWorkflowRan,
                summary: "Completed local screenshot workflow",
                details: ["captured": "\(capturedFileCount)", "composed": "\(composition.artifacts.count)", "mode": mode.rawValue]
            ),
            to: workspace
        )
        return result
    }

    private func refreshAndLintScreenshotCopy(
        workspace: ReleaseWorkspace,
        store: ReleaseWorkspaceStore,
        screenshotPlan: ScreenshotPlan,
        copyPath: String
    ) throws -> ScreenshotCompositionCopyLintReport {
        let existing = try loadIfExists(ScreenshotCompositionCopyManifest.self, path: copyPath)
        let copy = ScreenshotCompositionCopyTemplateBuilder().refresh(
            plan: screenshotPlan,
            existing: existing,
            locale: screenshotPlan.locales.first
        )
        let copyURL = URL(fileURLWithPath: copyPath)
        try store.save(copy, to: copyURL)
        try store.appendAudit(
            .init(
                action: .screenshotCopyRefreshed,
                summary: "Refreshed screenshot composition copy for workflow",
                details: ["items": "\(copy.items.count)", "path": copyURL.path]
            ),
            to: workspace
        )

        guard let importManifest = try loadIfExists(ScreenshotImportManifest.self, path: workspace.paths.screenshotImportManifest) else {
            throw AscendKitError.fileNotFound(workspace.paths.screenshotImportManifest)
        }
        let report = ScreenshotCompositionCopyLinter().lint(
            importManifest: importManifest,
            copyManifest: copy
        )
        try store.save(report, to: URL(fileURLWithPath: workspace.paths.screenshotCopyLint))
        try store.appendAudit(
            .init(
                action: .screenshotCopyLinted,
                summary: "Linted screenshot composition copy for workflow",
                details: ["findings": "\(report.findings.count)", "path": copyURL.path]
            ),
            to: workspace
        )
        return report
    }

    private func composeScreenshots(
        workspace: ReleaseWorkspace,
        store: ReleaseWorkspaceStore,
        mode: ScreenshotCompositionMode,
        copyPath: String?
    ) throws -> ScreenshotCompositionManifest {
        guard let importManifest = try loadIfExists(ScreenshotImportManifest.self, path: workspace.paths.screenshotImportManifest) else {
            throw AscendKitError.fileNotFound(workspace.paths.screenshotImportManifest)
        }
        let copyManifest = try loadScreenshotCompositionCopy(from: copyPath)
        let outputRoot = URL(fileURLWithPath: workspace.paths.root).appendingPathComponent("screenshots/composed")
        let manifest = try ScreenshotComposer(fileManager: fileManager).compose(
            importManifest: importManifest,
            outputRoot: outputRoot,
            mode: mode,
            copyManifest: copyManifest
        )
        try store.save(manifest, to: URL(fileURLWithPath: workspace.paths.screenshotCompositionManifest))
        try store.appendAudit(.init(action: .screenshotCompositionManifestSaved, summary: "Saved screenshot composition manifest"), to: workspace)
        return manifest
    }

    private func discoverScreenshotDestinations(platforms: [ApplePlatform]) throws -> ScreenshotDestinationDiscoveryReport {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["xcrun", "simctl", "list", "devices", "available"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        var report = ScreenshotDestinationDiscoverer().discover(simctlOutput: output, requestedPlatforms: platforms)
        if process.terminationStatus != 0 {
            report.findings.append("simctl destination discovery failed with exit code \(process.terminationStatus): \(errorOutput)")
        }
        return report
    }

    private func executeScreenshotCapture(workspace: ReleaseWorkspace, store: ReleaseWorkspaceStore) throws -> ScreenshotCaptureExecutionResult {
        guard let plan = try loadIfExists(ScreenshotCapturePlan.self, path: workspace.paths.screenshotCapturePlan) else {
            throw AscendKitError.fileNotFound(workspace.paths.screenshotCapturePlan)
        }
        let result = try ScreenshotCaptureExecutor(fileManager: fileManager).execute(
            plan: plan,
            logsDirectory: URL(fileURLWithPath: workspace.paths.root).appendingPathComponent("screenshots/capture/logs")
        )
        try store.save(result, to: URL(fileURLWithPath: workspace.paths.screenshotCaptureResult))
        if result.succeeded,
           let screenshotPlan = try loadIfExists(ScreenshotPlan.self, path: workspace.paths.screenshotPlan),
           let firstCommand = plan.commands.first {
            let sourceRoot = URL(fileURLWithPath: firstCommand.rawOutputDirectory)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let manifest = ScreenshotImporter(fileManager: fileManager).makeManifest(
                plan: screenshotPlan,
                sourceDirectory: sourceRoot
            )
            try store.save(manifest, to: URL(fileURLWithPath: workspace.paths.screenshotImportManifest))
            try store.appendAudit(
                .init(
                    action: .screenshotImportManifestSaved,
                    summary: "Refreshed screenshot import manifest after capture",
                    details: ["artifacts": "\(manifest.artifacts.count)"]
                ),
                to: workspace
            )
        }
        try store.appendAudit(
            .init(
                action: .screenshotCaptureExecuted,
                summary: "Executed local screenshot capture",
                details: ["succeeded": "\(result.succeededCount)", "failed": "\(result.failedCount)"]
            ),
            to: workspace
        )
        return result
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
            throw AscendKitError.invalidArguments("Usage: ascendkit asc auth init|check OR ascendkit asc lookup plan|apps OR ascendkit asc apps lookup OR ascendkit asc builds list|import OR ascendkit asc metadata import OR ascendkit asc pricing set-free OR ascendkit asc privacy set-not-collected|status|confirm-manual")
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

    private func loadScreenshotCompositionCopy(from path: String?) throws -> ScreenshotCompositionCopyManifest? {
        guard let path else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: url.path) else {
            throw AscendKitError.fileNotFound(url.path)
        }
        return try AscendKitJSON.decoder.decode(ScreenshotCompositionCopyManifest.self, from: Data(contentsOf: url))
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
                throw AscendKitError.invalidArguments("Usage: ascendkit asc auth init --workspace PATH (--profile NAME | --issuer-id ID --key-id ID --private-key-provider env|file --private-key-ref REF) [--json]")
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
                throw AscendKitError.invalidArguments("Usage: ascendkit asc auth save-profile --name NAME --issuer-id ID --key-id ID --private-key-provider env|file --private-key-ref REF [--json]")
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
            throw AscendKitError.invalidArguments("Usage: ascendkit asc metadata import|observe|plan|requests|apply|status --workspace PATH [--file PATH] [--json]")
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
        case "status":
            let status = ASCMetadataStatusBuilder().build(
                applyResult: try loadIfExists(ASCMetadataApplyResult.self, path: workspace.paths.ascMetadataApplyResult),
                diffReport: try loadIfExists(MetadataDiffReport.self, path: workspace.paths.ascDiff)
            )
            return try render(status, json: json) {
                renderASCMetadataStatusText(status)
            }
        default:
            throw AscendKitError.invalidArguments("Usage: ascendkit asc metadata import|observe|plan|requests|apply|status --workspace PATH [--file PATH] [--json]")
        }
    }

    private func renderASCMetadataStatusText(_ status: ASCMetadataStatusReport) -> String {
        var lines = [
            "ASC metadata status: \(status.readyForReviewPlan ? "ready for review plan" : "not ready")",
            "Applied: \(status.applied.map { $0 ? "yes" : "no" } ?? "unknown")",
            "Apply responses: \(status.applyResponseCount.map(String.init) ?? "unknown")",
            "Diff fresh: \(status.diffFresh.map { $0 ? "yes" : "no" } ?? "unknown")",
            "Remaining diffs: \(status.remainingDiffCount.map(String.init) ?? "unknown")",
            "Blocking diffs: \(status.blockingDiffCount.map(String.init) ?? "unknown")",
            "Release notes only diff: \(status.releaseNotesOnlyDiff ? "yes" : "no")"
        ]
        if !status.findings.isEmpty {
            lines.append("Finding(s):")
            lines.append(contentsOf: status.findings.map { "- \($0)" })
        }
        if !status.nextActions.isEmpty {
            lines.append("Next action(s):")
            lines.append(contentsOf: status.nextActions.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
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
        let workspace = try loadWorkspace(from: args)
        let store = ReleaseWorkspaceStore(fileManager: fileManager)
        switch args.dropFirst().first {
        case "status":
            let status = try loadIfExists(AppPrivacyStatus.self, path: workspace.paths.ascPrivacyStatus)
                ?? AppPrivacyStatus(
                    state: .unknown,
                    source: "workspace",
                    findings: ["No App Privacy status has been recorded."]
            )
            return try render(status, json: json) {
                renderAppPrivacyStatusText(status)
            }
        case "confirm-manual":
            guard args.contains("--data-not-collected") else {
                throw AscendKitError.invalidArguments("Usage: ascendkit asc privacy confirm-manual --workspace PATH --data-not-collected [--json]")
            }
            let status = AppPrivacyStatus(
                state: .publishedDataNotCollected,
                source: "manual-app-store-connect",
                findings: ["User confirmed App Store Connect App Privacy is published as Data Not Collected."]
            )
            try store.save(status, to: URL(fileURLWithPath: workspace.paths.ascPrivacyStatus))
            try store.appendAudit(
                .init(action: .ascPrivacyUpdated, summary: "Recorded manual App Privacy confirmation"),
                to: workspace
            )
            return try render(status, json: json) {
                "ASC App Privacy manually marked as Data Not Collected."
            }
        case "set-not-collected":
            break
        default:
            throw AscendKitError.invalidArguments("Usage: ascendkit asc privacy set-not-collected|status|confirm-manual --workspace PATH [--app-id ID] [--confirm-remote-mutation] [--data-not-collected] [--json]")
        }
        guard args.contains("--confirm-remote-mutation") else {
            let status = AppPrivacyStatus(
                state: .unknown,
                source: "dry-run",
                findings: ["ASC app privacy was not changed. Pass --confirm-remote-mutation to attempt Data Not Collected publishing."]
            )
            try store.save(status, to: URL(fileURLWithPath: workspace.paths.ascPrivacyStatus))
            return try render(status, json: json) {
                "ASC app privacy was not changed: pass --confirm-remote-mutation to publish Data Not Collected answers."
            }
        }

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
        let irisUnauthorized = responses.contains(where: { $0.statusCode == 401 })
        let status = AppPrivacyStatus(
            state: irisUnauthorized ? .requiresManualAppStoreConnect : .publishedDataNotCollected,
            source: irisUnauthorized ? "apple-iris-api-key-unauthorized" : "app-store-connect-api",
            findings: irisUnauthorized
                ? [
                    "Apple's IRIS App Privacy endpoint rejected ASC API key authentication.",
                    "Complete App Privacy in App Store Connect UI, then run asc privacy confirm-manual --data-not-collected."
                ]
                : ["Published App Privacy answers as Data Not Collected."]
        )
        try store.save(status, to: URL(fileURLWithPath: workspace.paths.ascPrivacyStatus))
        try store.appendAudit(
            .init(
                action: .ascPrivacyUpdated,
                summary: irisUnauthorized
                    ? "Skipped ASC app privacy publish because IRIS rejected API key auth"
                    : "Published ASC app privacy Data Not Collected answers",
                details: ["appID": appID, "responses": "\(responses.count)"]
            ),
            to: workspace
        )
        return try render(status, json: json) {
            irisUnauthorized
                ? "ASC app privacy could not be published with API key auth; use App Store Connect UI or Apple ID web session support."
                : "ASC app privacy Data Not Collected answers published with \(responses.count) response(s)."
        }
    }

    private func renderAppPrivacyStatusText(_ status: AppPrivacyStatus) -> String {
        var lines = [
            "ASC App Privacy status: \(status.state.rawValue) via \(status.source)",
            "Ready for submission: \(status.readyForSubmission ? "yes" : "no")"
        ]
        if !status.findings.isEmpty {
            lines.append("App Privacy finding(s):")
            lines.append(contentsOf: status.findings.map { "- \($0)" })
        }
        if !status.nextActions.isEmpty {
            lines.append("Next action(s):")
            lines.append(contentsOf: status.nextActions.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
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
            screenshotCopyLintReport: context.screenshotCopyLintReport,
            screenshotCompositionManifest: context.screenshotCompositionManifest,
            ascLookupPlan: context.ascLookupPlan,
            appPrivacyStatus: context.appPrivacyStatus,
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
                    "Review submission execution was not run: pass --confirm-remote-submission to record the current boundary-disabled result."
                }
            }
            guard plan.remoteSubmissionExecutionAllowed else {
                let result = ReviewSubmissionExecutionResult.boundaryDisabled(
                    appStoreVersionID: try loadIfExists(MetadataObservedState.self, path: workspace.paths.ascObservedState)?.appStoreVersionID,
                    buildID: plan.selectedBuildID
                )
                try store.save(result, to: URL(fileURLWithPath: workspace.paths.reviewSubmissionResult))
                try store.appendAudit(
                    .init(
                        action: .reviewSubmissionPlanned,
                        summary: "Skipped remote review submission because execution is disabled"
                    ),
                    to: workspace
                )
                return try render(result, json: json) {
                    "Review submission execution is disabled by AscendKit boundary; use submit handoff and submit manually in App Store Connect."
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
            renderSubmissionReadinessText(report)
        }
    }

    private func renderSubmissionReadinessText(_ report: SubmissionReadinessReport) -> String {
        let header = "Submission readiness: \(report.ready ? "ready" : "not ready")"
        let blockers = report.items.filter { !$0.satisfied }
        guard !blockers.isEmpty else {
            return header
        }
        let lines = blockers.map { item in
            let note = item.note.map { " - \($0)" } ?? ""
            return "- \(item.id): \(item.title)\(note)"
        }
        return ([header, "Unsatisfied checklist item(s):"] + lines).joined(separator: "\n")
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
            appPrivacyStatus: context.appPrivacyStatus,
            buildCandidatesReport: context.buildCandidatesReport
        )
    }

    private struct SubmissionContext {
        var manifest: ReleaseManifest
        var doctorReport: DoctorReport?
        var reviewInfo: ReviewInfo?
        var metadataLintReports: [MetadataLintReport]
        var screenshotImportManifest: ScreenshotImportManifest?
        var screenshotCopyLintReport: ScreenshotCompositionCopyLintReport?
        var screenshotCompositionManifest: ScreenshotCompositionManifest?
        var ascLookupPlan: ASCLookupPlan?
        var appPrivacyStatus: AppPrivacyStatus?
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
        let screenshotCopyLintReport = try loadIfExists(ScreenshotCompositionCopyLintReport.self, path: workspace.paths.screenshotCopyLint)
        let screenshotCompositionManifest = try loadIfExists(ScreenshotCompositionManifest.self, path: workspace.paths.screenshotCompositionManifest)
        let ascLookupPlan = try loadIfExists(ASCLookupPlan.self, path: workspace.paths.ascLookupPlan)
        let appPrivacyStatus = try loadIfExists(AppPrivacyStatus.self, path: workspace.paths.ascPrivacyStatus)
        let buildCandidatesReport = try loadIfExists(BuildCandidatesReport.self, path: workspace.paths.buildCandidates)
        let iapValidationReport = try loadIfExists(IAPValidationReport.self, path: workspace.paths.iapValidation)
        return SubmissionContext(
            manifest: manifest,
            doctorReport: doctorReport,
            reviewInfo: reviewInfo,
            metadataLintReports: metadataLintReports,
            screenshotImportManifest: screenshotImportManifest,
            screenshotCopyLintReport: screenshotCopyLintReport,
            screenshotCompositionManifest: screenshotCompositionManifest,
            ascLookupPlan: ascLookupPlan,
            appPrivacyStatus: appPrivacyStatus,
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

    private func repeatedValues(after flag: String, in args: [String]) -> [String] {
        args.indices.compactMap { index in
            guard args[index] == flag, args.indices.contains(index + 1) else {
                return nil
            }
            return args[index + 1]
        }
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
        if value == "keychain" {
            return nil
        }
        return SecretProvider(rawValue: value)
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    static let help = AscendKitCommandCatalog.helpText
}
