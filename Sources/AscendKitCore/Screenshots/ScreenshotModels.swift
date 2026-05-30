import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ScreenshotImageSanitizer {
    private static let renderLock = NSLock()

    public static func opaquePNGData(from imageURL: URL, backgroundColor: NSColor = .white) throws -> Data {
        guard let image = NSImage(contentsOf: imageURL), image.isValid else {
            throw AscendKitError.invalidState("Cannot decode screenshot image: \(imageURL.path)")
        }
        return try opaquePNGData(from: image, backgroundColor: backgroundColor)
    }

    public static func opaquePNGData(from image: NSImage, backgroundColor: NSColor = .white) throws -> Data {
        let canvasSize = bitmapPixelSize(for: image)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            throw AscendKitError.invalidState("Screenshot has invalid dimensions.")
        }

        var proposedRect = NSRect(origin: .zero, size: canvasSize)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: [.interpolation: NSImageInterpolation.high]) else {
            throw AscendKitError.invalidState("Cannot create screenshot bitmap.")
        }
        return try opaquePNGData(from: cgImage, size: canvasSize, backgroundColor: backgroundColor)
    }

    public static func renderOpaquePNG(
        size: NSSize,
        backgroundColor: NSColor = .white,
        draw: () throws -> Void
    ) throws -> Data {
        renderLock.lock()
        defer { renderLock.unlock() }

        guard size.width > 0, size.height > 0,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: Int(size.width.rounded(.up)),
                  pixelsHigh: Int(size.height.rounded(.up)),
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ) else {
            throw AscendKitError.invalidState("Cannot allocate screenshot bitmap.")
        }

        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.current = previousContext }

        backgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        try draw()

        guard let renderedImage = bitmap.cgImage else {
            throw AscendKitError.invalidState("Cannot create rendered screenshot image.")
        }
        return try opaquePNGData(from: renderedImage, size: size, backgroundColor: backgroundColor)
    }

    private static func bitmapPixelSize(for image: NSImage) -> NSSize {
        if let representation = image.representations.first {
            return NSSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return image.size
    }

    private static func opaquePNGData(from image: CGImage, size: NSSize, backgroundColor: NSColor) throws -> Data {
        let width = Int(size.width.rounded(.up))
        let height = Int(size.height.rounded(.up))
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            throw AscendKitError.invalidState("Cannot allocate opaque screenshot context.")
        }

        context.setFillColor(backgroundColor.usingColorSpace(.sRGB)?.cgColor ?? NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let flattenedImage = context.makeImage() else {
            throw AscendKitError.invalidState("Cannot flatten screenshot image.")
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw AscendKitError.invalidState("Cannot create opaque screenshot PNG destination.")
        }
        CGImageDestinationAddImage(destination, flattenedImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AscendKitError.invalidState("Cannot encode opaque screenshot PNG.")
        }
        return data as Data
    }
}

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

public struct ScreenshotCaptureDestination: Codable, Equatable, Sendable {
    public var platform: ApplePlatform
    public var name: String
    public var xcodebuildDestination: String

    public init(platform: ApplePlatform, name: String, xcodebuildDestination: String) {
        self.platform = platform
        self.name = name
        self.xcodebuildDestination = xcodebuildDestination
    }
}

public struct ScreenshotCaptureCommand: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var locale: String
    public var platform: ApplePlatform
    public var destinationName: String
    public var resultBundlePath: String
    public var rawOutputDirectory: String
    public var environment: [String: String]
    public var command: [String]

    public init(
        locale: String,
        platform: ApplePlatform,
        destinationName: String,
        resultBundlePath: String,
        rawOutputDirectory: String,
        environment: [String: String],
        command: [String]
    ) {
        self.locale = locale
        self.platform = platform
        self.destinationName = destinationName
        self.resultBundlePath = resultBundlePath
        self.rawOutputDirectory = rawOutputDirectory
        self.environment = environment
        self.command = command
        self.id = [locale, platform.rawValue, destinationName].joined(separator: ":")
    }
}

public struct ScreenshotCapturePlan: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var scheme: String
    public var projectPath: String?
    public var workspacePath: String?
    public var configuration: String
    public var destinations: [ScreenshotCaptureDestination]
    public var locales: [String]
    public var commands: [ScreenshotCaptureCommand]
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        scheme: String,
        projectPath: String? = nil,
        workspacePath: String? = nil,
        configuration: String = "Debug",
        destinations: [ScreenshotCaptureDestination],
        locales: [String],
        commands: [ScreenshotCaptureCommand],
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.scheme = scheme
        self.projectPath = projectPath
        self.workspacePath = workspacePath
        self.configuration = configuration
        self.destinations = destinations
        self.locales = locales
        self.commands = commands
        self.findings = findings
    }
}

public struct ScreenshotDestinationDiscoveryReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var availableDestinations: [ScreenshotCaptureDestination]
    public var recommendedDestinations: [ScreenshotCaptureDestination]
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        availableDestinations: [ScreenshotCaptureDestination],
        recommendedDestinations: [ScreenshotCaptureDestination],
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.availableDestinations = availableDestinations
        self.recommendedDestinations = recommendedDestinations
        self.findings = findings
    }
}

public struct ScreenshotDestinationDiscoverer {
    public init() {}

    public func discover(simctlOutput: String, requestedPlatforms: [ApplePlatform]) -> ScreenshotDestinationDiscoveryReport {
        let available = parseAvailableDestinations(simctlOutput: simctlOutput)
        let requested = requestedPlatforms.isEmpty ? [.iOS] : requestedPlatforms
        let recommended = recommendedDestinations(from: available, requestedPlatforms: requested)
        var findings: [String] = []
        if available.isEmpty {
            findings.append("No available iOS simulators were discovered from simctl output.")
        }
        let missing = requested.filter { platform in
            platform == .iOS || platform == .iPadOS
        }.filter { platform in
            !recommended.contains { $0.platform == platform }
        }
        for platform in missing {
            findings.append("No recommended simulator destination found for \(platform.rawValue). Pass --destination explicitly or install a matching simulator.")
        }
        return ScreenshotDestinationDiscoveryReport(
            availableDestinations: available,
            recommendedDestinations: recommended,
            findings: findings
        )
    }

    private func parseAvailableDestinations(simctlOutput: String) -> [ScreenshotCaptureDestination] {
        simctlOutput
            .split(separator: "\n")
            .compactMap { rawLine -> ScreenshotCaptureDestination? in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix("iPhone ") || line.hasPrefix("iPad ") else {
                    return nil
                }
                guard let name = simulatorName(from: line) else {
                    return nil
                }
                let platform: ApplePlatform = name.hasPrefix("iPad ") ? .iPadOS : .iOS
                return ScreenshotCaptureDestination(
                    platform: platform,
                    name: name,
                    xcodebuildDestination: "platform=iOS Simulator,name=\(name)"
                )
            }
    }

    private func simulatorName(from line: String) -> String? {
        let withoutState = line.replacingOccurrences(
            of: #" \((Booted|Shutdown|Creating|Shutting Down)\)( .*)?$"#,
            with: "",
            options: .regularExpression
        )
        let withoutIdentifier = withoutState.replacingOccurrences(
            of: #" \([^()]+\)$"#,
            with: "",
            options: .regularExpression
        )
        let name = withoutIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func recommendedDestinations(
        from available: [ScreenshotCaptureDestination],
        requestedPlatforms: [ApplePlatform]
    ) -> [ScreenshotCaptureDestination] {
        var result: [ScreenshotCaptureDestination] = []
        if requestedPlatforms.contains(.iOS),
           let phone = preferredDestination(
               from: available,
               platform: .iOS,
               preferredNames: ["iPhone 17 Pro Max", "iPhone 16 Pro Max", "iPhone 15 Pro Max"]
           ) {
            result.append(phone)
        }
        if requestedPlatforms.contains(.iPadOS),
           let tablet = preferredDestination(
               from: available,
               platform: .iPadOS,
               preferredNames: ["iPad Pro 13-inch (M5)", "iPad Pro 13-inch (M4)", "iPad Pro 12.9-inch"]
           ) {
            result.append(tablet)
        }
        return result
    }

    private func preferredDestination(
        from available: [ScreenshotCaptureDestination],
        platform: ApplePlatform,
        preferredNames: [String]
    ) -> ScreenshotCaptureDestination? {
        let platformDestinations = available.filter { $0.platform == platform }
        for preferredName in preferredNames {
            if let destination = platformDestinations.first(where: { $0.name == preferredName }) {
                return destination
            }
        }
        return platformDestinations.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
        }.first
    }
}

public struct ScreenshotCaptureExecutionItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var commandID: String
    public var locale: String
    public var platform: ApplePlatform
    public var destinationName: String
    public var exitCode: Int32
    public var succeeded: Bool
    public var resultBundlePath: String
    public var rawOutputDirectory: String
    public var stdoutLogPath: String?
    public var stderrLogPath: String?
    public var outputFiles: [String]
    public var durationSeconds: Double

    public init(
        commandID: String,
        locale: String,
        platform: ApplePlatform,
        destinationName: String,
        exitCode: Int32,
        resultBundlePath: String,
        rawOutputDirectory: String,
        stdoutLogPath: String? = nil,
        stderrLogPath: String? = nil,
        outputFiles: [String] = [],
        durationSeconds: Double
    ) {
        self.commandID = commandID
        self.locale = locale
        self.platform = platform
        self.destinationName = destinationName
        self.exitCode = exitCode
        self.succeeded = exitCode == 0
        self.resultBundlePath = resultBundlePath
        self.rawOutputDirectory = rawOutputDirectory
        self.stdoutLogPath = stdoutLogPath
        self.stderrLogPath = stderrLogPath
        self.outputFiles = outputFiles
        self.durationSeconds = durationSeconds
        self.id = commandID
    }
}

public struct ScreenshotCaptureExecutionResult: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var ascendKitVersion: String?
    public var executed: Bool
    public var succeeded: Bool
    public var succeededCount: Int
    public var failedCount: Int
    public var items: [ScreenshotCaptureExecutionItem]
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        ascendKitVersion: String? = AscendKitVersion.current,
        executed: Bool,
        items: [ScreenshotCaptureExecutionItem] = [],
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.ascendKitVersion = ascendKitVersion
        self.executed = executed
        self.items = items
        self.findings = findings
        self.succeededCount = items.filter(\.succeeded).count
        self.failedCount = items.filter { !$0.succeeded }.count
        self.succeeded = executed && failedCount == 0 && findings.isEmpty
    }
}

public struct ScreenshotAttachmentImportResult: Equatable, Sendable {
    public var importedFiles: [String]
    public var findings: [String]

    public init(importedFiles: [String] = [], findings: [String] = []) {
        self.importedFiles = importedFiles
        self.findings = findings
    }
}

public struct ScreenshotAttachmentImporter {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func `import`(exportedAttachmentsDirectory: URL, rawOutputDirectory: URL) throws -> ScreenshotAttachmentImportResult {
        let manifestURL = exportedAttachmentsDirectory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return ScreenshotAttachmentImportResult(findings: ["No xcresult attachment manifest was generated."])
        }

        let suites = try JSONDecoder().decode(
            [XcresultAttachmentSuite].self,
            from: Data(contentsOf: manifestURL)
        )
        let attachments = suites.flatMap(\.attachments).sorted { lhs, rhs in
            lhs.timestamp < rhs.timestamp
        }
        try fileManager.createDirectory(at: rawOutputDirectory, withIntermediateDirectories: true)

        var importedFiles: [String] = []
        var usedNames = Set<String>()
        for attachment in attachments {
            let sourceURL = exportedAttachmentsDirectory.appendingPathComponent(attachment.exportedFileName)
            guard fileManager.fileExists(atPath: sourceURL.path),
                  let baseName = orderedScreenshotBaseName(from: attachment.suggestedHumanReadableName) else {
                continue
            }

            let pathExtension = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
            let uniqueBaseName = uniqueName(baseName, used: &usedNames)
            let destinationURL = rawOutputDirectory.appendingPathComponent("\(uniqueBaseName).\(pathExtension)")
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            importedFiles.append(destinationURL.path)
        }

        let findings = importedFiles.isEmpty
            ? ["No ordered screenshot attachments were found in xcresult. Name XCTest attachments like 01-home, 02-settings, etc."]
            : []
        return ScreenshotAttachmentImportResult(importedFiles: importedFiles.sorted(), findings: findings)
    }

    private func orderedScreenshotBaseName(from value: String) -> String? {
        let stem = URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let prefix = String(stem.unicodeScalars.prefix { allowed.contains($0) })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        guard prefix.count >= 4 else { return nil }

        let separatorIndex = prefix.index(prefix.startIndex, offsetBy: 2)
        guard prefix.prefix(2).allSatisfy(\.isNumber),
              prefix[separatorIndex] == "-" || prefix[separatorIndex] == "_" else {
            return nil
        }
        let nameStart = prefix.index(after: separatorIndex)
        let suffixStart = prefix[nameStart...].firstIndex(of: "_") ?? prefix.endIndex
        let baseName = String(prefix[..<suffixStart])
        return baseName.replacingOccurrences(of: "_", with: "-")
    }

    private func uniqueName(_ preferredName: String, used: inout Set<String>) -> String {
        if used.insert(preferredName).inserted {
            return preferredName
        }
        var index = 2
        while true {
            let candidate = "\(preferredName)-\(index)"
            if used.insert(candidate).inserted {
                return candidate
            }
            index += 1
        }
    }
}

private struct XcresultAttachmentSuite: Codable {
    var attachments: [XcresultAttachment]
}

private struct XcresultAttachment: Codable {
    var exportedFileName: String
    var suggestedHumanReadableName: String
    var timestamp: Double
}

public struct ScreenshotLocalWorkflowResult: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var ascendKitVersion: String?
    public var succeeded: Bool
    public var capturePlanPath: String
    public var captureResultPath: String
    public var importManifestPath: String?
    public var compositionManifestPath: String?
    public var compositionMode: ScreenshotCompositionMode?
    public var capturedFileCount: Int
    public var composedArtifactCount: Int
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        ascendKitVersion: String? = AscendKitVersion.current,
        succeeded: Bool,
        capturePlanPath: String,
        captureResultPath: String,
        importManifestPath: String? = nil,
        compositionManifestPath: String? = nil,
        compositionMode: ScreenshotCompositionMode? = nil,
        capturedFileCount: Int = 0,
        composedArtifactCount: Int = 0,
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.ascendKitVersion = ascendKitVersion
        self.succeeded = succeeded
        self.capturePlanPath = capturePlanPath
        self.captureResultPath = captureResultPath
        self.importManifestPath = importManifestPath
        self.compositionManifestPath = compositionManifestPath
        self.compositionMode = compositionMode
        self.capturedFileCount = capturedFileCount
        self.composedArtifactCount = composedArtifactCount
        self.findings = findings
    }
}

public enum ScreenshotWorkflowStepState: String, Codable, Equatable, Sendable {
    case complete
    case missing
    case blocked
}

public struct ScreenshotWorkflowStepStatus: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var state: ScreenshotWorkflowStepState
    public var detail: String?
    public var path: String?

    public init(
        id: String,
        title: String,
        state: ScreenshotWorkflowStepState,
        detail: String? = nil,
        path: String? = nil
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.detail = detail
        self.path = path
    }
}

public struct ScreenshotWorkflowStatusReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var ascendKitVersion: String?
    public var readyForUploadPlan: Bool
    public var steps: [ScreenshotWorkflowStepStatus]
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        ascendKitVersion: String? = AscendKitVersion.current,
        steps: [ScreenshotWorkflowStepStatus],
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.ascendKitVersion = ascendKitVersion
        self.steps = steps
        self.findings = findings
        self.readyForUploadPlan = steps.allSatisfy { $0.state == .complete } && findings.isEmpty
    }
}

public struct ScreenshotWorkflowStatusBuilder {
    public init() {}

    public func build(
        capturePlan: ScreenshotCapturePlan?,
        captureResult: ScreenshotCaptureExecutionResult?,
        importManifest: ScreenshotImportManifest?,
        copyLintReport: ScreenshotCompositionCopyLintReport? = nil,
        compositionManifest: ScreenshotCompositionManifest?,
        workflowResult: ScreenshotLocalWorkflowResult?,
        uploadPlan: ScreenshotUploadPlan? = nil,
        paths: ReleaseWorkspacePaths? = nil
    ) -> ScreenshotWorkflowStatusReport {
        var findings: [String] = []
        var steps: [ScreenshotWorkflowStepStatus] = []

        steps.append(.init(
            id: "capture-plan",
            title: "Capture plan",
            state: capturePlan == nil ? .missing : (capturePlan?.findings.isEmpty == true ? .complete : .blocked),
            detail: capturePlan.map { "\($0.commands.count) command(s), \($0.destinations.count) destination(s)" },
            path: paths?.screenshotCapturePlan
        ))

        if let capturePlan, !capturePlan.findings.isEmpty {
            findings.append(contentsOf: capturePlan.findings)
        }

        let captureState: ScreenshotWorkflowStepState
        if let captureResult {
            captureState = captureResult.succeeded ? .complete : .blocked
            findings.append(contentsOf: captureResult.findings)
        } else {
            captureState = .missing
        }
        steps.append(.init(
            id: "capture-result",
            title: "Capture execution",
            state: captureState,
            detail: captureResult.map { "\($0.succeededCount) succeeded, \($0.failedCount) failed" },
            path: paths?.screenshotCaptureResult
        ))

        steps.append(.init(
            id: "import-manifest",
            title: "Import manifest",
            state: importManifest == nil ? .missing : (importManifest?.artifacts.isEmpty == false ? .complete : .blocked),
            detail: importManifest.map { "\($0.artifacts.count) artifact(s)" },
            path: paths?.screenshotImportManifest
        ))
        if importManifest?.artifacts.isEmpty == true {
            findings.append("Screenshot import manifest has no artifacts.")
        }

        if let copyLintReport {
            steps.append(.init(
                id: "copy-lint",
                title: "Copy lint",
                state: copyLintReport.valid ? .complete : .blocked,
                detail: "\(copyLintReport.copyItemCount) copy item(s), \(copyLintReport.findings.count) finding(s)",
                path: paths?.screenshotCopyLint
            ))
            findings.append(contentsOf: copyLintReport.findings)
        }

        steps.append(.init(
            id: "composition-manifest",
            title: "Composition manifest",
            state: compositionManifest == nil ? .missing : (compositionManifest?.artifacts.isEmpty == false ? .complete : .blocked),
            detail: compositionManifest.map { "\($0.artifacts.count) artifact(s), mode \($0.mode.rawValue)" },
            path: paths?.screenshotCompositionManifest
        ))
        if compositionManifest?.artifacts.isEmpty == true {
            findings.append("Screenshot composition manifest has no artifacts.")
        }

        steps.append(.init(
            id: "workflow-result",
            title: "Local workflow result",
            state: workflowResult == nil ? .missing : (workflowResult?.succeeded == true ? .complete : .blocked),
            detail: workflowResult.map { "\($0.capturedFileCount) captured, \($0.composedArtifactCount) composed" },
            path: paths?.screenshotWorkflowResult
        ))
        if let workflowResult, !workflowResult.succeeded {
            findings.append(contentsOf: workflowResult.findings)
        }

        if let uploadPlan {
            steps.append(.init(
                id: "upload-plan",
                title: "Upload plan",
                state: uploadPlan.findings.isEmpty ? .complete : .blocked,
                detail: "\(uploadPlan.items.count) item(s), \(uploadPlan.findings.count) finding(s)",
                path: paths?.screenshotUploadPlan
            ))
            findings.append(contentsOf: uploadPlan.findings)
        }

        return ScreenshotWorkflowStatusReport(steps: steps, findings: findings)
    }
}

public struct ScreenshotCaptureExecutor {
    public let fileManager: FileManager
    private let simulatorBusyRetryLimit = 2
    private let simulatorBusyRetryDelaySeconds: TimeInterval = 5

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func execute(
        plan: ScreenshotCapturePlan,
        logsDirectory: URL,
        cleanOutputDirectories: Bool = true
    ) throws -> ScreenshotCaptureExecutionResult {
        guard plan.findings.isEmpty else {
            return ScreenshotCaptureExecutionResult(
                executed: false,
                findings: plan.findings.map { "Capture plan is not executable: \($0)" }
            )
        }
        guard !plan.commands.isEmpty else {
            return ScreenshotCaptureExecutionResult(
                executed: false,
                findings: ["Capture plan has no commands."]
            )
        }

        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        var items: [ScreenshotCaptureExecutionItem] = []
        for command in plan.commands {
            items.append(try execute(
                command: command,
                logsDirectory: logsDirectory,
                cleanOutputDirectory: cleanOutputDirectories
            ))
        }

        let failed = items.filter { !$0.succeeded }
        var findings = failed.map {
            "Capture command \($0.commandID) failed with exit code \($0.exitCode). See \($0.stderrLogPath ?? "stderr log")."
        }
        findings.append(contentsOf: items.filter(\.succeeded).filter(\.outputFiles.isEmpty).map {
            "Capture command \($0.commandID) completed but produced no screenshot files in \($0.rawOutputDirectory)."
        })
        return ScreenshotCaptureExecutionResult(executed: true, items: items, findings: findings)
    }

    private func execute(
        command: ScreenshotCaptureCommand,
        logsDirectory: URL,
        cleanOutputDirectory: Bool
    ) throws -> ScreenshotCaptureExecutionItem {
        let rawOutputURL = URL(fileURLWithPath: command.rawOutputDirectory)
        if cleanOutputDirectory && fileManager.fileExists(atPath: rawOutputURL.path) {
            try fileManager.removeItem(at: rawOutputURL)
        }
        try fileManager.createDirectory(at: rawOutputURL, withIntermediateDirectories: true)
        try writeFastlaneSnapshotConfigurationIfNeeded(
            locale: command.locale,
            commandEnvironment: command.environment
        )
        let resultBundleURL = URL(fileURLWithPath: command.resultBundlePath)
        if fileManager.fileExists(atPath: resultBundleURL.path) {
            try fileManager.removeItem(at: resultBundleURL)
        }
        try fileManager.createDirectory(
            at: resultBundleURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let stdoutURL = logsDirectory.appendingPathComponent("\(safeFileName(command.id)).stdout.log")
        let stderrURL = logsDirectory.appendingPathComponent("\(safeFileName(command.id)).stderr.log")
        let start = Date()
        let exitCode: Int32

        if command.command.isEmpty {
            try Data("Capture command is empty.\n".utf8).write(to: stderrURL, options: [.atomic])
            exitCode = 127
        } else {
            exitCode = try runCaptureProcessWithRetries(
                command: command,
                resultBundleURL: resultBundleURL,
                rawOutputURL: rawOutputURL,
                stdoutURL: stdoutURL,
                stderrURL: stderrURL,
                cleanOutputDirectory: cleanOutputDirectory
            )
        }

        var outputFiles = cleanOutputDirectory
            ? imageFiles(in: rawOutputURL, modifiedSince: start).map(\.path)
            : imageFiles(in: rawOutputURL).map(\.path)
        if exitCode == 0 && outputFiles.isEmpty {
            outputFiles = try importOrderedAttachmentsIfPresent(
                resultBundleURL: resultBundleURL,
                rawOutputDirectory: rawOutputURL,
                logsDirectory: logsDirectory,
                commandID: command.id,
                modifiedSince: start
            )
        }
        if exitCode == 0 && outputFiles.isEmpty {
            outputFiles = try importFastlaneScreenshotsIfPresent(
                rawOutputDirectory: rawOutputURL,
                commandEnvironment: command.environment,
                modifiedSince: start
            )
        }

        return ScreenshotCaptureExecutionItem(
            commandID: command.id,
            locale: command.locale,
            platform: command.platform,
            destinationName: command.destinationName,
            exitCode: exitCode,
            resultBundlePath: command.resultBundlePath,
            rawOutputDirectory: command.rawOutputDirectory,
            stdoutLogPath: stdoutURL.path,
            stderrLogPath: stderrURL.path,
            outputFiles: outputFiles,
            durationSeconds: Date().timeIntervalSince(start)
        )
    }

    private func runCaptureProcessWithRetries(
        command: ScreenshotCaptureCommand,
        resultBundleURL: URL,
        rawOutputURL: URL,
        stdoutURL: URL,
        stderrURL: URL,
        cleanOutputDirectory: Bool
    ) throws -> Int32 {
        var attempt = 0
        while true {
            let exitCode = try runProcess(
                command: command.command,
                environment: command.environment,
                stdoutURL: stdoutURL,
                stderrURL: stderrURL
            )
            guard shouldRetryForSimulatorBusy(
                exitCode: exitCode,
                stderrURL: stderrURL,
                attempt: attempt
            ) else {
                return exitCode
            }

            attempt += 1
            try appendRetryNote(
                "AscendKit retrying capture command \(command.id) after transient simulator busy failure (attempt \(attempt + 1) of \(simulatorBusyRetryLimit + 1)).\n",
                to: stderrURL
            )
            Thread.sleep(forTimeInterval: simulatorBusyRetryDelaySeconds)
            try prepareRetryDirectories(
                resultBundleURL: resultBundleURL,
                rawOutputURL: rawOutputURL,
                cleanOutputDirectory: cleanOutputDirectory
            )
        }
    }

    private func shouldRetryForSimulatorBusy(
        exitCode: Int32,
        stderrURL: URL,
        attempt: Int
    ) -> Bool {
        guard exitCode == 65, attempt < simulatorBusyRetryLimit else {
            return false
        }
        guard let stderr = try? String(contentsOf: stderrURL, encoding: .utf8) else {
            return false
        }
        let normalized = stderr.lowercased()
        return normalized.contains("application failed preflight checks") ||
            normalized.contains("bserrorcodedescription = busy") ||
            normalized.contains("reason: busy")
    }

    private func prepareRetryDirectories(
        resultBundleURL: URL,
        rawOutputURL: URL,
        cleanOutputDirectory: Bool
    ) throws {
        if fileManager.fileExists(atPath: resultBundleURL.path) {
            try fileManager.removeItem(at: resultBundleURL)
        }
        try fileManager.createDirectory(
            at: resultBundleURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if cleanOutputDirectory {
            if fileManager.fileExists(atPath: rawOutputURL.path) {
                try fileManager.removeItem(at: rawOutputURL)
            }
            try fileManager.createDirectory(at: rawOutputURL, withIntermediateDirectories: true)
        }
    }

    private func appendRetryNote(_ note: String, to url: URL) throws {
        let existing = (try? Data(contentsOf: url)) ?? Data()
        var updated = existing
        updated.append(Data(note.utf8))
        try updated.write(to: url, options: [.atomic])
    }

    private func importOrderedAttachmentsIfPresent(
        resultBundleURL: URL,
        rawOutputDirectory: URL,
        logsDirectory: URL,
        commandID: String,
        modifiedSince start: Date
    ) throws -> [String] {
        guard fileManager.fileExists(atPath: resultBundleURL.path) else {
            return []
        }

        let attachmentsDirectory = logsDirectory.appendingPathComponent("\(safeFileName(commandID)).attachments")
        if fileManager.fileExists(atPath: attachmentsDirectory.path) {
            try fileManager.removeItem(at: attachmentsDirectory)
        }
        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)

        let exportExitCode = try runProcess(
            command: [
                "xcrun",
                "xcresulttool",
                "export",
                "attachments",
                "--path",
                resultBundleURL.path,
                "--output-path",
                attachmentsDirectory.path
            ],
            environment: [:],
            stdoutURL: logsDirectory.appendingPathComponent("\(safeFileName(commandID)).attachments.stdout.log"),
            stderrURL: logsDirectory.appendingPathComponent("\(safeFileName(commandID)).attachments.stderr.log")
        )
        guard exportExitCode == 0 else {
            return []
        }

        let result = try ScreenshotAttachmentImporter(fileManager: fileManager).import(
            exportedAttachmentsDirectory: attachmentsDirectory,
            rawOutputDirectory: rawOutputDirectory
        )
        guard result.findings.isEmpty else {
            return []
        }
        return imageFiles(in: rawOutputDirectory, modifiedSince: start).map(\.path)
    }

    private func importFastlaneScreenshotsIfPresent(
        rawOutputDirectory: URL,
        commandEnvironment: [String: String],
        modifiedSince start: Date
    ) throws -> [String] {
        guard let sourceDirectory = fastlaneScreenshotsDirectory(commandEnvironment: commandEnvironment),
              fileManager.fileExists(atPath: sourceDirectory.path) else {
            return []
        }

        let sourceFiles = imageFiles(in: sourceDirectory, modifiedSince: start)
        guard !sourceFiles.isEmpty else {
            return []
        }

        try fileManager.createDirectory(at: rawOutputDirectory, withIntermediateDirectories: true)
        var importedFiles: [String] = []
        for sourceURL in sourceFiles {
            let destinationURL = rawOutputDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            importedFiles.append(destinationURL.path)
        }
        return importedFiles.sorted()
    }

    private func fastlaneScreenshotsDirectory(commandEnvironment: [String: String]) -> URL? {
        if let override = commandEnvironment["ASCENDKIT_FASTLANE_SCREENSHOTS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent("Library/Caches/tools.fastlane/screenshots", isDirectory: true)
        }
        return nil
    }

    private func writeFastlaneSnapshotConfigurationIfNeeded(
        locale: String,
        commandEnvironment: [String: String]
    ) throws {
        guard let cacheDirectory = fastlaneCacheDirectory(commandEnvironment: commandEnvironment) else {
            return
        }
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try Data(locale.utf8).write(
            to: cacheDirectory.appendingPathComponent("language.txt"),
            options: [.atomic]
        )
        try Data(locale.utf8).write(
            to: cacheDirectory.appendingPathComponent("locale.txt"),
            options: [.atomic]
        )
    }

    private func fastlaneCacheDirectory(commandEnvironment: [String: String]) -> URL? {
        if let override = commandEnvironment["ASCENDKIT_FASTLANE_CACHE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent("Library/Caches/tools.fastlane", isDirectory: true)
        }
        return nil
    }

    private func runProcess(command: [String], environment: [String: String], stdoutURL: URL, stderrURL: URL) throws -> Int32 {
        let process = Process()
        if command[0].contains("/") {
            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command
        }
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        do {
            try process.run()
            process.waitUntilExit()
            try stdoutHandle.close()
            try stderrHandle.close()
            return process.terminationStatus
        } catch {
            let message = "Failed to launch capture command: \(error)\n"
            try? stderrHandle.write(contentsOf: Data(message.utf8))
            try stdoutHandle.close()
            try stderrHandle.close()
            return 127
        }
    }

    private func imageFiles(in directory: URL, modifiedSince start: Date) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]) else {
            return []
        }
        let supported = Set(["png", "jpg", "jpeg", "heic", "tif", "tiff"])
        return contents
            .filter { url in
                guard supported.contains(url.pathExtension.lowercased()) else {
                    return false
                }
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return modified.map { $0 >= start } ?? true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func imageFiles(in directory: URL) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        let supported = Set(["png", "jpg", "jpeg", "heic", "tif", "tiff"])
        return contents
            .filter { supported.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return value.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
    }
}

