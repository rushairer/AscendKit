import AppKit
import Foundation

public enum ScreenshotInputPath: String, Codable, Equatable, Sendable {
    case uiTestCapture
    case userProvided
}

public struct ScreenshotPlanningInput: Codable, Equatable, Sendable {
    public var appCategory: String
    public var targetAudience: String
    public var positioning: String
    public var keyFeatures: [String]
    public var importantScreens: [String]
    public var platforms: [ApplePlatform]
    public var locales: [String]

    public init(
        appCategory: String,
        targetAudience: String,
        positioning: String,
        keyFeatures: [String],
        importantScreens: [String],
        platforms: [ApplePlatform],
        locales: [String] = ["en-US"]
    ) {
        self.appCategory = appCategory
        self.targetAudience = targetAudience
        self.positioning = positioning
        self.keyFeatures = keyFeatures
        self.importantScreens = importantScreens
        self.platforms = platforms
        self.locales = locales
    }
}

public struct ScreenshotPlanItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var screenName: String
    public var order: Int
    public var purpose: String
    public var requiredFeatures: [String]

    public init(id: String, screenName: String, order: Int, purpose: String, requiredFeatures: [String] = []) {
        self.id = id
        self.screenName = screenName
        self.order = order
        self.purpose = purpose
        self.requiredFeatures = requiredFeatures
    }
}

public struct ScreenshotPlan: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var inputPath: ScreenshotInputPath
    public var platforms: [ApplePlatform]
    public var locales: [String]
    public var items: [ScreenshotPlanItem]
    public var coverageGaps: [String]
    public var sourceDirectory: String?

    public init(
        schemaVersion: Int = 1,
        inputPath: ScreenshotInputPath,
        platforms: [ApplePlatform],
        locales: [String],
        items: [ScreenshotPlanItem],
        coverageGaps: [String] = [],
        sourceDirectory: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.inputPath = inputPath
        self.platforms = platforms
        self.locales = locales
        self.items = items
        self.coverageGaps = coverageGaps
        self.sourceDirectory = sourceDirectory
    }

    public static func makeDeterministicPlan(
        from input: ScreenshotPlanningInput,
        inputPath: ScreenshotInputPath = .userProvided,
        sourceDirectory: String? = nil
    ) -> ScreenshotPlan {
        let items = input.importantScreens.enumerated().map { offset, screen in
            ScreenshotPlanItem(
                id: screen.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "-"),
                screenName: screen,
                order: offset + 1,
                purpose: "Show \(screen) for \(input.targetAudience).",
                requiredFeatures: input.keyFeatures.filter { feature in
                    screen.localizedCaseInsensitiveContains(feature)
                }
            )
        }
        let coveredText = input.importantScreens.joined(separator: " ").lowercased()
        let gaps = input.keyFeatures.filter { !coveredText.contains($0.lowercased()) }
        return ScreenshotPlan(
            inputPath: inputPath,
            platforms: input.platforms,
            locales: input.locales,
            items: items,
            coverageGaps: gaps,
            sourceDirectory: sourceDirectory
        )
    }
}

public enum ScreenshotReadinessSeverity: String, Codable, Equatable, Sendable {
    case blocker
    case warning
}

public struct ScreenshotReadinessFinding: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var severity: ScreenshotReadinessSeverity
    public var message: String
    public var nextAction: String

    public init(id: String, severity: ScreenshotReadinessSeverity, message: String, nextAction: String) {
        self.id = id
        self.severity = severity
        self.message = message
        self.nextAction = nextAction
    }
}

public struct ScreenshotReadinessResult: Codable, Equatable, Sendable {
    public var ready: Bool
    public var generatedAt: Date
    public var findings: [ScreenshotReadinessFinding]

    public init(generatedAt: Date = Date(), findings: [ScreenshotReadinessFinding]) {
        self.ready = !findings.contains { $0.severity == .blocker }
        self.generatedAt = generatedAt
        self.findings = findings
    }
}

