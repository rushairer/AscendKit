import Foundation

public enum DoctorSeverity: String, Codable, Equatable, Comparable, Sendable {
    case info
    case warning
    case error
    case blocker

    public static func < (lhs: DoctorSeverity, rhs: DoctorSeverity) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ severity: DoctorSeverity) -> Int {
        switch severity {
        case .info: 0
        case .warning: 1
        case .error: 2
        case .blocker: 3
        }
    }
}

public enum DoctorCategory: String, Codable, Equatable, Sendable {
    case intake
    case versioning
    case assets
    case metadata
    case screenshots
    case privacy
    case exportCompliance
    case capabilities
    case appStoreConnect
    case submission
    case iap
}

public enum Fixability: String, Codable, Equatable, Sendable {
    case detectOnly
    case suggested
    case safeLocalAutofix
    case requiresConfirmation
}

public struct DoctorFinding: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var severity: DoctorSeverity
    public var category: DoctorCategory
    public var title: String
    public var detail: String
    public var fixability: Fixability
    public var nextAction: String?

    public init(
        id: String,
        severity: DoctorSeverity,
        category: DoctorCategory,
        title: String,
        detail: String,
        fixability: Fixability = .detectOnly,
        nextAction: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.title = title
        self.detail = detail
        self.fixability = fixability
        self.nextAction = nextAction
    }
}

public struct DoctorReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var findings: [DoctorFinding]

    public init(generatedAt: Date = Date(), findings: [DoctorFinding]) {
        self.generatedAt = generatedAt
        self.findings = findings.sorted { lhs, rhs in
            if lhs.severity == rhs.severity { return lhs.id < rhs.id }
            return lhs.severity > rhs.severity
        }
    }

    public var hasBlockers: Bool {
        findings.contains { $0.severity == .blocker }
    }
}

public struct ReleaseDoctor {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func run(
        manifest: ReleaseManifest,
        metadata: AppMetadata? = nil,
        screenshotPlan: ScreenshotPlan? = nil,
        screenshotImportManifest: ScreenshotImportManifest? = nil,
        iapValidationReport: IAPValidationReport? = nil
    ) -> DoctorReport {
        var findings: [DoctorFinding] = []

        if manifest.projects.isEmpty {
            findings.append(.init(
                id: "intake.no-project",
                severity: .blocker,
                category: .intake,
                title: "No Xcode project or workspace detected",
                detail: "Release intake needs a concrete .xcodeproj or .xcworkspace before downstream checks can be trusted.",
                nextAction: "Run intake with --project or --workspace."
            ))
        }

        if manifest.targets.isEmpty {
            findings.append(.init(
                id: "intake.no-targets",
                severity: .error,
                category: .intake,
                title: "No bundle targets detected",
                detail: "AscendKit could not infer bundle identifiers or version settings from the discovered project files.",
                nextAction: "Provide an explicit release manifest or inspect the Xcode project build settings."
            ))
        }

        for target in manifest.targets where target.isReleaseApplication {
            if target.bundleIdentifier?.isEmpty ?? true {
                findings.append(.init(
                    id: "versioning.\(target.name).missing-bundle-id",
                    severity: .error,
                    category: .versioning,
                    title: "Missing bundle identifier for \(target.name)",
                    detail: "App Store release assets must be tied to a stable bundle identifier.",
                    nextAction: "Set PRODUCT_BUNDLE_IDENTIFIER for the release target."
                ))
            }
            if target.version.marketingVersion?.isEmpty ?? true {
                findings.append(.init(
                    id: "versioning.\(target.name).missing-marketing-version",
                    severity: .warning,
                    category: .versioning,
                    title: "Missing marketing version for \(target.name)",
                    detail: "MARKETING_VERSION was not detected in the project build settings.",
                    nextAction: "Set MARKETING_VERSION or provide it in the release manifest."
                ))
            }
            if target.version.buildNumber?.isEmpty ?? true {
                findings.append(.init(
                    id: "versioning.\(target.name).missing-build-number",
                    severity: .warning,
                    category: .versioning,
                    title: "Missing build number for \(target.name)",
                    detail: "CURRENT_PROJECT_VERSION was not detected in the project build settings.",
                    nextAction: "Set CURRENT_PROJECT_VERSION or provide it in the release manifest."
                ))
            }
        }

        let plistInspector = InfoPlistInspector(fileManager: fileManager)
        let assetInspector = AssetCatalogInspector(fileManager: fileManager)
        let entitlementsInspector = EntitlementsInspector(fileManager: fileManager)
        let hygieneScanner = ReleaseHygieneScanner(fileManager: fileManager)
        for target in manifest.targets where target.isReleaseApplication {
            if let result = plistInspector.inspect(target: target, projectReferences: manifest.projects) {
                findings.append(contentsOf: result.findings)
            }
            findings.append(contentsOf: assetInspector.inspect(target: target, projectReferences: manifest.projects))
            findings.append(contentsOf: entitlementsInspector.inspect(target: target, projectReferences: manifest.projects))
        }
        findings.append(contentsOf: hygieneScanner.scan(projectReferences: manifest.projects))

        if let metadata {
            findings.append(contentsOf: MetadataLinter().lint(metadata: metadata).findings.map(\.doctorFinding))
        } else {
            findings.append(.init(
                id: "metadata.not-loaded",
                severity: .info,
                category: .metadata,
                title: "No local metadata loaded",
                detail: "Metadata linting was skipped because no local metadata file was supplied.",
                fixability: .suggested,
                nextAction: "Run metadata init, then metadata lint."
            ))
        }

        if let screenshotPlan {
            if let screenshotImportManifest, !screenshotImportManifest.artifacts.isEmpty {
                findings.append(contentsOf: screenshotPlan.coverageGaps.map { gap in
                    DoctorFinding(
                        id: "screenshots.coverage.\(gap.lowercased())",
                        severity: .warning,
                        category: .screenshots,
                        title: "Screenshot coverage warning",
                        detail: "Key feature is not clearly covered by planned screenshots: \(gap).",
                        fixability: .suggested,
                        nextAction: "Review imported screenshots and confirm this feature is visually represented."
                    )
                })
            } else {
                let readiness = ScreenshotReadinessEvaluator(fileManager: fileManager).evaluate(plan: screenshotPlan)
                findings.append(contentsOf: readiness.findings.map { finding in
                    DoctorFinding(
                        id: "screenshots.readiness.\(finding.id)",
                        severity: finding.severity == .blocker ? .error : .warning,
                        category: .screenshots,
                        title: "Screenshot readiness issue",
                        detail: finding.message,
                        fixability: .suggested,
                        nextAction: finding.nextAction
                    )
                })
            }
        } else {
            findings.append(.init(
                id: "screenshots.no-plan",
                severity: .warning,
                category: .screenshots,
                title: "No screenshot plan loaded",
                detail: "Screenshot readiness cannot be evaluated until a structured screenshot plan exists.",
                fixability: .suggested,
                nextAction: "Run screenshots plan with structured product inputs."
            ))
        }

        if let iapValidationReport, !iapValidationReport.valid {
            findings.append(.init(
                id: "iap.validation.failed",
                severity: .error,
                category: .iap,
                title: "Local IAP templates do not validate",
                detail: iapValidationReport.findings.joined(separator: " "),
                fixability: .suggested,
                nextAction: "Fix local IAP subscription templates and rerun iap validate."
            ))
        }

        return DoctorReport(findings: findings)
    }
}