public struct ScreenshotCapturePlanBuilder {
    public init() {}

    public func build(
        manifest: ReleaseManifest,
        screenshotPlan: ScreenshotPlan,
        workspaceRoot: URL,
        scheme: String? = nil,
        configuration: String = "Debug",
        destinationOverrides: [String] = [],
        onlyTesting: [String] = [],
        discoveredDestinations: [ScreenshotCaptureDestination] = []
    ) -> ScreenshotCapturePlan {
        var findings: [String] = []
        let projectReference = preferredProjectReference(from: manifest.projects)
        if projectReference == nil {
            findings.append("No .xcworkspace or .xcodeproj was found in the release manifest.")
        }

        let effectiveScheme = scheme ?? manifest.targets.first(where: \.isAppStoreApplication)?.name
        if effectiveScheme == nil {
            findings.append("No scheme was supplied and no App Store application target was found to use as the default scheme.")
        }

        let destinations = destinationOverrides.isEmpty
            ? defaultDestinations(for: screenshotPlan.platforms, discoveredDestinations: discoveredDestinations)
            : destinationOverrides.map(parseDestination)
        if destinations.isEmpty {
            findings.append("No screenshot capture destinations were supplied or inferred.")
        }

        let locales = screenshotPlan.locales.isEmpty ? ["en-US"] : screenshotPlan.locales
        let rawRoot = workspaceRoot.appendingPathComponent("screenshots/raw")
        let resultRoot = workspaceRoot.appendingPathComponent("screenshots/capture/xcresult")
        let projectPath = projectReference?.kind == .xcodeproj ? projectReference?.path : nil
        let xcodeWorkspacePath = projectReference?.kind == .xcworkspace ? projectReference?.path : nil
        let schemeValue = effectiveScheme ?? ""

        let commands = destinations.flatMap { destination in
            locales.map { locale in
                let rawOutputDirectory = rawRoot
                    .appendingPathComponent(locale)
                    .appendingPathComponent(destination.platform.rawValue)
                let resultBundlePath = resultRoot
                    .appendingPathComponent(locale)
                    .appendingPathComponent(safeFileName(destination.name))
                    .appendingPathExtension("xcresult")
                let environment = [
                    "ASCENDKIT_SCREENSHOT_OUTPUT_DIR": rawOutputDirectory.path,
                    "ASCENDKIT_SCREENSHOT_LOCALE": locale
                ]
                return ScreenshotCaptureCommand(
                    locale: locale,
                    platform: destination.platform,
                    destinationName: destination.name,
                    resultBundlePath: resultBundlePath.path,
                    rawOutputDirectory: rawOutputDirectory.path,
                    environment: environment,
                    command: makeCommand(
                        projectReference: projectReference,
                        scheme: schemeValue,
                        configuration: configuration,
                        locale: locale,
                        destination: destination,
                        onlyTesting: onlyTesting,
                        resultBundlePath: resultBundlePath
                    )
                )
            }
        }

        return ScreenshotCapturePlan(
            scheme: schemeValue,
            projectPath: projectPath,
            workspacePath: xcodeWorkspacePath,
            configuration: configuration,
            destinations: destinations,
            locales: locales,
            commands: commands,
            findings: findings
        )
    }

    private func preferredProjectReference(from projects: [ProjectReference]) -> ProjectReference? {
        projects.first { $0.kind == .xcworkspace } ?? projects.first { $0.kind == .xcodeproj }
    }

    private func defaultDestinations(
        for platforms: [ApplePlatform],
        discoveredDestinations: [ScreenshotCaptureDestination]
    ) -> [ScreenshotCaptureDestination] {
        if !discoveredDestinations.isEmpty {
            return discoveredDestinations
        }
        var seen: [ApplePlatform] = []
        for platform in platforms where !seen.contains(platform) {
            seen.append(platform)
        }
        let uniquePlatforms = seen.sorted { $0.rawValue < $1.rawValue }
        return uniquePlatforms.compactMap { platform in
            switch platform {
            case .iOS:
                return ScreenshotCaptureDestination(
                    platform: .iOS,
                    name: "iPhone 17 Pro Max",
                    xcodebuildDestination: "platform=iOS Simulator,name=iPhone 17 Pro Max"
                )
            case .iPadOS:
                return ScreenshotCaptureDestination(
                    platform: .iPadOS,
                    name: "iPad Pro 13-inch (M5)",
                    xcodebuildDestination: "platform=iOS Simulator,name=iPad Pro 13-inch (M5)"
                )
            case .macOS:
                return ScreenshotCaptureDestination(
                    platform: .macOS,
                    name: "Mac",
                    xcodebuildDestination: "platform=macOS"
                )
            default:
                return nil
            }
        }
    }

    private func parseDestination(_ rawValue: String) -> ScreenshotCaptureDestination {
        let name = destinationComponent(named: "name", in: rawValue)
            ?? destinationComponent(named: "platform", in: rawValue)
            ?? rawValue
        return ScreenshotCaptureDestination(
            platform: inferPlatform(from: rawValue),
            name: name,
            xcodebuildDestination: rawValue
        )
    }

    private func inferPlatform(from destination: String) -> ApplePlatform {
        if destination.localizedCaseInsensitiveContains("iphone") {
            return .iOS
        }
        if destination.localizedCaseInsensitiveContains("ipad") {
            return .iPadOS
        }
        if destination.localizedCaseInsensitiveContains("macos") {
            return .macOS
        }
        return .unknown
    }

    private func destinationComponent(named name: String, in destination: String) -> String? {
        destination
            .split(separator: ",")
            .compactMap { component -> String? in
                let parts = component.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count == 2, parts[0] == name else { return nil }
                return parts[1]
            }
            .first
    }

    private func makeCommand(
        projectReference: ProjectReference?,
        scheme: String,
        configuration: String,
        locale: String,
        destination: ScreenshotCaptureDestination,
        onlyTesting: [String],
        resultBundlePath: URL
    ) -> [String] {
        var command = ["xcodebuild"]
        if let projectReference {
            switch projectReference.kind {
            case .xcworkspace:
                command.append(contentsOf: ["-workspace", projectReference.path])
            case .xcodeproj:
                command.append(contentsOf: ["-project", projectReference.path])
            }
        }
        command.append(contentsOf: [
            "-scheme", scheme,
            "-configuration", configuration,
            "-destination", destination.xcodebuildDestination,
            "-resultBundlePath", resultBundlePath.path
        ])
        if let language = localeLanguage(locale) {
            command.append(contentsOf: ["-testLanguage", language])
        }
        if let region = localeRegion(locale) {
            command.append(contentsOf: ["-testRegion", region])
        }
        for testIdentifier in onlyTesting where !testIdentifier.isEmpty {
            command.append(contentsOf: ["-only-testing:\(testIdentifier)"])
        }
        command.append("test")
        return command
    }

    private func localeLanguage(_ locale: String) -> String? {
        let parts = locale.split(separator: "-").map(String.init)
        guard let language = parts.first else { return nil }
        guard let script = parts.dropFirst().first, isScriptSubtag(script) else {
            return language
        }
        return "\(language)-\(script)"
    }

    private func localeRegion(_ locale: String) -> String? {
        locale.split(separator: "-")
            .dropFirst()
            .map(String.init)
            .first(where: isRegionSubtag)
    }

    private func isScriptSubtag(_ value: String) -> Bool {
        value.count == 4 && value.allSatisfy(\.isLetter)
    }

    private func isRegionSubtag(_ value: String) -> Bool {
        (value.count == 2 && value.allSatisfy(\.isLetter)) ||
            (value.count == 3 && value.allSatisfy(\.isNumber))
    }

    private func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        return scalars.joined().split(separator: "-").joined(separator: "-")
    }
}

public enum ScreenshotDoctorSeverity: String, Codable, Equatable, Sendable {
    case blocker
    case warning
    case info
}

public struct ScreenshotDoctorFinding: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var severity: ScreenshotDoctorSeverity
    public var title: String
    public var detail: String
    public var nextAction: String

    public init(
        id: String,
        severity: ScreenshotDoctorSeverity,
        title: String,
        detail: String,
        nextAction: String
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.nextAction = nextAction
    }
}

public struct ScreenshotPlatformSupport: Codable, Equatable, Sendable {
    public var platform: ApplePlatform
    public var deterministicCapture: String
    public var defaultDestination: String?
    public var appStoreDisplayType: String
    public var compositionSupport: String
    public var notes: [String]

    public init(
        platform: ApplePlatform,
        deterministicCapture: String,
        defaultDestination: String?,
        appStoreDisplayType: String,
        compositionSupport: String,
        notes: [String]
    ) {
        self.platform = platform
        self.deterministicCapture = deterministicCapture
        self.defaultDestination = defaultDestination
        self.appStoreDisplayType = appStoreDisplayType
        self.compositionSupport = compositionSupport
        self.notes = notes
    }
}

public struct ScreenshotDoctorReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var readyForDeterministicCapture: Bool
    public var projectReference: ProjectReference?
    public var appTargetName: String?
    public var uiTestTargetNames: [String]
    public var platforms: [ApplePlatform]
    public var locales: [String]
    public var recommendedDestinations: [ScreenshotCaptureDestination]
    public var platformSupport: [ScreenshotPlatformSupport]
    public var screenshotPlanPresent: Bool
    public var nextCommands: [String]
    public var findings: [ScreenshotDoctorFinding]
    public var uiTestGuidance: [String]
    public var uiTestAgentPrompt: String
    public var ascendKitVersion: String?

    public init(
        generatedAt: Date = Date(),
        projectReference: ProjectReference?,
        appTargetName: String?,
        uiTestTargetNames: [String],
        platforms: [ApplePlatform],
        locales: [String],
        recommendedDestinations: [ScreenshotCaptureDestination],
        screenshotPlanPresent: Bool,
        nextCommands: [String],
        findings: [ScreenshotDoctorFinding],
        ascendKitVersion: String? = AscendKitVersion.current
    ) {
        self.generatedAt = generatedAt
        self.projectReference = projectReference
        self.appTargetName = appTargetName
        self.uiTestTargetNames = uiTestTargetNames
        self.platforms = platforms
        self.locales = locales
        self.recommendedDestinations = recommendedDestinations
        self.platformSupport = Self.buildPlatformSupport(for: platforms)
        self.screenshotPlanPresent = screenshotPlanPresent
        self.nextCommands = nextCommands
        self.findings = findings
        self.uiTestGuidance = [
            "Use UI Tests for repeatable screenshots when manual screenshots are missing or stale.",
            "Launch the app with screenshot-specific arguments such as --ascendkit-screenshot-mode.",
            "Use deterministic fixtures or mock data; never use real user credentials.",
            "Write raw screenshots to ASCENDKIT_SCREENSHOT_OUTPUT_DIR when possible, or attach ordered XCTest screenshots for xcresult import.",
            "Keep manual screenshot import as a fallback when UI Test capture is not practical yet."
        ]
        self.uiTestAgentPrompt = "Use AscendKit to create deterministic App Store screenshots. Prefer UI Tests with stable launch arguments, mock data, ordered screenshot names, and no real credentials. If no UI test target exists, scaffold one before running screenshots capture-plan."
        self.readyForDeterministicCapture = !findings.contains { $0.severity == .blocker }
        self.ascendKitVersion = ascendKitVersion
    }

    private static func buildPlatformSupport(for platforms: [ApplePlatform]) -> [ScreenshotPlatformSupport] {
        let requestedPlatforms = platforms.filter { $0 != .unknown }
        let matrixPlatforms = requestedPlatforms.isEmpty
            ? ApplePlatform.allCases.filter { $0 != .unknown }
            : requestedPlatforms
        return matrixPlatforms.map { platform in
            switch platform {
            case .iOS:
                return ScreenshotPlatformSupport(
                    platform: .iOS,
                    deterministicCapture: "default-supported",
                    defaultDestination: "platform=iOS Simulator,name=iPhone 17 Pro Max",
                    appStoreDisplayType: "APP_IPHONE_67",
                    compositionSupport: "storeReadyCopy, poster, generic deviceFrame, framedPoster",
                    notes: ["Best-supported path for UI-test screenshot capture and framed marketing screenshots."]
                )
            case .iPadOS:
                return ScreenshotPlatformSupport(
                    platform: .iPadOS,
                    deterministicCapture: "default-supported",
                    defaultDestination: "platform=iOS Simulator,name=iPad Pro 13-inch (M5)",
                    appStoreDisplayType: "APP_IPAD_PRO_3GEN_129",
                    compositionSupport: "storeReadyCopy, poster, generic deviceFrame, framedPoster",
                    notes: ["Uses iOS Simulator destinations with iPad device names."]
                )
            case .macOS:
                return ScreenshotPlatformSupport(
                    platform: .macOS,
                    deterministicCapture: "default-supported",
                    defaultDestination: "platform=macOS",
                    appStoreDisplayType: "APP_DESKTOP",
                    compositionSupport: "storeReadyCopy, poster, generic deviceFrame, framedPoster",
                    notes: ["Capture can run against the macOS destination when the scheme supports UI testing."]
                )
            case .tvOS:
                return ScreenshotPlatformSupport(
                    platform: .tvOS,
                    deterministicCapture: "explicit-destination-required",
                    defaultDestination: nil,
                    appStoreDisplayType: "APP_APPLE_TV",
                    compositionSupport: "storeReadyCopy, poster, generic deviceFrame, framedPoster",
                    notes: ["Run screenshots destinations and pass a tvOS Simulator destination, or import manually until the project has deterministic UI Tests."]
                )
            case .watchOS:
                return ScreenshotPlatformSupport(
                    platform: .watchOS,
                    deterministicCapture: "explicit-destination-required",
                    defaultDestination: "platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)",
                    appStoreDisplayType: "APP_WATCH_ULTRA",
                    compositionSupport: "storeReadyCopy, poster, generic deviceFrame, framedPoster",
                    notes: ["Watch screenshots often need app-specific host app and simulator setup; use explicit destinations or manual import."]
                )
            case .visionOS:
                return ScreenshotPlatformSupport(
                    platform: .visionOS,
                    deterministicCapture: "explicit-destination-required",
                    defaultDestination: nil,
                    appStoreDisplayType: "APP_VISION_PRO",
                    compositionSupport: "storeReadyCopy, poster, generic deviceFrame, framedPoster",
                    notes: ["Use a discovered visionOS Simulator destination before capture-plan; manual import remains supported."]
                )
            case .unknown:
                return ScreenshotPlatformSupport(
                    platform: .unknown,
                    deterministicCapture: "unsupported-until-platform-is-known",
                    defaultDestination: nil,
                    appStoreDisplayType: "APP_IPHONE_67",
                    compositionSupport: "manual import only",
                    notes: ["Rerun intake or screenshot planning with a concrete Apple platform."]
                )
            }
        }
    }
}