public struct ScreenshotReadinessEvaluator {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func evaluate(plan: ScreenshotPlan, sourceDirectory: URL? = nil) -> ScreenshotReadinessResult {
        var findings: [ScreenshotReadinessFinding] = []

        if plan.platforms.isEmpty {
            findings.append(.init(
                id: "screenshots.platforms.missing",
                severity: .blocker,
                message: "Screenshot plan does not define any target platforms.",
                nextAction: "Add at least one Apple platform to the screenshot plan."
            ))
        }

        if plan.locales.isEmpty {
            findings.append(.init(
                id: "screenshots.locales.missing",
                severity: .blocker,
                message: "Screenshot plan does not define any locales.",
                nextAction: "Add at least en-US to the screenshot plan locale matrix."
            ))
        }

        if plan.items.isEmpty {
            findings.append(.init(
                id: "screenshots.items.missing",
                severity: .blocker,
                message: "Screenshot plan has no planned screens.",
                nextAction: "Add planned screens or generate a plan from structured inputs."
            ))
        }

        for gap in plan.coverageGaps {
            findings.append(.init(
                id: "screenshots.coverage.\(gap.lowercased())",
                severity: .warning,
                message: "Key feature is not clearly covered by planned screenshots: \(gap).",
                nextAction: "Add a screen that visually proves this feature."
            ))
        }

        if plan.inputPath == .userProvided {
            let effectiveSourceDirectory = sourceDirectory ?? plan.sourceDirectory.map { URL(fileURLWithPath: $0) }
            guard let effectiveSourceDirectory else {
                findings.append(.init(
                    id: "screenshots.import.source-missing",
                    severity: .blocker,
                    message: "User-provided screenshot path was selected but no source directory was supplied.",
                    nextAction: "Pass a source screenshot directory."
                ))
                return ScreenshotReadinessResult(findings: findings)
            }
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: effectiveSourceDirectory.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                findings.append(.init(
                    id: "screenshots.import.source-not-found",
                    severity: .blocker,
                    message: "Source screenshot directory does not exist: \(effectiveSourceDirectory.path).",
                    nextAction: "Create the directory or point to the correct screenshot import path."
                ))
            } else {
                findings.append(contentsOf: importDirectoryFindings(plan: plan, sourceDirectory: effectiveSourceDirectory))
            }
        }

        return ScreenshotReadinessResult(findings: findings)
    }

    private func importDirectoryFindings(plan: ScreenshotPlan, sourceDirectory: URL) -> [ScreenshotReadinessFinding] {
        var findings: [ScreenshotReadinessFinding] = []
        for locale in plan.locales {
            let localeDirectory = sourceDirectory.appendingPathComponent(locale)
            if !directoryExists(localeDirectory) {
                findings.append(.init(
                    id: "screenshots.import.locale.\(locale).missing",
                    severity: .blocker,
                    message: "Screenshot import locale directory is missing: \(locale).",
                    nextAction: "Create \(localeDirectory.path) and add platform-specific screenshot folders."
                ))
                continue
            }

            for platform in plan.platforms {
                let platformDirectory = localeDirectory.appendingPathComponent(platform.rawValue)
                if !directoryExists(platformDirectory) {
                    findings.append(.init(
                        id: "screenshots.import.\(locale).\(platform.rawValue).missing",
                        severity: .blocker,
                        message: "Screenshot import platform directory is missing for \(locale)/\(platform.rawValue).",
                        nextAction: "Create \(platformDirectory.path) and add one image per planned screen."
                    ))
                    continue
                }

                let images = imageFiles(in: platformDirectory)
                if images.count < plan.items.count {
                    findings.append(.init(
                        id: "screenshots.import.\(locale).\(platform.rawValue).count",
                        severity: .blocker,
                        message: "Expected at least \(plan.items.count) screenshot image(s) for \(locale)/\(platform.rawValue), found \(images.count).",
                        nextAction: "Add missing PNG, JPG, JPEG, HEIC, or TIFF screenshot files."
                    ))
                }
            }
        }
        return findings
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func imageFiles(in directory: URL) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        let supported = Set(["png", "jpg", "jpeg", "heic", "tif", "tiff"])
        return contents.filter { supported.contains($0.pathExtension.lowercased()) }
    }
}

public struct ScreenshotArtifact: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }
    public var locale: String
    public var platform: ApplePlatform
    public var path: String
    public var fileName: String

    public init(locale: String, platform: ApplePlatform, path: String, fileName: String) {
        self.locale = locale
        self.platform = platform
        self.path = path
        self.fileName = fileName
    }
}

public struct ScreenshotImportManifest: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var sourceDirectory: String
    public var artifacts: [ScreenshotArtifact]

    public init(generatedAt: Date = Date(), sourceDirectory: String, artifacts: [ScreenshotArtifact]) {
        self.generatedAt = generatedAt
        self.sourceDirectory = sourceDirectory
        self.artifacts = artifacts
    }
}

public struct ScreenshotImporter {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func makeManifest(plan: ScreenshotPlan, sourceDirectory: URL) -> ScreenshotImportManifest {
        var artifacts: [ScreenshotArtifact] = []
        for locale in plan.locales {
            for platform in plan.platforms {
                let directory = sourceDirectory
                    .appendingPathComponent(locale)
                    .appendingPathComponent(platform.rawValue)
                artifacts.append(contentsOf: imageFiles(in: directory).map { url in
                    ScreenshotArtifact(
                        locale: locale,
                        platform: platform,
                        path: url.standardizedFileURL.path,
                        fileName: url.lastPathComponent
                    )
                })
            }
        }
        return ScreenshotImportManifest(
            sourceDirectory: sourceDirectory.standardizedFileURL.path,
            artifacts: artifacts.sorted { lhs, rhs in
                if lhs.locale != rhs.locale { return lhs.locale < rhs.locale }
                if lhs.platform != rhs.platform { return lhs.platform.rawValue < rhs.platform.rawValue }
                return lhs.fileName < rhs.fileName
            }
        )
    }

    public func makeFastlaneManifest(sourceDirectory: URL, locales: [String] = []) -> ScreenshotImportManifest {
        let effectiveLocales = locales.isEmpty ? discoveredLocales(in: sourceDirectory) : locales
        var artifacts: [ScreenshotArtifact] = []

        for locale in effectiveLocales {
            let localeDirectory = sourceDirectory.appendingPathComponent(locale)
            artifacts.append(contentsOf: imageFiles(in: localeDirectory).compactMap { url in
                guard !url.deletingPathExtension().lastPathComponent.hasSuffix("_framed") else {
                    return nil
                }
                return ScreenshotArtifact(
                    locale: locale,
                    platform: inferPlatform(from: url.lastPathComponent),
                    path: url.standardizedFileURL.path,
                    fileName: url.lastPathComponent
                )
            })
        }

        return ScreenshotImportManifest(
            sourceDirectory: sourceDirectory.standardizedFileURL.path,
            artifacts: artifacts.sorted { lhs, rhs in
                if lhs.locale != rhs.locale { return lhs.locale < rhs.locale }
                if lhs.platform != rhs.platform { return lhs.platform.rawValue < rhs.platform.rawValue }
                return lhs.fileName < rhs.fileName
            }
        )
    }

    private func imageFiles(in directory: URL) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        let supported = Set(["png", "jpg", "jpeg", "heic", "tif", "tiff"])
        return contents.filter { supported.contains($0.pathExtension.lowercased()) }
    }

    private func discoveredLocales(in sourceDirectory: URL) -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.compactMap { url in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return url.lastPathComponent
        }
        .sorted()
    }

    private func inferPlatform(from fileName: String) -> ApplePlatform {
        if fileName.localizedCaseInsensitiveContains("iPad") {
            return .iPadOS
        }
        if fileName.localizedCaseInsensitiveContains("iPhone") {
            return .iOS
        }
        if fileName.localizedCaseInsensitiveContains("Mac") {
            return .macOS
        }
        return .unknown
    }
}