public struct ScreenshotDoctor {
    public init() {}

    public func diagnose(
        manifest: ReleaseManifest,
        screenshotPlan: ScreenshotPlan?,
        recommendedDestinations: [ScreenshotCaptureDestination] = []
    ) -> ScreenshotDoctorReport {
        let projectReference = manifest.projects.first { $0.kind == .xcworkspace } ?? manifest.projects.first
        let appTarget = manifest.targets.first(where: \.isAppStoreApplication)
        let uiTestTargets = manifest.targets.filter { target in
            target.productType?.contains("ui-testing") == true || target.name.localizedCaseInsensitiveContains("UITests")
        }
        let platforms = normalizedPlatforms(
            screenshotPlan?.platforms ?? manifest.targets.map(\.platform).filter { $0 != .unknown }
        )
        let locales = screenshotPlan?.locales.isEmpty == false ? screenshotPlan?.locales ?? ["en-US"] : ["en-US"]
        var findings: [ScreenshotDoctorFinding] = []

        if projectReference == nil {
            findings.append(.init(
                id: "screenshots.doctor.project.missing",
                severity: .blocker,
                title: "No Xcode project or workspace found",
                detail: "AscendKit needs an .xcodeproj or .xcworkspace reference before it can plan UI-test-driven screenshot capture.",
                nextAction: "Run intake inspect --workspace PATH --save from the app project root, then rerun screenshots doctor."
            ))
        }

        if appTarget == nil {
            findings.append(.init(
                id: "screenshots.doctor.app-target.missing",
                severity: .blocker,
                title: "No App Store application target found",
                detail: "Screenshot capture needs a runnable application scheme.",
                nextAction: "Confirm the app target is discoverable, then rerun intake inspect --workspace PATH --save."
            ))
        }

        if uiTestTargets.isEmpty {
            findings.append(.init(
                id: "screenshots.doctor.uitest-target.missing",
                severity: .blocker,
                title: "No UI test target detected",
                detail: "Manual screenshot import can still work, but deterministic screenshot capture requires UI Tests.",
                nextAction: "Create a UI test target or run screenshots scaffold-uitests --workspace PATH --json, review the generated file, add it to the UI test target, then run screenshots capture-plan."
            ))
        }

        if screenshotPlan == nil {
            findings.append(.init(
                id: "screenshots.doctor.plan.missing",
                severity: .blocker,
                title: "No screenshot plan found",
                detail: "A screenshot plan defines platforms, locales, ordered screens, and marketing intent before deterministic capture.",
                nextAction: "Run screenshots plan --workspace PATH --screens Home,Feature,Paywall --features A,B --platforms iOS,iPadOS --locales en-US --json."
            ))
        }

        if platforms.isEmpty {
            findings.append(.init(
                id: "screenshots.doctor.platforms.missing",
                severity: .warning,
                title: "No screenshot platform matrix found",
                detail: "AscendKit could not infer target platforms from the manifest or screenshot plan.",
                nextAction: "Run screenshots plan with --platforms iOS,iPadOS or the correct platform list for this app."
            ))
        }

        if recommendedDestinations.isEmpty {
            findings.append(.init(
                id: "screenshots.doctor.destinations.missing",
                severity: .warning,
                title: "No simulator destinations discovered",
                detail: "Capture can still be planned with explicit --destination values, but automatic recommendations are unavailable.",
                nextAction: "Run screenshots destinations --workspace PATH --json or pass --destination to screenshots capture-plan."
            ))
        }

        if !uiTestTargets.isEmpty {
            findings.append(.init(
                id: "screenshots.doctor.uitest-target.present",
                severity: .info,
                title: "UI test target detected",
                detail: "Detected UI test target(s): \(uiTestTargets.map(\.name).joined(separator: ", ")).",
                nextAction: "Use launch arguments and ASCENDKIT_SCREENSHOT_OUTPUT_DIR in UI Tests, then run screenshots capture-plan."
            ))
        }

        var nextCommands = [
            "screenshots plan --workspace PATH --screens Home,Feature,Paywall --features A,B --platforms iOS,iPadOS --locales en-US --json",
            "screenshots destinations --workspace PATH --json"
        ]
        if uiTestTargets.isEmpty {
            nextCommands.append("screenshots scaffold-uitests --workspace PATH --json")
        }
        nextCommands.append(contentsOf: [
            "screenshots capture-plan --workspace PATH --json",
            "screenshots capture --workspace PATH --json",
            "screenshots compose --workspace PATH --mode framedPoster --json"
        ])

        return ScreenshotDoctorReport(
            projectReference: projectReference,
            appTargetName: appTarget?.name,
            uiTestTargetNames: uiTestTargets.map(\.name).sorted(),
            platforms: platforms,
            locales: locales,
            recommendedDestinations: recommendedDestinations,
            screenshotPlanPresent: screenshotPlan != nil,
            nextCommands: nextCommands,
            findings: findings
        )
    }

    private func normalizedPlatforms(_ platforms: [ApplePlatform]) -> [ApplePlatform] {
        var result: [ApplePlatform] = []
        for platform in platforms where platform != .unknown && !result.contains(platform) {
            result.append(platform)
        }
        return result.sorted { $0.rawValue < $1.rawValue }
    }
}

public struct ScreenshotUITestScaffoldResult: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var swiftFilePath: String
    public var appTargetName: String?
    public var uiTestTargetNames: [String]
    public var screenCount: Int
    public var launchArguments: [String]
    public var environmentKeys: [String]
    public var navigationPlaceholders: [ScreenshotUITestNavigationPlaceholder]
    public var instructions: [String]
    public var agentPrompt: String
    public var swiftSource: String
    public var ascendKitVersion: String?

    public init(
        generatedAt: Date = Date(),
        swiftFilePath: String,
        appTargetName: String?,
        uiTestTargetNames: [String],
        screenCount: Int,
        launchArguments: [String],
        environmentKeys: [String],
        navigationPlaceholders: [ScreenshotUITestNavigationPlaceholder],
        instructions: [String],
        agentPrompt: String,
        swiftSource: String,
        ascendKitVersion: String? = AscendKitVersion.current
    ) {
        self.generatedAt = generatedAt
        self.swiftFilePath = swiftFilePath
        self.appTargetName = appTargetName
        self.uiTestTargetNames = uiTestTargetNames
        self.screenCount = screenCount
        self.launchArguments = launchArguments
        self.environmentKeys = environmentKeys
        self.navigationPlaceholders = navigationPlaceholders
        self.instructions = instructions
        self.agentPrompt = agentPrompt
        self.swiftSource = swiftSource
        self.ascendKitVersion = ascendKitVersion
    }
}

public struct ScreenshotUITestNavigationPlaceholder: Codable, Equatable, Sendable {
    public var screenID: String
    public var screenName: String
    public var order: Int
    public var purpose: String
    public var outputFileName: String
    public var replacementGuidance: String

    public init(
        screenID: String,
        screenName: String,
        order: Int,
        purpose: String,
        outputFileName: String,
        replacementGuidance: String
    ) {
        self.screenID = screenID
        self.screenName = screenName
        self.order = order
        self.purpose = purpose
        self.outputFileName = outputFileName
        self.replacementGuidance = replacementGuidance
    }
}

public struct ScreenshotUITestScaffoldBuilder {
    public init() {}

    public func build(
        manifest: ReleaseManifest,
        screenshotPlan: ScreenshotPlan?,
        outputURL: URL
    ) -> ScreenshotUITestScaffoldResult {
        let appTarget = manifest.targets.first(where: \.isAppStoreApplication)
        let uiTestTargets = manifest.targets.filter { target in
            target.productType?.contains("ui-testing") == true || target.name.localizedCaseInsensitiveContains("UITests")
        }
        let items = screenshotPlan?.items.sorted { $0.order < $1.order } ?? [
            ScreenshotPlanItem(id: "home", screenName: "Home", order: 1, purpose: "Show the app's first meaningful screen."),
            ScreenshotPlanItem(id: "feature", screenName: "Feature", order: 2, purpose: "Show the primary product value."),
            ScreenshotPlanItem(id: "paywall", screenName: "Paywall", order: 3, purpose: "Show monetization or upgrade context if applicable.")
        ]
        let swiftSource = makeSwiftSource(items: items)
        return ScreenshotUITestScaffoldResult(
            swiftFilePath: outputURL.path,
            appTargetName: appTarget?.name,
            uiTestTargetNames: uiTestTargets.map(\.name).sorted(),
            screenCount: items.count,
            launchArguments: ["--ascendkit-screenshot-mode", "--disable-animations"],
            environmentKeys: [
                "ASCENDKIT_SCREENSHOT_OUTPUT_DIR",
                "ASCENDKIT_SCREENSHOT_LOCALE"
            ],
            navigationPlaceholders: navigationPlaceholders(for: items),
            instructions: [
                "Review the generated Swift file before adding it to the UI test target.",
                "Replace placeholder navigation comments with real, deterministic app navigation.",
                "Use mock data or local fixtures. Do not use real credentials or production accounts.",
                "Keep screenshot names ordered, for example 01-home.png, 02-feature.png, and 03-paywall.png.",
                "Run screenshots capture-plan, screenshots capture, and screenshots compose after adding the test."
            ],
            agentPrompt: "Add the generated AscendKit screenshot UI test to the app's UI test target. Replace placeholder navigation with stable app-specific steps, keep launch arguments, use deterministic mock data, avoid real credentials, and preserve ordered screenshot file names.",
            swiftSource: swiftSource
        )
    }

    private func navigationPlaceholders(for items: [ScreenshotPlanItem]) -> [ScreenshotUITestNavigationPlaceholder] {
        items.map { item in
            let fileName = "\(String(format: "%02d", item.order))-\(safeStem(item.id)).png"
            return ScreenshotUITestNavigationPlaceholder(
                screenID: item.id,
                screenName: item.screenName,
                order: item.order,
                purpose: item.purpose,
                outputFileName: fileName,
                replacementGuidance: "Replace the TODO before \(fileName) with stable UI automation that navigates to \(item.screenName) without real credentials or network-dependent state."
            )
        }
    }

    private func makeSwiftSource(items: [ScreenshotPlanItem]) -> String {
        let captureCalls = items.map { item in
            let fileName = "\(String(format: "%02d", item.order))-\(safeStem(item.id)).png"
            return """

                // \(escapeComment(item.purpose))
                // TODO: Navigate to \(escapeComment(item.screenName)) using stable accessibility identifiers.
                captureScreenshot(named: "\(fileName)")
            """
        }.joined(separator: "\n")

        return """
        import XCTest

        final class AscendKitScreenshotUITests: XCTestCase {
            private var app: XCUIApplication!

            override func setUpWithError() throws {
                continueAfterFailure = false
                app = XCUIApplication()
                app.launchArguments += [
                    "--ascendkit-screenshot-mode",
                    "--disable-animations"
                ]
                app.launch()
            }

            func testAppStoreScreenshots() throws {
                // Use deterministic mock data and stable navigation. Do not use real credentials.
        \(captureCalls)
            }

            private func captureScreenshot(named fileName: String) {
                let screenshot = XCUIScreen.main.screenshot()
                if let outputDirectory = ProcessInfo.processInfo.environment["ASCENDKIT_SCREENSHOT_OUTPUT_DIR"] {
                    let outputURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent(fileName)
                    try? FileManager.default.createDirectory(
                        at: outputURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try? screenshot.pngRepresentation.write(to: outputURL, options: [.atomic])
                }

                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = fileName
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }

        """
    }