public enum ScreenshotCompositionMode: String, Codable, Equatable, Sendable {
    case storeReadyCopy
    case poster
    case deviceFrame
}

public struct ScreenshotCompositionArtifact: Codable, Equatable, Identifiable, Sendable {
    public var id: String { outputPath }
    public var locale: String
    public var platform: ApplePlatform
    public var inputPath: String
    public var outputPath: String
    public var mode: ScreenshotCompositionMode

    public init(locale: String, platform: ApplePlatform, inputPath: String, outputPath: String, mode: ScreenshotCompositionMode) {
        self.locale = locale
        self.platform = platform
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.mode = mode
    }
}

public struct ScreenshotCompositionManifest: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var mode: ScreenshotCompositionMode
    public var artifacts: [ScreenshotCompositionArtifact]

    public init(generatedAt: Date = Date(), mode: ScreenshotCompositionMode, artifacts: [ScreenshotCompositionArtifact]) {
        self.generatedAt = generatedAt
        self.mode = mode
        self.artifacts = artifacts
    }
}

public enum ScreenshotUploadSourceKind: String, Codable, Equatable, Sendable {
    case imported
    case composed
}

public struct ScreenshotUploadPlanItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var locale: String
    public var platform: ApplePlatform
    public var displayType: String
    public var appStoreVersionLocalizationID: String
    public var sourcePath: String
    public var fileName: String
    public var order: Int
    public var uploadOperations: [String]

    public init(
        locale: String,
        platform: ApplePlatform,
        displayType: String,
        appStoreVersionLocalizationID: String,
        sourcePath: String,
        fileName: String,
        order: Int,
        uploadOperations: [String] = [
            "create appScreenshotSet when missing",
            "create appScreenshot reservation",
            "upload asset delivery parts",
            "commit appScreenshot",
            "wait for processing"
        ]
    ) {
        self.locale = locale
        self.platform = platform
        self.displayType = displayType
        self.appStoreVersionLocalizationID = appStoreVersionLocalizationID
        self.sourcePath = sourcePath
        self.fileName = fileName
        self.order = order
        self.uploadOperations = uploadOperations
        self.id = [
            locale,
            platform.rawValue,
            displayType,
            "\(order)",
            fileName
        ].joined(separator: ":")
    }
}

public struct ScreenshotRemoteDeletion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var locale: String
    public var displayType: String
    public var appScreenshotSetID: String
    public var appScreenshotID: String
    public var fileName: String?

    public init(
        locale: String,
        displayType: String,
        appScreenshotSetID: String,
        appScreenshotID: String,
        fileName: String? = nil
    ) {
        self.locale = locale
        self.displayType = displayType
        self.appScreenshotSetID = appScreenshotSetID
        self.appScreenshotID = appScreenshotID
        self.fileName = fileName
        self.id = [locale, displayType, appScreenshotSetID, appScreenshotID].joined(separator: ":")
    }
}

public struct ScreenshotUploadPlan: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var sourceKind: ScreenshotUploadSourceKind
    public var dryRunOnly: Bool
    public var items: [ScreenshotUploadPlanItem]
    public var findings: [String]
    public var replaceExistingRemoteScreenshots: Bool?
    public var remoteScreenshotsToDelete: [ScreenshotRemoteDeletion]?

    public init(
        generatedAt: Date = Date(),
        sourceKind: ScreenshotUploadSourceKind,
        dryRunOnly: Bool = true,
        items: [ScreenshotUploadPlanItem],
        findings: [String] = [],
        replaceExistingRemoteScreenshots: Bool = false,
        remoteScreenshotsToDelete: [ScreenshotRemoteDeletion] = []
    ) {
        self.generatedAt = generatedAt
        self.sourceKind = sourceKind
        self.dryRunOnly = dryRunOnly
        self.items = items
        self.findings = findings
        self.replaceExistingRemoteScreenshots = replaceExistingRemoteScreenshots
        self.remoteScreenshotsToDelete = remoteScreenshotsToDelete
    }
}

public struct ScreenshotUploadExecutionResult: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var executed: Bool
    public var uploadedCount: Int
    public var items: [ScreenshotUploadExecutionItem]
    public var findings: [String]
    public var deletedScreenshots: [ScreenshotRemoteDeletion]?
    public var failedItems: [ScreenshotUploadFailure]?

    public init(
        generatedAt: Date = Date(),
        executed: Bool,
        uploadedCount: Int = 0,
        items: [ScreenshotUploadExecutionItem] = [],
        findings: [String] = [],
        deletedScreenshots: [ScreenshotRemoteDeletion] = [],
        failedItems: [ScreenshotUploadFailure] = []
    ) {
        self.generatedAt = generatedAt
        self.executed = executed
        self.uploadedCount = uploadedCount
        self.items = items
        self.findings = findings
        self.deletedScreenshots = deletedScreenshots
        self.failedItems = failedItems
    }
}

public struct ScreenshotUploadFailure: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var phase: String
    public var planItemID: String?
    public var appScreenshotID: String?
    public var fileName: String?
    public var message: String

    public init(
        phase: String,
        planItemID: String? = nil,
        appScreenshotID: String? = nil,
        fileName: String? = nil,
        message: String
    ) {
        self.phase = phase
        self.planItemID = planItemID
        self.appScreenshotID = appScreenshotID
        self.fileName = fileName
        self.message = message
        self.id = [
            phase,
            planItemID ?? appScreenshotID ?? fileName ?? "unknown"
        ].joined(separator: ":")
    }
}

public struct ScreenshotUploadExecutionItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var planItemID: String
    public var appScreenshotSetID: String
    public var appScreenshotID: String
    public var fileName: String
    public var checksum: String
    public var assetDeliveryState: String?
    public var responses: [ReviewSubmissionExecutionResponse]

    public init(
        planItemID: String,
        appScreenshotSetID: String,
        appScreenshotID: String,
        fileName: String,
        checksum: String,
        assetDeliveryState: String? = nil,
        responses: [ReviewSubmissionExecutionResponse] = []
    ) {
        self.planItemID = planItemID
        self.appScreenshotSetID = appScreenshotSetID
        self.appScreenshotID = appScreenshotID
        self.fileName = fileName
        self.checksum = checksum
        self.assetDeliveryState = assetDeliveryState
        self.responses = responses
        self.id = appScreenshotID
    }
}

public struct ScreenshotUploadPlanBuilder {
    public init() {}