    private func safeStem(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = value.unicodeScalars
            .map { allowed.contains($0) ? String($0).lowercased() : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
        return sanitized.isEmpty ? "screenshot" : sanitized
    }

    private func escapeComment(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ")
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
                findings.append(contentsOf: dimensionFindings(
                    images: images,
                    locale: locale,
                    platform: platform
                ))
            }
        }
        return findings
    }

    private func dimensionFindings(
        images: [URL],
        locale: String,
        platform: ApplePlatform
    ) -> [ScreenshotReadinessFinding] {
        images.compactMap { imageURL in
            guard let image = NSImage(contentsOf: imageURL) else {
                return ScreenshotReadinessFinding(
                    id: "screenshots.import.\(locale).\(platform.rawValue).\(safeFindingID(imageURL.deletingPathExtension().lastPathComponent)).decode",
                    severity: .warning,
                    message: "Screenshot image could not be decoded for \(locale)/\(platform.rawValue): \(imageURL.lastPathComponent).",
                    nextAction: "Replace the file with a valid PNG, JPG, JPEG, HEIC, or TIFF image before final composition/upload."
                )
            }

            let width = Int(image.size.width.rounded())
            let height = Int(image.size.height.rounded())
            guard width >= 320 && height >= 320 else {
                return ScreenshotReadinessFinding(
                    id: "screenshots.import.\(locale).\(platform.rawValue).\(safeFindingID(imageURL.deletingPathExtension().lastPathComponent)).dimensions",
                    severity: .warning,
                    message: "Screenshot image is suspiciously small for \(locale)/\(platform.rawValue): \(imageURL.lastPathComponent) is \(width)x\(height).",
                    nextAction: "Replace it with a real App Store screenshot captured from a simulator or device."
                )
            }

            return nil
        }
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

    private func safeFindingID(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = value.unicodeScalars
            .map { allowed.contains($0) ? String($0).lowercased() : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
        return sanitized.isEmpty ? "image" : sanitized
    }
}

public struct ScreenshotArtifact: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }
    public var locale: String
    public var platform: ApplePlatform
    public var path: String
    public var fileName: String
    public var planItemID: String?
    public var screenName: String?
    public var purpose: String?

    public init(
        locale: String,
        platform: ApplePlatform,
        path: String,
        fileName: String,
        planItemID: String? = nil,
        screenName: String? = nil,
        purpose: String? = nil
    ) {
        self.locale = locale
        self.platform = platform
        self.path = path
        self.fileName = fileName
        self.planItemID = planItemID
        self.screenName = screenName
        self.purpose = purpose
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
                    let matchedItem = ScreenshotSemanticMatcher.matchingPlanItem(
                        forFileName: url.lastPathComponent,
                        items: plan.items
                    )
                    return ScreenshotArtifact(
                        locale: locale,
                        platform: platform,
                        path: url.standardizedFileURL.path,
                        fileName: url.lastPathComponent,
                        planItemID: matchedItem?.id,
                        screenName: matchedItem?.screenName,
                        purpose: matchedItem?.purpose
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
    case framedPoster

    public var effectiveRenderMode: ScreenshotCompositionMode {
        switch self {
        case .deviceFrame:
            return .framedPoster
        case .storeReadyCopy, .poster, .framedPoster:
            return self
        }
    }

    public var requiresMarketingCopy: Bool {
        effectiveRenderMode == .framedPoster
    }
}

// MARK: - Screenshot Theme

public struct ScreenshotThemeColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var nsColor: NSColor {
        NSColor(calibratedRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}

public struct ScreenshotTheme: Codable, Equatable, Sendable {
    public let name: String

    // Framed poster
    public var framedPosterBackground: ScreenshotThemeColor
    public var framedPosterUpperOval: ScreenshotThemeColor
    public var framedPosterLowerOval: ScreenshotThemeColor
    public var framedPosterTitleColor: ScreenshotThemeColor
    public var framedPosterSubtitleColor: ScreenshotThemeColor
    public var framedPosterDeviceFrame: ScreenshotThemeColor
    public var framedPosterDeviceFrameStroke: ScreenshotThemeColor

    // Poster
    public var posterBackground: ScreenshotThemeColor
    public var posterAccentBar: ScreenshotThemeColor
    public var posterTitleColor: ScreenshotThemeColor

    // Device frame
    public var deviceFrameBackground: ScreenshotThemeColor
    public var deviceFrameStroke: ScreenshotThemeColor

    public init(
        name: String,
        framedPosterBackground: ScreenshotThemeColor,
        framedPosterUpperOval: ScreenshotThemeColor,
        framedPosterLowerOval: ScreenshotThemeColor,
        framedPosterTitleColor: ScreenshotThemeColor,
        framedPosterSubtitleColor: ScreenshotThemeColor,
        framedPosterDeviceFrame: ScreenshotThemeColor,
        framedPosterDeviceFrameStroke: ScreenshotThemeColor,
        posterBackground: ScreenshotThemeColor,
        posterAccentBar: ScreenshotThemeColor,
        posterTitleColor: ScreenshotThemeColor,
        deviceFrameBackground: ScreenshotThemeColor,
        deviceFrameStroke: ScreenshotThemeColor
    ) {
        self.name = name
        self.framedPosterBackground = framedPosterBackground
        self.framedPosterUpperOval = framedPosterUpperOval
        self.framedPosterLowerOval = framedPosterLowerOval
        self.framedPosterTitleColor = framedPosterTitleColor
        self.framedPosterSubtitleColor = framedPosterSubtitleColor
        self.framedPosterDeviceFrame = framedPosterDeviceFrame
        self.framedPosterDeviceFrameStroke = framedPosterDeviceFrameStroke
        self.posterBackground = posterBackground
        self.posterAccentBar = posterAccentBar
        self.posterTitleColor = posterTitleColor
        self.deviceFrameBackground = deviceFrameBackground
        self.deviceFrameStroke = deviceFrameStroke
    }

    internal func resolved() -> ScreenshotTheme {
        guard name == "auto" else { return self }
        return Self.randomPreset()
    }

    private static func randomPreset() -> ScreenshotTheme {
        allCases.randomElement()!
    }

    public static let allCases: [ScreenshotTheme] = [
        .tealGold, .midnightPurple, .oceanBlue, .warmAmber, .minimalLight
    ]
}

public extension ScreenshotTheme {
    static let tealGold = ScreenshotTheme(
        name: "tealGold",
        framedPosterBackground: ScreenshotThemeColor(red: 0.08, green: 0.12, blue: 0.10),
        framedPosterUpperOval: ScreenshotThemeColor(red: 0.18, green: 0.36, blue: 0.30, alpha: 0.78),
        framedPosterLowerOval: ScreenshotThemeColor(red: 0.88, green: 0.66, blue: 0.34, alpha: 0.30),
        framedPosterTitleColor: ScreenshotThemeColor(red: 0.98, green: 0.96, blue: 0.90),
        framedPosterSubtitleColor: ScreenshotThemeColor(red: 0.83, green: 0.88, blue: 0.78),
        framedPosterDeviceFrame: ScreenshotThemeColor(red: 0.05, green: 0.06, blue: 0.06),
        framedPosterDeviceFrameStroke: ScreenshotThemeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16),
        posterBackground: ScreenshotThemeColor(red: 0.95, green: 0.91, blue: 0.84),
        posterAccentBar: ScreenshotThemeColor(red: 0.13, green: 0.24, blue: 0.23),
        posterTitleColor: ScreenshotThemeColor(red: 1.0, green: 1.0, blue: 1.0),
        deviceFrameBackground: ScreenshotThemeColor(red: 0.08, green: 0.09, blue: 0.10),
        deviceFrameStroke: ScreenshotThemeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.18)
    )

    static let midnightPurple = ScreenshotTheme(
        name: "midnightPurple",
        framedPosterBackground: ScreenshotThemeColor(red: 0.06, green: 0.04, blue: 0.12),
        framedPosterUpperOval: ScreenshotThemeColor(red: 0.22, green: 0.14, blue: 0.42, alpha: 0.78),
        framedPosterLowerOval: ScreenshotThemeColor(red: 0.55, green: 0.38, blue: 0.72, alpha: 0.30),
        framedPosterTitleColor: ScreenshotThemeColor(red: 0.96, green: 0.94, blue: 0.98),
        framedPosterSubtitleColor: ScreenshotThemeColor(red: 0.78, green: 0.74, blue: 0.88),
        framedPosterDeviceFrame: ScreenshotThemeColor(red: 0.04, green: 0.03, blue: 0.07),
        framedPosterDeviceFrameStroke: ScreenshotThemeColor(red: 0.90, green: 0.85, blue: 1.0, alpha: 0.16),
        posterBackground: ScreenshotThemeColor(red: 0.94, green: 0.91, blue: 0.96),
        posterAccentBar: ScreenshotThemeColor(red: 0.18, green: 0.12, blue: 0.32),
        posterTitleColor: ScreenshotThemeColor(red: 1.0, green: 1.0, blue: 1.0),
        deviceFrameBackground: ScreenshotThemeColor(red: 0.06, green: 0.04, blue: 0.10),
        deviceFrameStroke: ScreenshotThemeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.18)
    )

    static let oceanBlue = ScreenshotTheme(
        name: "oceanBlue",
        framedPosterBackground: ScreenshotThemeColor(red: 0.04, green: 0.08, blue: 0.14),
        framedPosterUpperOval: ScreenshotThemeColor(red: 0.10, green: 0.28, blue: 0.52, alpha: 0.78),
        framedPosterLowerOval: ScreenshotThemeColor(red: 0.30, green: 0.65, blue: 0.78, alpha: 0.30),
        framedPosterTitleColor: ScreenshotThemeColor(red: 0.92, green: 0.96, blue: 1.0),
        framedPosterSubtitleColor: ScreenshotThemeColor(red: 0.68, green: 0.82, blue: 0.88),
        framedPosterDeviceFrame: ScreenshotThemeColor(red: 0.03, green: 0.05, blue: 0.08),
        framedPosterDeviceFrameStroke: ScreenshotThemeColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 0.16),
        posterBackground: ScreenshotThemeColor(red: 0.90, green: 0.94, blue: 0.97),
        posterAccentBar: ScreenshotThemeColor(red: 0.08, green: 0.18, blue: 0.32),
        posterTitleColor: ScreenshotThemeColor(red: 1.0, green: 1.0, blue: 1.0),
        deviceFrameBackground: ScreenshotThemeColor(red: 0.04, green: 0.07, blue: 0.12),
        deviceFrameStroke: ScreenshotThemeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.18)
    )

    static let warmAmber = ScreenshotTheme(
        name: "warmAmber",
        framedPosterBackground: ScreenshotThemeColor(red: 0.12, green: 0.08, blue: 0.05),
        framedPosterUpperOval: ScreenshotThemeColor(red: 0.36, green: 0.22, blue: 0.10, alpha: 0.78),
        framedPosterLowerOval: ScreenshotThemeColor(red: 0.88, green: 0.62, blue: 0.22, alpha: 0.30),
        framedPosterTitleColor: ScreenshotThemeColor(red: 1.0, green: 0.96, blue: 0.88),
        framedPosterSubtitleColor: ScreenshotThemeColor(red: 0.88, green: 0.78, blue: 0.60),
        framedPosterDeviceFrame: ScreenshotThemeColor(red: 0.06, green: 0.04, blue: 0.03),
        framedPosterDeviceFrameStroke: ScreenshotThemeColor(red: 1.0, green: 0.94, blue: 0.80, alpha: 0.16),
        posterBackground: ScreenshotThemeColor(red: 0.97, green: 0.93, blue: 0.86),
        posterAccentBar: ScreenshotThemeColor(red: 0.26, green: 0.16, blue: 0.08),
        posterTitleColor: ScreenshotThemeColor(red: 1.0, green: 1.0, blue: 1.0),
        deviceFrameBackground: ScreenshotThemeColor(red: 0.10, green: 0.07, blue: 0.04),
        deviceFrameStroke: ScreenshotThemeColor(red: 1.0, green: 0.94, blue: 0.80, alpha: 0.18)
    )

    static let minimalLight = ScreenshotTheme(
        name: "minimalLight",
        framedPosterBackground: ScreenshotThemeColor(red: 0.95, green: 0.95, blue: 0.96),
        framedPosterUpperOval: ScreenshotThemeColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 0.60),
        framedPosterLowerOval: ScreenshotThemeColor(red: 0.92, green: 0.88, blue: 0.82, alpha: 0.25),
        framedPosterTitleColor: ScreenshotThemeColor(red: 0.12, green: 0.12, blue: 0.14),
        framedPosterSubtitleColor: ScreenshotThemeColor(red: 0.45, green: 0.45, blue: 0.50),
        framedPosterDeviceFrame: ScreenshotThemeColor(red: 0.85, green: 0.85, blue: 0.87),
        framedPosterDeviceFrameStroke: ScreenshotThemeColor(red: 0.60, green: 0.60, blue: 0.63, alpha: 0.25),
        posterBackground: ScreenshotThemeColor(red: 0.98, green: 0.98, blue: 0.98),
        posterAccentBar: ScreenshotThemeColor(red: 0.12, green: 0.12, blue: 0.14),
        posterTitleColor: ScreenshotThemeColor(red: 1.0, green: 1.0, blue: 1.0),
        deviceFrameBackground: ScreenshotThemeColor(red: 0.90, green: 0.90, blue: 0.92),
        deviceFrameStroke: ScreenshotThemeColor(red: 0.50, green: 0.50, blue: 0.53, alpha: 0.25)
    )

    static let auto = ScreenshotTheme(
        name: "auto",
        framedPosterBackground: ScreenshotThemeColor(red: 0.08, green: 0.12, blue: 0.10),
        framedPosterUpperOval: ScreenshotThemeColor(red: 0.18, green: 0.36, blue: 0.30, alpha: 0.78),
        framedPosterLowerOval: ScreenshotThemeColor(red: 0.88, green: 0.66, blue: 0.34, alpha: 0.30),
        framedPosterTitleColor: ScreenshotThemeColor(red: 0.98, green: 0.96, blue: 0.90),
        framedPosterSubtitleColor: ScreenshotThemeColor(red: 0.83, green: 0.88, blue: 0.78),
        framedPosterDeviceFrame: ScreenshotThemeColor(red: 0.05, green: 0.06, blue: 0.06),
        framedPosterDeviceFrameStroke: ScreenshotThemeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16),
        posterBackground: ScreenshotThemeColor(red: 0.95, green: 0.91, blue: 0.84),
        posterAccentBar: ScreenshotThemeColor(red: 0.13, green: 0.24, blue: 0.23),
        posterTitleColor: ScreenshotThemeColor(red: 1.0, green: 1.0, blue: 1.0),
        deviceFrameBackground: ScreenshotThemeColor(red: 0.08, green: 0.09, blue: 0.10),
        deviceFrameStroke: ScreenshotThemeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.18)
    )
}

public struct ScreenshotCompositionCopyManifest: Codable, Equatable, Sendable {
    public var items: [ScreenshotCompositionCopy]

    public init(items: [ScreenshotCompositionCopy]) {
        self.items = items
    }

    public func copy(locale: String, platform: ApplePlatform, fileName: String) -> ScreenshotCompositionCopy? {
        let canonicalFileName = canonicalScreenshotCopyFileName(fileName)

        // Tier 1: Exact match — locale + platform + fileName
        if let exact = items.first(where: {
            $0.locale == locale &&
                $0.platform == platform &&
                $0.fileName == fileName
        }) {
            return exact
        }

        // Tier 2: Canonical match — locale + platform + normalized fileName
        if let canonicalMatch = items.first(where: {
            $0.locale == locale &&
                $0.platform == platform &&
                canonicalScreenshotCopyFileName($0.fileName) == canonicalFileName
        }) {
            return canonicalMatch
        }

        // Tier 3: Same locale, any platform — exact fileName
        if let sameLocaleFallback = items.first(where: {
            $0.locale == locale && $0.fileName == fileName
        }) {
            return sameLocaleFallback
        }

        // Tier 4: Same locale, any platform — canonical fileName
        if let sameLocaleCanonical = items.first(where: {
            $0.locale == locale &&
                canonicalScreenshotCopyFileName($0.fileName) == canonicalFileName
        }) {
            return sameLocaleCanonical
        }

        // Tier 5: Cross-locale, same platform — exact fileName
        // Prefer same-platform copy from other locales before cross-platform.
        if let samePlatformFallback = items.first(where: {
            $0.platform == platform && $0.fileName == fileName
        }) {
            return samePlatformFallback
        }

        // Tier 6: Cross-locale, same platform — canonical fileName
        if let samePlatformCanonical = items.first(where: {
            $0.platform == platform &&
                canonicalScreenshotCopyFileName($0.fileName) == canonicalFileName
        }) {
            return samePlatformCanonical
        }

        // Tier 7: Cross-locale, any platform — exact fileName
        if let exactFallback = items.first(where: { $0.fileName == fileName }) {
            return exactFallback
        }

        // Tier 8: Cross-locale, any platform — canonical fileName (last resort)
        return items.first {
            canonicalScreenshotCopyFileName($0.fileName) == canonicalFileName
        }
    }

    public func merged(with fallback: ScreenshotCompositionCopyManifest?) -> ScreenshotCompositionCopyManifest {
        guard let fallback else {
            return self
        }
        var merged = fallback.items
        for item in items {
            if let index = merged.firstIndex(where: {
                $0.locale == item.locale &&
                    $0.platform == item.platform &&
                    $0.fileName == item.fileName
            }) {
                merged[index] = item
            } else {
                merged.append(item)
            }
        }
        return ScreenshotCompositionCopyManifest(items: merged.sorted {
            if $0.locale != $1.locale { return $0.locale < $1.locale }
            if $0.platform.rawValue != $1.platform.rawValue { return $0.platform.rawValue < $1.platform.rawValue }
            return $0.fileName < $1.fileName
        })
    }

    private func canonicalScreenshotCopyFileName(_ fileName: String) -> String {
        normalizeScreenshotCopyStem(
            ScreenshotComposer.canonicalScreenshotCopyStem(
                fromFileName: fileName,
                modeSuffixes: ["-framed-poster", "-device-frame", "-poster", "_framed"]
            )
        )
    }

    private func normalizeScreenshotCopyStem(_ stem: String) -> String {
        stem
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: #"[^A-Za-z0-9-]+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
    }
}

public struct ScreenshotCompositionCopyTemplateBuilder {
    public init() {}

    public func build(plan: ScreenshotPlan, locale: String? = nil, fileExtension: String = "png") -> ScreenshotCompositionCopyManifest {
        build(plan: plan, locale: locale, fileExtension: fileExtension, preserving: nil)
    }

    public func refresh(
        plan: ScreenshotPlan,
        existing: ScreenshotCompositionCopyManifest?,
        locale: String? = nil,
        fileExtension: String = "png"
    ) -> ScreenshotCompositionCopyManifest {
        build(plan: plan, locale: locale, fileExtension: fileExtension, preserving: existing)
    }

    private func build(
        plan: ScreenshotPlan,
        locale: String?,
        fileExtension: String,
        preserving existing: ScreenshotCompositionCopyManifest?
    ) -> ScreenshotCompositionCopyManifest {
        let effectiveLocales = locale.map { [$0] } ?? plan.locales
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let items = effectiveLocales.flatMap { locale in
            plan.platforms.flatMap { platform in
                plan.items.sorted { $0.order < $1.order }.map { item in
                    let fileName = "\(String(format: "%02d", item.order))-\(item.id).\(normalizedExtension)"
                    let existingCopy = existing?.copy(locale: locale, platform: platform, fileName: fileName)
                    return ScreenshotCompositionCopy(
                        locale: locale,
                        platform: platform,
                        fileName: fileName,
                        title: existingCopy?.title ?? item.screenName,
                        subtitle: existingCopy?.subtitle ?? item.purpose
                    )
                }
            }
        }
        return ScreenshotCompositionCopyManifest(items: items)
    }
}

enum ScreenshotSemanticMatcher {
    static func matchingPlanItem(
        forFileName fileName: String,
        items: [ScreenshotPlanItem]
    ) -> ScreenshotPlanItem? {
        let candidateStem = normalizedStem(fromFileName: fileName)
        if let exact = items.first(where: { normalizedStem(forPlanItem: $0) == candidateStem }) {
            return exact
        }

        let unprefixedStem = candidateStem.replacingOccurrences(
            of: #"^\d+[-\s]*"#,
            with: "",
            options: .regularExpression
        )
        return items.first {
            normalizedStem(forPlanItem: $0)
                .replacingOccurrences(of: #"^\d+[-\s]*"#, with: "", options: .regularExpression) == unprefixedStem
        }
    }

    static func normalizedStem(forPlanItem item: ScreenshotPlanItem) -> String {
        "\(String(format: "%02d", item.order))-\(item.id)"
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: #"[^A-Za-z0-9-]+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
    }

    static func normalizedStem(fromFileName fileName: String) -> String {
        ScreenshotComposer.canonicalScreenshotCopyStem(
            fromFileName: fileName,
            modeSuffixes: ["-framed-poster", "-device-frame", "-poster", "_framed"]
        )
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: #"[^A-Za-z0-9-]+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
    }
}

public struct ScreenshotCompositionCopyLintReport: Codable, Equatable, Sendable {
    public var valid: Bool
    public var checkedArtifactCount: Int
    public var copyItemCount: Int
    public var findings: [String]

    public init(checkedArtifactCount: Int, copyItemCount: Int, findings: [String] = []) {
        self.valid = findings.isEmpty
        self.checkedArtifactCount = checkedArtifactCount
        self.copyItemCount = copyItemCount
        self.findings = findings
    }
}

public struct ScreenshotCompositionCopyLinter {
    public init() {}

    public func lint(importManifest: ScreenshotImportManifest, copyManifest: ScreenshotCompositionCopyManifest) -> ScreenshotCompositionCopyLintReport {
        var findings: [String] = []
        for artifact in importManifest.artifacts {
            if copyManifest.copy(locale: artifact.locale, platform: artifact.platform, fileName: artifact.fileName) == nil {
                findings.append("Missing copy for \(artifact.locale)/\(artifact.platform.rawValue)/\(artifact.fileName).")
            }
        }

        for item in copyManifest.items {
            let itemManifest = ScreenshotCompositionCopyManifest(items: [item])
            let hasArtifact = importManifest.artifacts.contains {
                itemManifest.copy(locale: $0.locale, platform: $0.platform, fileName: $0.fileName) != nil
            }
            if !hasArtifact {
                findings.append("Stale copy item for \(item.locale)/\(item.platform.rawValue)/\(item.fileName).")
            }
        }

        return ScreenshotCompositionCopyLintReport(
            checkedArtifactCount: importManifest.artifacts.count,
            copyItemCount: copyManifest.items.count,
            findings: findings.sorted()
        )
    }
}

public struct ScreenshotCompositionCopy: Codable, Equatable, Sendable {
    public var locale: String
    public var platform: ApplePlatform
    public var fileName: String
    public var title: String
    public var subtitle: String?

    public init(
        locale: String,
        platform: ApplePlatform,
        fileName: String,
        title: String,
        subtitle: String? = nil
    ) {
        self.locale = locale
        self.platform = platform
        self.fileName = fileName
        self.title = title
        self.subtitle = subtitle
    }
}

public struct ScreenshotCompositionArtifact: Codable, Equatable, Identifiable, Sendable {
    public var id: String { outputPath }
    public var locale: String
    public var platform: ApplePlatform
    public var inputPath: String
    public var outputPath: String
    public var mode: ScreenshotCompositionMode
    public var planItemID: String?
    public var screenName: String?
    public var purpose: String?
    public var title: String?
    public var subtitle: String?

    public init(
        locale: String,
        platform: ApplePlatform,
        inputPath: String,
        outputPath: String,
        mode: ScreenshotCompositionMode,
        planItemID: String? = nil,
        screenName: String? = nil,
        purpose: String? = nil,
        title: String? = nil,
        subtitle: String? = nil
    ) {
        self.locale = locale
        self.platform = platform
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.mode = mode
        self.planItemID = planItemID
        self.screenName = screenName
        self.purpose = purpose
        self.title = title
        self.subtitle = subtitle
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
    public var ascendKitVersion: String?
    public var executed: Bool
    public var uploadedCount: Int
    public var items: [ScreenshotUploadExecutionItem]
    public var findings: [String]
    public var deletedScreenshots: [ScreenshotRemoteDeletion]?
    public var failedItems: [ScreenshotUploadFailure]?

    public init(
        generatedAt: Date = Date(),
        ascendKitVersion: String? = AscendKitVersion.current,
        executed: Bool,
        uploadedCount: Int = 0,
        items: [ScreenshotUploadExecutionItem] = [],
        findings: [String] = [],
        deletedScreenshots: [ScreenshotRemoteDeletion] = [],
        failedItems: [ScreenshotUploadFailure] = []
    ) {
        self.generatedAt = generatedAt
        self.ascendKitVersion = ascendKitVersion
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

public struct ScreenshotUploadStatusReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var ascendKitVersion: String?
    public var plannedCount: Int?
    public var executed: Bool?
    public var uploadedCount: Int
    public var failedCount: Int
    public var deletedCount: Int
    public var deliveryCompleteCount: Int
    public var deliveryFailedCount: Int
    public var deliveryPendingCount: Int
    public var deliveryUnknownCount: Int
    public var deliveryFailedItemIDs: [String]
    public var deliveryPendingItemIDs: [String]
    public var requiresRemoteRecovery: Bool
    public var readyForReview: Bool
    public var readyForRetry: Bool
    public var retryPlanItemIDs: [String]
    public var findings: [String]
    public var nextActions: [String]
    public var recoveryCommands: [String]

    public init(
        generatedAt: Date = Date(),
        ascendKitVersion: String? = AscendKitVersion.current,
        plannedCount: Int?,
        executed: Bool?,
        uploadedCount: Int,
        failedCount: Int,
        deletedCount: Int,
        deliveryCompleteCount: Int = 0,
        deliveryFailedCount: Int = 0,
        deliveryPendingCount: Int = 0,
        deliveryUnknownCount: Int = 0,
        deliveryFailedItemIDs: [String] = [],
        deliveryPendingItemIDs: [String] = [],
        requiresRemoteRecovery: Bool = false,
        readyForReview: Bool = false,
        readyForRetry: Bool,
        retryPlanItemIDs: [String],
        findings: [String],
        nextActions: [String],
        recoveryCommands: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.ascendKitVersion = ascendKitVersion
        self.plannedCount = plannedCount
        self.executed = executed
        self.uploadedCount = uploadedCount
        self.failedCount = failedCount
        self.deletedCount = deletedCount
        self.deliveryCompleteCount = deliveryCompleteCount
        self.deliveryFailedCount = deliveryFailedCount
        self.deliveryPendingCount = deliveryPendingCount
        self.deliveryUnknownCount = deliveryUnknownCount
        self.deliveryFailedItemIDs = deliveryFailedItemIDs
        self.deliveryPendingItemIDs = deliveryPendingItemIDs
        self.requiresRemoteRecovery = requiresRemoteRecovery
        self.readyForReview = readyForReview
        self.readyForRetry = readyForRetry
        self.retryPlanItemIDs = retryPlanItemIDs
        self.findings = findings
        self.nextActions = nextActions
        self.recoveryCommands = recoveryCommands
    }
}

public struct ScreenshotUploadStatusBuilder {
    public init() {}

    public func build(
        plan: ScreenshotUploadPlan?,
        result: ScreenshotUploadExecutionResult?
    ) -> ScreenshotUploadStatusReport {
        guard let result else {
            return ScreenshotUploadStatusReport(
                plannedCount: plan?.items.count,
                executed: nil,
                uploadedCount: 0,
                failedCount: 0,
                deletedCount: 0,
                readyForRetry: false,
                retryPlanItemIDs: [],
                findings: plan?.findings ?? [],
                nextActions: ["Run screenshots upload --workspace PATH --confirm-remote-mutation after reviewing screenshots upload-plan."],
                recoveryCommands: ["screenshots upload --workspace PATH --confirm-remote-mutation --json"]
            )
        }

        let failedItems = result.failedItems ?? []
        let idempotentCommittedFailures = failedItems.filter(Self.isAlreadyCommittedScreenshotUploadFailure)
        let actionableFailedItems = failedItems.filter { !Self.isAlreadyCommittedScreenshotUploadFailure($0) }
        let retryPlanItemIDs = actionableFailedItems.compactMap(\.planItemID).sorted()
        let deliverySummary = deliveryStateSummary(items: result.items)
        let effectiveUploadedCount = result.uploadedCount + idempotentCommittedFailures.count
        let effectiveDeliveryCompleteCount = deliverySummary.completeCount + idempotentCommittedFailures.count
        let deletionFailed = actionableFailedItems.contains(where: { $0.phase == "delete" })
        let requiresRemoteRecovery = deletionFailed || !deliverySummary.failedItemIDs.isEmpty
        let readyForReview = result.executed
            && actionableFailedItems.isEmpty
            && deliverySummary.failedItemIDs.isEmpty
            && deliverySummary.pendingItemIDs.isEmpty
            && deliverySummary.unknownCount == 0
            && effectiveUploadedCount == (plan?.items.count ?? result.items.count + idempotentCommittedFailures.count)
        var findings = result.findings.filter { finding in
            !actionableFailedItems.isEmpty || !finding.contains("Screenshot upload completed with")
        }
        if !idempotentCommittedFailures.isEmpty {
            findings.append("ASC reported \(idempotentCommittedFailures.count) screenshot commit(s) already complete; treated as uploaded.")
        }
        if !deliverySummary.failedItemIDs.isEmpty {
            findings.append("Screenshot asset delivery failed for \(deliverySummary.failedItemIDs.count) uploaded item(s).")
        }
        if !deliverySummary.pendingItemIDs.isEmpty {
            findings.append("Screenshot asset delivery is still pending for \(deliverySummary.pendingItemIDs.count) uploaded item(s).")
        }
        if deliverySummary.unknownCount > 0 {
            findings.append("Screenshot asset delivery state is unknown for \(deliverySummary.unknownCount) uploaded item(s).")
        }
        var nextActions: [String] = []
        if !actionableFailedItems.isEmpty {
            nextActions.append("Inspect failedItems in screenshots/manifests/upload-result.json.")
            if !retryPlanItemIDs.isEmpty {
                nextActions.append("Fix the failed local assets or transient ASC issue, then rerun screenshots upload with the same workspace.")
            }
            if deletionFailed {
                nextActions.append("Resolve remote screenshot deletion failures before retrying replace-existing upload.")
            }
        }
        if !deliverySummary.failedItemIDs.isEmpty {
            nextActions.append("Open App Store Connect or re-run asc metadata observe to inspect failed screenshot processing before replacing remote screenshots.")
            nextActions.append("If failed screenshots remain in the target set, run screenshots upload-plan --replace-existing and review planned deletions before retrying.")
        }
        if !deliverySummary.pendingItemIDs.isEmpty {
            nextActions.append("Wait for App Store Connect screenshot processing, then re-run screenshots upload-status after refreshing observed state if needed.")
        }
        if nextActions.isEmpty && readyForReview {
            nextActions.append("Screenshots are uploaded and asset delivery is complete; run workspace summary or submit readiness.")
        } else if nextActions.isEmpty && result.executed {
            nextActions.append("Run screenshots workflow status or workspace summary to confirm no screenshot blockers remain.")
        } else if nextActions.isEmpty {
            nextActions.append("Run screenshots upload --workspace PATH --confirm-remote-mutation when ready to mutate App Store Connect.")
        }
        let recoveryCommands = recoveryCommands(
            result: result,
            retryPlanItemIDs: retryPlanItemIDs,
            deliverySummary: deliverySummary,
            deletionFailed: deletionFailed,
            readyForReview: readyForReview
        )

        return ScreenshotUploadStatusReport(
            plannedCount: plan?.items.count,
            executed: result.executed,
            uploadedCount: effectiveUploadedCount,
            failedCount: actionableFailedItems.count,
            deletedCount: result.deletedScreenshots?.count ?? 0,
            deliveryCompleteCount: effectiveDeliveryCompleteCount,
            deliveryFailedCount: deliverySummary.failedItemIDs.count,
            deliveryPendingCount: deliverySummary.pendingItemIDs.count,
            deliveryUnknownCount: deliverySummary.unknownCount,
            deliveryFailedItemIDs: deliverySummary.failedItemIDs,
            deliveryPendingItemIDs: deliverySummary.pendingItemIDs,
            requiresRemoteRecovery: requiresRemoteRecovery,
            readyForReview: readyForReview,
            readyForRetry: !retryPlanItemIDs.isEmpty,
            retryPlanItemIDs: retryPlanItemIDs,
            findings: Array(Set(findings)).sorted(),
            nextActions: nextActions,
            recoveryCommands: recoveryCommands
        )
    }

    private static func isAlreadyCommittedScreenshotUploadFailure(_ failure: ScreenshotUploadFailure) -> Bool {
        guard failure.phase == "upload",
              failure.message.contains("app-screenshot.commit"),
              failure.message.contains("HTTP 409"),
              failure.message.contains("STATE_ERROR") else {
            return false
        }
        return failure.message.contains("can't be re-committed")
            || failure.message.contains("can't commit Asset")
            || failure.message.contains("already Approved")
            || failure.message.contains("Asset in Completed")
    }

    private func deliveryStateSummary(items: [ScreenshotUploadExecutionItem]) -> (
        completeCount: Int,
        failedItemIDs: [String],
        pendingItemIDs: [String],
        unknownCount: Int
    ) {
        var completeCount = 0
        var failedItemIDs: [String] = []
        var pendingItemIDs: [String] = []
        var unknownCount = 0

        for item in items {
            guard let rawState = item.assetDeliveryState?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawState.isEmpty else {
                unknownCount += 1
                continue
            }
            switch rawState.uppercased() {
            case "COMPLETE":
                completeCount += 1
            case "FAILED":
                failedItemIDs.append(item.planItemID)
            default:
                pendingItemIDs.append(item.planItemID)
            }
        }

        return (
            completeCount,
            failedItemIDs.sorted(),
            pendingItemIDs.sorted(),
            unknownCount
        )
    }

    private func recoveryCommands(
        result: ScreenshotUploadExecutionResult,
        retryPlanItemIDs: [String],
        deliverySummary: (
            completeCount: Int,
            failedItemIDs: [String],
            pendingItemIDs: [String],
            unknownCount: Int
        ),
        deletionFailed: Bool,
        readyForReview: Bool
    ) -> [String] {
        if readyForReview {
            return [
                "workspace summary --workspace PATH --json",
                "submit readiness --workspace PATH --json"
            ]
        }
        if !deliverySummary.pendingItemIDs.isEmpty {
            return [
                "asc metadata observe --workspace PATH --json",
                "screenshots upload-status --workspace PATH --json"
            ]
        }
        if !deliverySummary.failedItemIDs.isEmpty || deletionFailed {
            return [
                "asc metadata observe --workspace PATH --json",
                "screenshots upload-plan --workspace PATH --replace-existing --json",
                "screenshots upload --workspace PATH --replace-existing --confirm-remote-mutation --json"
            ]
        }
        if !retryPlanItemIDs.isEmpty {
            return [
                "screenshots upload --workspace PATH --confirm-remote-mutation --json",
                "screenshots upload-status --workspace PATH --json"
            ]
        }
        if !result.executed {
            return ["screenshots upload --workspace PATH --confirm-remote-mutation --json"]
        }
        return ["workspace summary --workspace PATH --json"]
    }
}

public struct ScreenshotCoverageEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { [locale, platform.rawValue, displayType ?? "none"].joined(separator: ":") }
    public var locale: String
    public var platform: ApplePlatform
    public var displayType: String?
    public var expectedCount: Int?
    public var importedCount: Int
    public var composedCount: Int
    public var uploadPlanCount: Int
    public var complete: Bool

    public init(
        locale: String,
        platform: ApplePlatform,
        displayType: String?,
        expectedCount: Int?,
        importedCount: Int,
        composedCount: Int,
        uploadPlanCount: Int
    ) {
        self.locale = locale
        self.platform = platform
        self.displayType = displayType
        self.expectedCount = expectedCount
        self.importedCount = importedCount
        self.composedCount = composedCount
        self.uploadPlanCount = uploadPlanCount
        self.complete = expectedCount.map {
            if displayType == nil {
                return importedCount >= $0 && composedCount >= $0
            }
            return importedCount >= $0 && composedCount >= $0 && uploadPlanCount >= $0
        } ?? (importedCount > 0 || composedCount > 0 || uploadPlanCount > 0)
    }
}

public struct ScreenshotCoverageReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var complete: Bool
    public var entries: [ScreenshotCoverageEntry]
    public var findings: [String]