    public func build(
        importManifest: ScreenshotImportManifest?,
        compositionManifest: ScreenshotCompositionManifest?,
        observedState: MetadataObservedState?,
        displayTypeOverride: String? = nil,
        replaceExistingRemoteScreenshots: Bool = false
    ) -> ScreenshotUploadPlan {
        let composedArtifacts = compositionManifest?.artifacts ?? []
        let sourceKind: ScreenshotUploadSourceKind = composedArtifacts.isEmpty ? .imported : .composed
        let sourceArtifacts = composedArtifacts.isEmpty
            ? importArtifacts(from: importManifest)
            : composedArtifacts.map {
                UploadSourceArtifact(
                    locale: $0.locale,
                    platform: $0.platform,
                    path: $0.outputPath,
                    fileName: URL(fileURLWithPath: $0.outputPath).lastPathComponent
                )
            }

        var findings: [String] = []
        if sourceArtifacts.isEmpty {
            findings.append("No screenshot artifacts are available. Run screenshots import or screenshots compose first.")
        }
        if observedState == nil {
            findings.append("ASC observed metadata state is missing. Run asc metadata observe before planning screenshot upload.")
        }

        let grouped = Dictionary(grouping: sourceArtifacts) { "\($0.locale)|\($0.platform.rawValue)" }
        let items = grouped
            .flatMap { _, artifacts in
                artifacts.sorted { $0.fileName < $1.fileName }.enumerated().compactMap { offset, artifact -> ScreenshotUploadPlanItem? in
                    guard let localizationID = observedState?.resourceIDsByLocale?[artifact.locale]?.appStoreVersionLocalizationID else {
                        findings.append("Missing appStoreVersionLocalizationID for locale \(artifact.locale).")
                        return nil
                    }
                    return ScreenshotUploadPlanItem(
                        locale: artifact.locale,
                        platform: artifact.platform,
                        displayType: displayTypeOverride ?? defaultDisplayType(for: artifact.platform),
                        appStoreVersionLocalizationID: localizationID,
                        sourcePath: artifact.path,
                        fileName: artifact.fileName,
                        order: offset + 1
                    )
                }
            }
            .sorted {
                if $0.locale != $1.locale { return $0.locale < $1.locale }
                if $0.platform.rawValue != $1.platform.rawValue { return $0.platform.rawValue < $1.platform.rawValue }
                if $0.displayType != $1.displayType { return $0.displayType < $1.displayType }
                return $0.order < $1.order
            }

        let remoteScreenshotsToDelete = existingRemoteScreenshots(items: items, observedState: observedState)
        findings.append(contentsOf: localizationMismatchFindings(items: items, observedState: observedState))
        if !replaceExistingRemoteScreenshots {
            findings.append(contentsOf: existingScreenshotFindings(deletions: remoteScreenshotsToDelete))
        }

        return ScreenshotUploadPlan(
            sourceKind: sourceKind,
            items: items,
            findings: Array(Set(findings)).sorted(),
            replaceExistingRemoteScreenshots: replaceExistingRemoteScreenshots,
            remoteScreenshotsToDelete: remoteScreenshotsToDelete
        )
    }

    private func importArtifacts(from manifest: ScreenshotImportManifest?) -> [UploadSourceArtifact] {
        (manifest?.artifacts ?? []).map {
            UploadSourceArtifact(
                locale: $0.locale,
                platform: $0.platform,
                path: $0.path,
                fileName: $0.fileName
            )
        }
    }

    private func defaultDisplayType(for platform: ApplePlatform) -> String {
        switch platform {
        case .iPadOS:
            return "APP_IPAD_PRO_3GEN_129"
        case .macOS:
            return "APP_DESKTOP"
        case .tvOS:
            return "APP_APPLE_TV"
        case .watchOS:
            return "APP_WATCH_ULTRA"
        case .visionOS:
            return "APP_VISION_PRO"
        case .iOS, .unknown:
            return "APP_IPHONE_67"
        }
    }

    private func existingRemoteScreenshots(
        items: [ScreenshotUploadPlanItem],
        observedState: MetadataObservedState?
    ) -> [ScreenshotRemoteDeletion] {
        guard let observedState else {
            return []
        }

        var deletions: [ScreenshotRemoteDeletion] = []
        let targets = Set(items.map { "\($0.locale)|\($0.displayType)" })
        for (locale, sets) in observedState.screenshotSetsByLocale ?? [:] {
            for set in sets where !set.screenshots.isEmpty {
                guard targets.contains("\(locale)|\(set.displayType)") else {
                    continue
                }
                deletions.append(contentsOf: set.screenshots.map {
                    ScreenshotRemoteDeletion(
                        locale: locale,
                        displayType: set.displayType,
                        appScreenshotSetID: set.id,
                        appScreenshotID: $0.id,
                        fileName: $0.fileName
                    )
                })
            }
        }

        return deletions.sorted {
            if $0.locale != $1.locale { return $0.locale < $1.locale }
            if $0.displayType != $1.displayType { return $0.displayType < $1.displayType }
            return $0.appScreenshotID < $1.appScreenshotID
        }
    }