    public init(generatedAt: Date = Date(), entries: [ScreenshotCoverageEntry], findings: [String]) {
        self.generatedAt = generatedAt
        self.entries = entries
        self.findings = findings
        self.complete = entries.allSatisfy(\.complete) && findings.isEmpty
    }
}

public struct ScreenshotCoverageBuilder {
    public init() {}

    public func build(
        plan: ScreenshotPlan?,
        importManifest: ScreenshotImportManifest?,
        compositionManifest: ScreenshotCompositionManifest?,
        uploadPlan: ScreenshotUploadPlan?
    ) -> ScreenshotCoverageReport {
        let expectedCount = plan?.items.count
        var keys = Set<CoverageKey>()
        if let plan {
            for locale in plan.locales {
                for platform in plan.platforms {
                    keys.insert(CoverageKey(locale: locale, platform: platform, displayType: nil))
                }
            }
        }
        keys.formUnion((importManifest?.artifacts ?? []).map { CoverageKey(locale: $0.locale, platform: $0.platform, displayType: nil) })
        keys.formUnion((compositionManifest?.artifacts ?? []).map { CoverageKey(locale: $0.locale, platform: $0.platform, displayType: nil) })
        keys.formUnion((uploadPlan?.items ?? []).map { CoverageKey(locale: $0.locale, platform: $0.platform, displayType: $0.displayType) })

        let imported = Dictionary(grouping: importManifest?.artifacts ?? []) {
            CoverageKey(locale: $0.locale, platform: $0.platform, displayType: nil)
        }
        let composed = Dictionary(grouping: compositionManifest?.artifacts ?? []) {
            CoverageKey(locale: $0.locale, platform: $0.platform, displayType: nil)
        }
        let uploadItems = Dictionary(grouping: uploadPlan?.items ?? []) {
            CoverageKey(locale: $0.locale, platform: $0.platform, displayType: $0.displayType)
        }

        var findings: [String] = []
        if plan == nil {
            findings.append("Screenshot plan is missing; expected coverage cannot be fully evaluated.")
        }

        let entries = keys.sorted().map { key in
            let baseKey = CoverageKey(locale: key.locale, platform: key.platform, displayType: nil)
            let entry = ScreenshotCoverageEntry(
                locale: key.locale,
                platform: key.platform,
                displayType: key.displayType,
                expectedCount: expectedCount,
                importedCount: imported[baseKey]?.count ?? 0,
                composedCount: composed[baseKey]?.count ?? 0,
                uploadPlanCount: uploadItems[key]?.count ?? 0
            )
            if let expectedCount, !entry.complete {
                findings.append("Incomplete screenshot coverage for \(key.locale)/\(key.platform.rawValue)\(key.displayType.map { "/\($0)" } ?? ""): expected \(expectedCount), imported \(entry.importedCount), composed \(entry.composedCount), upload-plan \(entry.uploadPlanCount).")
            }
            return entry
        }

        return ScreenshotCoverageReport(entries: entries, findings: findings)
    }

    private struct CoverageKey: Hashable, Comparable {
        var locale: String
        var platform: ApplePlatform
        var displayType: String?

        static func < (lhs: CoverageKey, rhs: CoverageKey) -> Bool {
            if lhs.locale != rhs.locale { return lhs.locale < rhs.locale }
            if lhs.platform.rawValue != rhs.platform.rawValue { return lhs.platform.rawValue < rhs.platform.rawValue }
            return (lhs.displayType ?? "") < (rhs.displayType ?? "")
        }
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
    public var assetDeliveryPollAttempts: Int?
    public var responses: [ReviewSubmissionExecutionResponse]

    public init(
        planItemID: String,
        appScreenshotSetID: String,
        appScreenshotID: String,
        fileName: String,
        checksum: String,
        assetDeliveryState: String? = nil,
        assetDeliveryPollAttempts: Int? = nil,
        responses: [ReviewSubmissionExecutionResponse] = []
    ) {
        self.planItemID = planItemID
        self.appScreenshotSetID = appScreenshotSetID
        self.appScreenshotID = appScreenshotID
        self.fileName = fileName
        self.checksum = checksum
        self.assetDeliveryState = assetDeliveryState
        self.assetDeliveryPollAttempts = assetDeliveryPollAttempts
        self.responses = responses
        self.id = appScreenshotID
    }
}

enum ScreenshotDisplayTypeValidator {
    static func finding(platform: ApplePlatform, displayType: String, fileName: String) -> String? {
        guard isCompatible(platform: platform, displayType: displayType) else {
            return "Screenshot item \(fileName) has platform \(platform.rawValue) but displayType \(displayType). Regenerate the upload plan so each platform targets its matching App Store Connect screenshot set."
        }
        return nil
    }

    private static func isCompatible(platform: ApplePlatform, displayType: String) -> Bool {
        switch platform {
        case .iOS:
            return displayType.hasPrefix("APP_IPHONE_")
        case .iPadOS:
            return displayType.hasPrefix("APP_IPAD_")
        case .macOS:
            return displayType == "APP_DESKTOP"
        case .tvOS:
            return displayType == "APP_APPLE_TV"
        case .watchOS:
            return displayType.hasPrefix("APP_WATCH")
        case .visionOS:
            return displayType == "APP_VISION_PRO"
        case .unknown:
            return true
        }
    }
}

public struct ScreenshotUploadPlanBuilder {
    public init() {}

    public func build(
        importManifest: ScreenshotImportManifest?,
        compositionManifest: ScreenshotCompositionManifest?,
        observedState: MetadataObservedState?,
        displayTypeOverride: String? = nil,
        replaceExistingRemoteScreenshots: Bool = false,
        onlyPlanItemIDs: Set<String> = [],
        deleteOnlyMatchingRemoteFiles: Bool = false
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

        let uploadSourceArtifacts: [UploadSourceArtifact]
        if let displayTypeOverride {
            uploadSourceArtifacts = sourceArtifacts.filter {
                ScreenshotDisplayTypeValidator.finding(
                    platform: $0.platform,
                    displayType: displayTypeOverride,
                    fileName: $0.fileName
                ) == nil
            }
        } else {
            uploadSourceArtifacts = sourceArtifacts
        }

        let grouped = Dictionary(grouping: uploadSourceArtifacts) { "\($0.locale)|\($0.platform.rawValue)" }
        var items = grouped
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
        if !onlyPlanItemIDs.isEmpty {
            items = items.filter { onlyPlanItemIDs.contains($0.id) }
            let missingIDs = onlyPlanItemIDs.subtracting(items.map(\.id)).sorted()
            if !missingIDs.isEmpty {
                findings.append("Requested screenshot upload item(s) were not found: \(missingIDs.joined(separator: ", ")).")
            }
        }

        let remoteScreenshotsToDelete = existingRemoteScreenshots(
            items: items,
            observedState: observedState,
            matchingFilesOnly: deleteOnlyMatchingRemoteFiles
        )

        // When --delete-matching-files-only is used without --only-item,
        // the intent is delete-only with no new uploads. Clear upload items
        // but keep the deletions that were computed above.
        if deleteOnlyMatchingRemoteFiles && onlyPlanItemIDs.isEmpty {
            items = []
            findings.append("--delete-matching-files-only was used without --only-item; upload items have been cleared. Only remote file deletions will be planned.")
        }
        findings.append(contentsOf: localizationMismatchFindings(items: items, observedState: observedState))
        findings.append(contentsOf: displayTypeMismatchFindings(items: items))
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
        observedState: MetadataObservedState?,
        matchingFilesOnly: Bool = false
    ) -> [ScreenshotRemoteDeletion] {
        guard let observedState else {
            return []
        }

        var deletions: [ScreenshotRemoteDeletion] = []
        let targets = Set(items.map { "\($0.locale)|\($0.displayType)" })
        let targetFileNamesBySet = Dictionary(grouping: items) { "\($0.locale)|\($0.displayType)" }
            .mapValues { Set($0.map(\.fileName)) }
        for (locale, sets) in observedState.screenshotSetsByLocale ?? [:] {
            for set in sets where !set.screenshots.isEmpty {
                let key = "\(locale)|\(set.displayType)"
                guard targets.contains(key) else {
                    continue
                }
                let screenshots = matchingFilesOnly
                    ? set.screenshots.filter {
                        guard let fileName = $0.fileName else { return false }
                        return targetFileNamesBySet[key]?.contains(fileName) == true
                    }
                    : set.screenshots
                deletions.append(contentsOf: screenshots.map {
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

    private func displayTypeMismatchFindings(items: [ScreenshotUploadPlanItem]) -> [String] {
        items.compactMap {
            ScreenshotDisplayTypeValidator.finding(
                platform: $0.platform,
                displayType: $0.displayType,
                fileName: $0.fileName
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

    public func compose(
        importManifest: ScreenshotImportManifest,
        outputRoot: URL,
        mode: ScreenshotCompositionMode,
        copyManifest: ScreenshotCompositionCopyManifest? = nil,
        theme: ScreenshotTheme = .tealGold
    ) throws -> ScreenshotCompositionManifest {
        let effectiveTheme = theme.resolved()
        let renderMode = mode.effectiveRenderMode
        var artifacts: [ScreenshotCompositionArtifact] = []
        for artifact in importManifest.artifacts {
            let inputURL = URL(fileURLWithPath: artifact.path)
            let outputDirectory = outputRoot
                .appendingPathComponent(renderMode.rawValue)
                .appendingPathComponent(artifact.locale)
                .appendingPathComponent(artifact.platform.rawValue)
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            let outputURL: URL
            switch renderMode {
            case .storeReadyCopy:
                let baseName = inputURL.deletingPathExtension().lastPathComponent
                outputURL = outputDirectory.appendingPathComponent("\(baseName).png")
                try replaceExistingFile(at: outputURL) {
                    let png = try ScreenshotImageSanitizer.opaquePNGData(from: inputURL)
                    try png.write(to: outputURL, options: [.atomic])
                }
            case .poster:
                let baseName = inputURL.deletingPathExtension().lastPathComponent
                outputURL = outputDirectory.appendingPathComponent("\(baseName)-poster.png")
                try replaceExistingFile(at: outputURL) {
                    try renderPoster(inputURL: inputURL, outputURL: outputURL, theme: effectiveTheme)
                }
            case .deviceFrame:
                fatalError("deviceFrame is normalized to framedPoster before rendering.")
            case .framedPoster:
                let baseName = inputURL.deletingPathExtension().lastPathComponent
                outputURL = outputDirectory.appendingPathComponent("\(baseName)-framed-poster.png")
                let copy = copyManifest?.copy(
                    locale: artifact.locale,
                    platform: artifact.platform,
                    fileName: artifact.fileName
                )
                let effectiveTitle = copy?.title
                    ?? artifact.screenName
                    ?? Self.inferredTitle(fromFileName: inputURL.lastPathComponent)
                let effectiveSubtitle = copy?.subtitle ?? artifact.purpose
                try replaceExistingFile(at: outputURL) {
                    try renderFramedPoster(
                        inputURL: inputURL,
                        outputURL: outputURL,
                        title: effectiveTitle,
                        subtitle: effectiveSubtitle,
                        theme: effectiveTheme,
                        platform: artifact.platform
                    )
                }
            }

            artifacts.append(ScreenshotCompositionArtifact(
                locale: artifact.locale,
                platform: artifact.platform,
                inputPath: inputURL.standardizedFileURL.path,
                outputPath: outputURL.standardizedFileURL.path,
                mode: renderMode,
                planItemID: artifact.planItemID,
                screenName: artifact.screenName,
                purpose: artifact.purpose,
                title: renderMode == .framedPoster ? (copyManifest?.copy(
                    locale: artifact.locale,
                    platform: artifact.platform,
                    fileName: artifact.fileName
                )?.title ?? artifact.screenName ?? Self.inferredTitle(fromFileName: inputURL.lastPathComponent)) : nil,
                subtitle: renderMode == .framedPoster ? (copyManifest?.copy(
                    locale: artifact.locale,
                    platform: artifact.platform,
                    fileName: artifact.fileName
                )?.subtitle ?? artifact.purpose) : nil
            ))
        }
        return ScreenshotCompositionManifest(mode: renderMode, artifacts: artifacts)
    }

    private func replaceExistingFile(at url: URL, write: () throws -> Void) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try write()
    }

    private func renderPoster(inputURL: URL, outputURL: URL, theme: ScreenshotTheme) throws {
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

        let png = try ScreenshotImageSanitizer.renderOpaquePNG(
            size: canvasSize,
            backgroundColor: theme.posterBackground.nsColor
        ) {
            let accentRect = NSRect(x: 0, y: canvasSize.height - 760, width: canvasSize.width, height: 760)
            theme.posterAccentBar.nsColor.setFill()
            accentRect.fill()

            let title = inputURL.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 76, weight: .semibold),
                .foregroundColor: theme.posterTitleColor.nsColor
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
        }
        try png.write(to: outputURL, options: [.atomic])
    }

    private func renderDeviceFrame(inputURL: URL, outputURL: URL, theme: ScreenshotTheme) throws {
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

        let png = try ScreenshotImageSanitizer.renderOpaquePNG(size: canvasSize) {
            let outerPath = NSBezierPath(
                roundedRect: NSRect(origin: .zero, size: canvasSize),
                xRadius: outerRadius,
                yRadius: outerRadius
            )
            theme.deviceFrameBackground.nsColor.setFill()
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

            theme.deviceFrameStroke.nsColor.setStroke()
            outerPath.lineWidth = max(2, border * 0.06)
            outerPath.stroke()
        }
        try png.write(to: outputURL, options: [.atomic])
    }

    private func renderFramedPoster(
        inputURL: URL,
        outputURL: URL,
        title: String,
        subtitle: String?,
        theme: ScreenshotTheme,
        platform: ApplePlatform
    ) throws {
        guard let screenshot = NSImage(contentsOf: inputURL), screenshot.isValid else {
            throw AscendKitError.invalidState("Cannot decode screenshot image for framed poster composition: \(inputURL.path)")
        }

        let canvasSize = bitmapPixelSize(for: screenshot)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            throw AscendKitError.invalidState("Screenshot has invalid dimensions: \(inputURL.path)")
        }

        let isTablet = canvasSize.width >= 1_800 || canvasSize.height <= canvasSize.width * 1.45
        let topBandHeight = canvasSize.height * (isTablet ? 0.30 : 0.33)
        let sideInset = canvasSize.width * (isTablet ? 0.12 : 0.10)
        let bottomInset = canvasSize.height * 0.055
        let deviceTop = bottomInset
        let deviceMaxSize = NSSize(
            width: canvasSize.width - sideInset * 2,
            height: canvasSize.height - topBandHeight - bottomInset * 1.1
        )
        let screenSize = aspectFitSize(source: canvasSize, maximum: deviceMaxSize)
        let screenRect = NSRect(
            x: (canvasSize.width - screenSize.width) / 2,
            y: deviceTop,
            width: screenSize.width,
            height: screenSize.height
        )

        // Fetch specification from the new DeviceFrameRegistry
        let spec = DeviceFrameRegistry.shared.specification(for: platform, size: canvasSize)
            ?? DeviceFrameRegistry.shared.defaultSpecification(for: platform)

        let bezelWidth = spec?.bezelWidth ?? max(14, min(screenSize.width, screenSize.height) * 0.045)
        let cornerRadius = spec?.cornerRadius ?? (bezelWidth * 1.55)

        let framePadding = bezelWidth
        let frameRect = screenRect.insetBy(dx: -framePadding, dy: -framePadding)

        let png = try ScreenshotImageSanitizer.renderOpaquePNG(
            size: canvasSize,
            backgroundColor: theme.framedPosterBackground.nsColor
        ) {
            drawFramedPosterBackground(canvasSize: canvasSize, theme: theme)

            let titleFontSize = min(canvasSize.width * 0.085, topBandHeight * 0.32)
            let subtitleFontSize = titleFontSize * 0.34
            let titleRect = NSRect(
                x: sideInset,
                y: canvasSize.height - topBandHeight + topBandHeight * 0.42,
                width: canvasSize.width - sideInset * 2,
                height: topBandHeight * 0.34
            )
            drawCenteredSingleLineTextFitting(
                title,
                in: titleRect,
                maxFontSize: titleFontSize,
                minFontSize: max(28, titleFontSize * 0.48),
                weight: .bold,
                color: theme.framedPosterTitleColor.nsColor,
                lineSpacing: titleFontSize * 0.06
            )

            if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                drawCenteredTextFitting(
                    subtitle,
                    in: NSRect(
                        x: sideInset,
                        y: canvasSize.height - topBandHeight + topBandHeight * 0.22,
                        width: canvasSize.width - sideInset * 2,
                        height: topBandHeight * 0.18
                    ),
                    maxFontSize: subtitleFontSize,
                    minFontSize: max(18, subtitleFontSize * 0.72),
                    weight: .medium,
                    color: theme.framedPosterSubtitleColor.nsColor,
                    lineSpacing: subtitleFontSize * 0.05
                )
            }

            // Draw shadow for the hardware frame
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowOffset = NSSize(width: 0, height: -22)
            shadow.shadowBlurRadius = 56
            shadow.set()

            let frameRadius = cornerRadius
            let framePath = NSBezierPath(roundedRect: frameRect, xRadius: frameRadius, yRadius: frameRadius)
            theme.framedPosterDeviceFrame.nsColor.setFill()
            framePath.fill()

            // Draw screen area & clip the screenshot
            NSGraphicsContext.saveGraphicsState()
            NSShadow().set()
            let screenRadius = max(6.0, frameRadius - framePadding)
            let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: screenRadius, yRadius: screenRadius)
            screenPath.addClip()
            screenshot.draw(
                in: screenRect,
                from: NSRect(origin: .zero, size: screenshot.size),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: false,
                hints: [.interpolation: NSImageInterpolation.high]
            )

            // Draw Dynamic Island overlay if specified
            if let islandSize = spec?.dynamicIslandSize {
                let scale = screenSize.width / (spec?.screenPixelSize.width ?? 1.0)
                let actualIslandSize = NSSize(width: islandSize.width * scale, height: islandSize.height * scale)
                let islandRect = NSRect(
                    x: screenRect.midX - (actualIslandSize.width / 2),
                    y: screenRect.maxY - (actualIslandSize.height * 1.3),
                    width: actualIslandSize.width,
                    height: actualIslandSize.height
                )
                let islandPath = NSBezierPath(roundedRect: islandRect, xRadius: actualIslandSize.height / 2, yRadius: actualIslandSize.height / 2)
                NSColor.black.setFill()
                islandPath.fill()
            }

            // Draw Notch overlay if specified
            if let notchSize = spec?.notchSize {
                let scale = screenSize.width / (spec?.screenPixelSize.width ?? 1.0)
                let actualNotchSize = NSSize(width: notchSize.width * scale, height: notchSize.height * scale)
                let notchRect = NSRect(
                    x: screenRect.midX - (actualNotchSize.width / 2),
                    y: screenRect.maxY - actualNotchSize.height,
                    width: actualNotchSize.width,
                    height: actualNotchSize.height
                )
                let notchPath = NSBezierPath(roundedRect: notchRect, xRadius: actualNotchSize.height * 0.18, yRadius: actualNotchSize.height * 0.18)
                NSColor.black.setFill()
                notchPath.fill()
            }

            // Draw Home Indicator if specified
            if spec?.hasHomeIndicator == true {
                let scale = screenSize.width / (spec?.screenPixelSize.width ?? 1.0)
                let indicatorWidth = 420.0 * scale
                let indicatorHeight = 15.0 * scale
                let indicatorRect = NSRect(
                    x: screenRect.midX - (indicatorWidth / 2),
                    y: screenRect.minY + (24.0 * scale),
                    width: indicatorWidth,
                    height: indicatorHeight
                )
                let indicatorPath = NSBezierPath(roundedRect: indicatorRect, xRadius: indicatorHeight / 2, yRadius: indicatorHeight / 2)
                NSColor.white.withAlphaComponent(0.85).setFill()
                indicatorPath.fill()
            }

            NSGraphicsContext.restoreGraphicsState()

            // Draw high-fidelity dual stroke/metallic bezel appearance
            theme.framedPosterDeviceFrameStroke.nsColor.setStroke()
            framePath.lineWidth = max(2, framePadding * 0.08)
            framePath.stroke()

            // Draw inner bezel highlight for realistic metallic framing
            let innerBezelRect = frameRect.insetBy(dx: 1, dy: 1)
            let innerBezelPath = NSBezierPath(roundedRect: innerBezelRect, xRadius: frameRadius - 1, yRadius: frameRadius - 1)
            NSColor.white.withAlphaComponent(0.08).setStroke()
            innerBezelPath.lineWidth = 1.0
            innerBezelPath.stroke()
        }
        try png.write(to: outputURL, options: [.atomic])
    }

    private func bitmapPixelSize(for image: NSImage) -> NSSize {
        if let bitmap = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { lhs, rhs in lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh }) {
            return NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }
        return image.size
    }

    private func drawFramedPosterBackground(canvasSize: NSSize, theme: ScreenshotTheme) {
        theme.framedPosterBackground.nsColor.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        let upper = NSBezierPath(ovalIn: NSRect(
            x: -canvasSize.width * 0.20,
            y: canvasSize.height * 0.52,
            width: canvasSize.width * 1.35,
            height: canvasSize.height * 0.60
        ))
        theme.framedPosterUpperOval.nsColor.setFill()
        upper.fill()

        let lower = NSBezierPath(ovalIn: NSRect(
            x: canvasSize.width * 0.18,
            y: -canvasSize.height * 0.20,
            width: canvasSize.width * 0.95,
            height: canvasSize.height * 0.48
        ))
        theme.framedPosterLowerOval.nsColor.setFill()
        lower.fill()
    }

    private func drawCenteredText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

    private func drawCenteredTextFitting(
        _ text: String,
        in rect: NSRect,
        maxFontSize: CGFloat,
        minFontSize: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        lineSpacing: CGFloat
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let resolvedFontSize = fittedFontSize(
            for: trimmed,
            in: rect,
            maxFontSize: maxFontSize,
            minFontSize: minFontSize,
            weight: weight,
            lineSpacing: lineSpacing
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = lineSpacing
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: resolvedFontSize, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSString(string: trimmed).draw(in: rect, withAttributes: attributes)
    }

    private func drawCenteredSingleLineTextFitting(
        _ text: String,
        in rect: NSRect,
        maxFontSize: CGFloat,
        minFontSize: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        lineSpacing: CGFloat
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if fitsSingleLine(trimmed, in: rect, fontSize: maxFontSize, weight: weight) {
            drawCenteredTextFitting(
                trimmed,
                in: rect,
                maxFontSize: maxFontSize,
                minFontSize: minFontSize,
                weight: weight,
                color: color,
                lineSpacing: lineSpacing
            )
            return
        }

        let resolvedFontSize = fittedSingleLineFontSize(
            for: trimmed,
            in: rect,
            maxFontSize: maxFontSize,
            minFontSize: minFontSize,
            weight: weight
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let font = NSFont.systemFont(ofSize: resolvedFontSize, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let drawRect = NSRect(
            x: rect.minX,
            y: rect.midY - lineHeight / 2,
            width: rect.width,
            height: lineHeight
        )
        NSString(string: trimmed).draw(in: drawRect, withAttributes: attributes)
    }

    private func fitsSingleLine(
        _ text: String,
        in rect: NSRect,
        fontSize: CGFloat,
        weight: NSFont.Weight
    ) -> Bool {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        let size = NSString(string: text).size(withAttributes: [.font: font])
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return size.width <= rect.width && lineHeight <= rect.height
    }

    private func fittedSingleLineFontSize(
        for text: String,
        in rect: NSRect,
        maxFontSize: CGFloat,
        minFontSize: CGFloat,
        weight: NSFont.Weight
    ) -> CGFloat {
        var fontSize = maxFontSize
        while fontSize > minFontSize {
            let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let size = NSString(string: text).size(withAttributes: attributes)
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            if size.width <= rect.width && lineHeight <= rect.height {
                return fontSize
            }
            fontSize -= max(2, maxFontSize * 0.04)
        }
        return minFontSize
    }

    private func fittedFontSize(
        for text: String,
        in rect: NSRect,
        maxFontSize: CGFloat,
        minFontSize: CGFloat,
        weight: NSFont.Weight,
        lineSpacing: CGFloat
    ) -> CGFloat {
        var fontSize = maxFontSize
        while fontSize > minFontSize {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = lineSpacing
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
                .paragraphStyle: paragraph
            ]
            let bounds = NSString(string: text).boundingRect(
                with: rect.size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            )
            if bounds.height <= rect.height && bounds.width <= rect.width {
                return fontSize
            }
            fontSize -= max(2, maxFontSize * 0.06)
        }
        return minFontSize
    }

    static func inferredTitle(fromFileName fileName: String) -> String {
        prettifiedScreenshotTitle(
            from: canonicalScreenshotCopyStem(
                fromFileName: fileName,
                modeSuffixes: ["-framed-poster", "-device-frame", "-poster"]
            )
        )
    }

    private static func prettifiedScreenshotTitle(from stem: String) -> String {
        stem
            .replacingOccurrences(of: #"^\d+[-_\s]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "-framed-poster", with: "")
            .replacingOccurrences(of: "-device-frame", with: "")
            .replacingOccurrences(of: "-poster", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { token in
                switch token.lowercased() {
                case "bpm":
                    return "BPM"
                case "ios":
                    return "iOS"
                case "ipad":
                    return "iPad"
                default:
                    return token.prefix(1).uppercased() + token.dropFirst().lowercased()
                }
            }
            .joined(separator: " ")
    }

    static func canonicalScreenshotCopyStem(
        fromFileName fileName: String,
        modeSuffixes: [String]
    ) -> String {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let normalizedStem = modeSuffixes.reduce(stem) { partial, suffix in
            partial.replacingOccurrences(of: suffix, with: "")
        }
        let pattern = #"(\d{2}[-_][A-Za-z0-9][A-Za-z0-9_-]*)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(
            in: normalizedStem,
            range: NSRange(location: 0, length: normalizedStem.utf16.count)
           ),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: normalizedStem) {
            return String(normalizedStem[range])
        }
        return normalizedStem
    }

    private func aspectFitSize(source: NSSize, maximum: NSSize) -> NSSize {
        guard source.width > 0, source.height > 0 else {
            return maximum
        }
        let ratio = min(maximum.width / source.width, maximum.height / source.height)
        return NSSize(width: source.width * ratio, height: source.height * ratio)
    }
}