    private func existingScreenshotFindings(deletions: [ScreenshotRemoteDeletion]) -> [String] {
        var findings: [String] = []
        let grouped = Dictionary(grouping: deletions.filter { !$0.appScreenshotID.isEmpty }) {
            "\($0.locale)|\($0.displayType)"
        }
        for (_, deletions) in grouped {
            guard let first = deletions.first else { continue }
            let names = deletions
                .compactMap(\.fileName)
                .sorted()
                .prefix(3)
                .joined(separator: ", ")
            let suffix = names.isEmpty ? "" : " Existing files include: \(names)."
            findings.append(
                "ASC already has \(deletions.count) screenshot(s) for \(first.locale)/\(first.displayType). Re-run upload-plan with --replace-existing to plan explicit deletion before upload, or clear existing screenshots in App Store Connect.\(suffix)"
            )
        }
        return findings
    }

    private func localizationMismatchFindings(
        items: [ScreenshotUploadPlanItem],
        observedState: MetadataObservedState?
    ) -> [String] {
        guard let observedState else {
            return []
        }

        var localeByLocalizationID: [String: String] = [:]
        for (locale, resourceIDs) in observedState.resourceIDsByLocale ?? [:] {
            if let appStoreVersionLocalizationID = resourceIDs.appStoreVersionLocalizationID {
                localeByLocalizationID[appStoreVersionLocalizationID] = locale
            }
        }

        return items.compactMap { item in
            guard let locale = localeByLocalizationID[item.appStoreVersionLocalizationID],
                  locale != item.locale else {
                return nil
            }
            return (
                "Screenshot item \(item.fileName) targets localization \(item.appStoreVersionLocalizationID), which observed state maps to \(locale), not \(item.locale)."
            )
        }
    }

    private struct UploadSourceArtifact {
        var locale: String
        var platform: ApplePlatform
        var path: String
        var fileName: String
    }
}

public struct ScreenshotComposer {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func compose(importManifest: ScreenshotImportManifest, outputRoot: URL, mode: ScreenshotCompositionMode) throws -> ScreenshotCompositionManifest {
        var artifacts: [ScreenshotCompositionArtifact] = []
        for artifact in importManifest.artifacts {
            let inputURL = URL(fileURLWithPath: artifact.path)
            let outputDirectory = outputRoot
                .appendingPathComponent(mode.rawValue)
                .appendingPathComponent(artifact.locale)
                .appendingPathComponent(artifact.platform.rawValue)
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            let outputURL: URL
            switch mode {
            case .storeReadyCopy:
                outputURL = outputDirectory.appendingPathComponent(artifact.fileName)
                try replaceExistingFile(at: outputURL) {
                    try fileManager.copyItem(at: inputURL, to: outputURL)
                }
            case .poster:
                let baseName = inputURL.deletingPathExtension().lastPathComponent
                outputURL = outputDirectory.appendingPathComponent("\(baseName)-poster.png")
                try replaceExistingFile(at: outputURL) {
                    try renderPoster(inputURL: inputURL, outputURL: outputURL)
                }
            case .deviceFrame:
                let baseName = inputURL.deletingPathExtension().lastPathComponent
                outputURL = outputDirectory.appendingPathComponent("\(baseName)-device-frame.png")
                try replaceExistingFile(at: outputURL) {
                    try renderDeviceFrame(inputURL: inputURL, outputURL: outputURL)
                }
            }

            artifacts.append(ScreenshotCompositionArtifact(
                locale: artifact.locale,
                platform: artifact.platform,
                inputPath: inputURL.standardizedFileURL.path,
                outputPath: outputURL.standardizedFileURL.path,
                mode: mode
            ))
        }
        return ScreenshotCompositionManifest(mode: mode, artifacts: artifacts)
    }

    private func replaceExistingFile(at url: URL, write: () throws -> Void) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try write()
    }

    private func renderPoster(inputURL: URL, outputURL: URL) throws {
        guard let screenshot = NSImage(contentsOf: inputURL), screenshot.isValid else {
            throw AscendKitError.invalidState("Cannot decode screenshot image for poster composition: \(inputURL.path)")
        }

        let canvasSize = NSSize(width: 1_290, height: 2_796)
        let imageMaxSize = NSSize(width: 1_010, height: 2_090)
        let imageSize = aspectFitSize(source: screenshot.size, maximum: imageMaxSize)
        let imageRect = NSRect(
            x: (canvasSize.width - imageSize.width) / 2,
            y: 350,
            width: imageSize.width,
            height: imageSize.height
        )

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize.width),
            pixelsHigh: Int(canvasSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw AscendKitError.invalidState("Cannot allocate poster bitmap: \(outputURL.path)")
        }

        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.current = previousContext }

        NSColor(calibratedRed: 0.95, green: 0.91, blue: 0.84, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        let accentRect = NSRect(x: 0, y: canvasSize.height - 760, width: canvasSize.width, height: 760)
        NSColor(calibratedRed: 0.13, green: 0.24, blue: 0.23, alpha: 1).setFill()
        accentRect.fill()

        let title = inputURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 76, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        NSString(string: title.capitalized).draw(
            in: NSRect(x: 112, y: canvasSize.height - 300, width: canvasSize.width - 224, height: 110),
            withAttributes: titleAttributes
        )

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowOffset = NSSize(width: 0, height: -18)
        shadow.shadowBlurRadius = 42
        shadow.set()

        let roundedRect = NSBezierPath(roundedRect: imageRect, xRadius: 58, yRadius: 58)
        NSColor.white.setFill()
        roundedRect.fill()

        NSGraphicsContext.saveGraphicsState()
        roundedRect.addClip()
        screenshot.draw(
            in: imageRect,
            from: NSRect(origin: .zero, size: screenshot.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AscendKitError.invalidState("Cannot encode poster PNG: \(outputURL.path)")
        }
        try png.write(to: outputURL, options: [.atomic])
    }

    private func renderDeviceFrame(inputURL: URL, outputURL: URL) throws {
        guard let screenshot = NSImage(contentsOf: inputURL), screenshot.isValid else {
            throw AscendKitError.invalidState("Cannot decode screenshot image for device-frame composition: \(inputURL.path)")
        }

        let screenshotSize = screenshot.size
        guard screenshotSize.width > 0, screenshotSize.height > 0 else {
            throw AscendKitError.invalidState("Screenshot has invalid dimensions: \(inputURL.path)")
        }

        let border: CGFloat = max(24, min(screenshotSize.width, screenshotSize.height) * 0.055)
        let outerRadius: CGFloat = border * 1.65
        let innerRadius: CGFloat = border * 1.10
        let canvasSize = NSSize(
            width: screenshotSize.width + border * 2,
            height: screenshotSize.height + border * 2
        )
        let screenRect = NSRect(
            x: border,
            y: border,
            width: screenshotSize.width,
            height: screenshotSize.height
        )

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize.width.rounded(.up)),
            pixelsHigh: Int(canvasSize.height.rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw AscendKitError.invalidState("Cannot allocate device-frame bitmap: \(outputURL.path)")
        }

        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.current = previousContext }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        let outerPath = NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: canvasSize),
            xRadius: outerRadius,
            yRadius: outerRadius
        )
        NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.10, alpha: 1).setFill()
        outerPath.fill()

        let innerPath = NSBezierPath(roundedRect: screenRect, xRadius: innerRadius, yRadius: innerRadius)
        NSGraphicsContext.saveGraphicsState()
        innerPath.addClip()
        screenshot.draw(
            in: screenRect,
            from: NSRect(origin: .zero, size: screenshotSize),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.18).setStroke()
        outerPath.lineWidth = max(2, border * 0.06)
        outerPath.stroke()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AscendKitError.invalidState("Cannot encode device-frame PNG: \(outputURL.path)")
        }
        try png.write(to: outputURL, options: [.atomic])
    }

    private func aspectFitSize(source: NSSize, maximum: NSSize) -> NSSize {
        guard source.width > 0, source.height > 0 else {
            return maximum
        }
        let ratio = min(maximum.width / source.width, maximum.height / source.height)
        return NSSize(width: source.width * ratio, height: source.height * ratio)
    }
}
