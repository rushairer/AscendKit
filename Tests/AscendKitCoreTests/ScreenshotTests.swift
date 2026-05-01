import AppKit
import Foundation
import Testing
@testable import AscendKitCore

@Suite("Screenshot readiness")
struct ScreenshotTests {
    @Test("classifies missing user-provided screenshot source as blocker")
    func missingSourceIsBlocker() {
        let plan = ScreenshotPlan(
            inputPath: .userProvided,
            platforms: [.iOS],
            locales: ["en-US"],
            items: [
                ScreenshotPlanItem(id: "home", screenName: "Home", order: 1, purpose: "Show home")
            ]
        )

        let result = ScreenshotReadinessEvaluator().evaluate(plan: plan)

        #expect(result.ready == false)
        #expect(result.findings.contains { $0.id == "screenshots.import.source-missing" && $0.severity == .blocker })
    }

    @Test("generates deterministic coverage warnings from structured input")
    func deterministicPlanCoverage() {
        let input = ScreenshotPlanningInput(
            appCategory: "Productivity",
            targetAudience: "writers",
            positioning: "Structured drafting",
            keyFeatures: ["Outline", "Export"],
            importantScreens: ["Outline Editor"],
            platforms: [.iOS]
        )

        let plan = ScreenshotPlan.makeDeterministicPlan(from: input)

        #expect(plan.items.first?.screenName == "Outline Editor")
        #expect(plan.coverageGaps == ["Export"])
    }

    @Test("builds deterministic local xcodebuild screenshot capture plan")
    func buildsScreenshotCapturePlan() {
        let manifest = ReleaseManifest(
            releaseID: "demo-1.0",
            appSlug: "Demo",
            projects: [
                ProjectReference(kind: .xcworkspace, path: "/tmp/Demo/Demo.xcworkspace")
            ],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    productType: "com.apple.product-type.application"
                )
            ]
        )
        let screenshotPlan = ScreenshotPlan(
            inputPath: .uiTestCapture,
            platforms: [.iOS],
            locales: ["en-US", "zh-Hans"],
            items: [
                ScreenshotPlanItem(id: "home", screenName: "Home", order: 1, purpose: "Show home")
            ]
        )

        let capturePlan = ScreenshotCapturePlanBuilder().build(
            manifest: manifest,
            screenshotPlan: screenshotPlan,
            workspaceRoot: URL(fileURLWithPath: "/tmp/Demo/.ascendkit/releases/demo-1.0")
        )

        #expect(capturePlan.scheme == "Demo")
        #expect(capturePlan.workspacePath == "/tmp/Demo/Demo.xcworkspace")
        #expect(capturePlan.commands.count == 2)
        #expect(capturePlan.destinations.first?.name == "iPhone 17 Pro Max")
        #expect(capturePlan.commands[0].command.contains("-workspace"))
        #expect(capturePlan.commands[0].command.contains("-testLanguage"))
        #expect(capturePlan.commands[0].environment["ASCENDKIT_SCREENSHOT_OUTPUT_DIR"]?.hasSuffix("screenshots/raw/en-US/iOS") == true)
        #expect(capturePlan.findings.isEmpty)
    }

    @Test("discovers and recommends available simulator destinations")
    func discoversRecommendedSimulatorDestinations() {
        let output = """
        == Devices ==
        -- iOS 26.4 --
            iPhone 17 Pro (AAAA) (Shutdown)
            iPhone 17 Pro Max (BBBB) (Shutdown)
            iPad Pro 13-inch (M5) (CCCC) (Shutdown)
            iPad Air 11-inch (M4) (DDDD) (Shutdown)
        """

        let report = ScreenshotDestinationDiscoverer().discover(
            simctlOutput: output,
            requestedPlatforms: [.iOS, .iPadOS]
        )

        #expect(report.recommendedDestinations.map(\.name) == ["iPhone 17 Pro Max", "iPad Pro 13-inch (M5)"])
        #expect(report.recommendedDestinations.map(\.xcodebuildDestination) == [
            "platform=iOS Simulator,name=iPhone 17 Pro Max",
            "platform=iOS Simulator,name=iPad Pro 13-inch (M5)"
        ])
        #expect(report.findings.isEmpty)
    }

    @Test("uses discovered destinations when building capture plans")
    func usesDiscoveredDestinationsForCapturePlan() {
        let manifest = ReleaseManifest(
            releaseID: "demo-1.0",
            appSlug: "Demo",
            projects: [ProjectReference(kind: .xcodeproj, path: "/tmp/Demo/Demo.xcodeproj")],
            targets: [
                BundleTarget(name: "Demo", platform: .iOS, productType: "com.apple.product-type.application")
            ]
        )
        let screenshotPlan = ScreenshotPlan(
            inputPath: .uiTestCapture,
            platforms: [.iOS],
            locales: ["en-US"],
            items: [ScreenshotPlanItem(id: "home", screenName: "Home", order: 1, purpose: "Show home")]
        )

        let capturePlan = ScreenshotCapturePlanBuilder().build(
            manifest: manifest,
            screenshotPlan: screenshotPlan,
            workspaceRoot: URL(fileURLWithPath: "/tmp/Demo/.ascendkit/releases/demo-1.0"),
            discoveredDestinations: [
                ScreenshotCaptureDestination(
                    platform: .iOS,
                    name: "iPhone 17",
                    xcodebuildDestination: "platform=iOS Simulator,name=iPhone 17"
                )
            ]
        )

        #expect(capturePlan.destinations.map(\.name) == ["iPhone 17"])
        #expect(capturePlan.commands.first?.command.contains("platform=iOS Simulator,name=iPhone 17") == true)
    }

    @Test("executes screenshot capture command and records output files")
    func executesScreenshotCaptureCommand() throws {
        let root = try TemporaryDirectory()
        let rawDirectory = root.url.appendingPathComponent("screenshots/raw/en-US/iOS")
        let plan = ScreenshotCapturePlan(
            scheme: "Demo",
            projectPath: "/tmp/Demo.xcodeproj",
            destinations: [
                ScreenshotCaptureDestination(
                    platform: .iOS,
                    name: "Test Device",
                    xcodebuildDestination: "platform=iOS Simulator,name=Test Device"
                )
            ],
            locales: ["en-US"],
            commands: [
                ScreenshotCaptureCommand(
                    locale: "en-US",
                    platform: .iOS,
                    destinationName: "Test Device",
                    resultBundlePath: root.url.appendingPathComponent("capture/result.xcresult").path,
                    rawOutputDirectory: rawDirectory.path,
                    environment: ["ASCENDKIT_SCREENSHOT_OUTPUT_DIR": rawDirectory.path],
                    command: [
                        "/bin/sh",
                        "-c",
                        "mkdir -p \"$ASCENDKIT_SCREENSHOT_OUTPUT_DIR\" && printf fake > \"$ASCENDKIT_SCREENSHOT_OUTPUT_DIR/01-home.png\""
                    ]
                )
            ]
        )

        let result = try ScreenshotCaptureExecutor().execute(
            plan: plan,
            logsDirectory: root.url.appendingPathComponent("logs")
        )

        #expect(result.executed)
        #expect(result.succeeded)
        #expect(result.succeededCount == 1)
        #expect(result.items.first?.outputFiles.map { URL(fileURLWithPath: $0).lastPathComponent } == ["01-home.png"])
        #expect(FileManager.default.fileExists(atPath: result.items[0].stdoutLogPath ?? ""))
        #expect(FileManager.default.fileExists(atPath: result.items[0].stderrLogPath ?? ""))
    }

    @Test("serializes local screenshot workflow result")
    func serializesLocalScreenshotWorkflowResult() throws {
        let result = ScreenshotLocalWorkflowResult(
            succeeded: true,
            capturePlanPath: "/tmp/capture-plan.json",
            captureResultPath: "/tmp/capture-result.json",
            importManifestPath: "/tmp/import.json",
            compositionManifestPath: "/tmp/composition.json",
            compositionMode: .framedPoster,
            capturedFileCount: 3,
            composedArtifactCount: 3
        )

        let decoded = try AscendKitJSON.decoder.decode(
            ScreenshotLocalWorkflowResult.self,
            from: AscendKitJSON.encoder.encode(result)
        )

        #expect(decoded.succeeded)
        #expect(decoded.compositionMode == .framedPoster)
        #expect(decoded.capturedFileCount == 3)
        #expect(decoded.composedArtifactCount == 3)
    }

    @Test("summarizes screenshot workflow status")
    func summarizesScreenshotWorkflowStatus() {
        let report = ScreenshotWorkflowStatusBuilder().build(
            capturePlan: ScreenshotCapturePlan(
                scheme: "Demo",
                destinations: [ScreenshotCaptureDestination(platform: .iOS, name: "iPhone", xcodebuildDestination: "platform=iOS Simulator,name=iPhone")],
                locales: ["en-US"],
                commands: []
            ),
            captureResult: ScreenshotCaptureExecutionResult(
                executed: true,
                items: [
                    ScreenshotCaptureExecutionItem(
                        commandID: "en-US:iOS:iPhone",
                        locale: "en-US",
                        platform: .iOS,
                        destinationName: "iPhone",
                        exitCode: 0,
                        resultBundlePath: "/tmp/result.xcresult",
                        rawOutputDirectory: "/tmp/raw",
                        outputFiles: ["/tmp/raw/01.png"],
                        durationSeconds: 1
                    )
                ]
            ),
            importManifest: ScreenshotImportManifest(
                sourceDirectory: "/tmp/raw",
                artifacts: [ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/raw/01.png", fileName: "01.png")]
            ),
            copyLintReport: ScreenshotCompositionCopyLintReport(
                checkedArtifactCount: 1,
                copyItemCount: 1
            ),
            compositionManifest: ScreenshotCompositionManifest(
                mode: .framedPoster,
                artifacts: [
                    ScreenshotCompositionArtifact(
                        locale: "en-US",
                        platform: .iOS,
                        inputPath: "/tmp/raw/01.png",
                        outputPath: "/tmp/composed/01.png",
                        mode: .framedPoster
                    )
                ]
            ),
            workflowResult: ScreenshotLocalWorkflowResult(
                succeeded: true,
                capturePlanPath: "/tmp/capture-plan.json",
                captureResultPath: "/tmp/capture-result.json",
                importManifestPath: "/tmp/import.json",
                compositionManifestPath: "/tmp/composition.json",
                compositionMode: .framedPoster,
                capturedFileCount: 1,
                composedArtifactCount: 1
            )
        )

        #expect(report.readyForUploadPlan)
        #expect(report.steps.map(\.state).allSatisfy { $0 == .complete })
        #expect(report.steps.contains { $0.id == "copy-lint" })
        #expect(report.findings.isEmpty)
    }

    @Test("summarizes screenshot upload retry status")
    func summarizesScreenshotUploadRetryStatus() {
        let plan = ScreenshotUploadPlan(
            sourceKind: .composed,
            items: [
                ScreenshotUploadPlanItem(
                    locale: "en-US",
                    platform: .iOS,
                    displayType: "APP_IPHONE_67",
                    appStoreVersionLocalizationID: "version-loc-1",
                    sourcePath: "/tmp/home.png",
                    fileName: "home.png",
                    order: 1
                ),
                ScreenshotUploadPlanItem(
                    locale: "en-US",
                    platform: .iOS,
                    displayType: "APP_IPHONE_67",
                    appStoreVersionLocalizationID: "version-loc-1",
                    sourcePath: "/tmp/settings.png",
                    fileName: "settings.png",
                    order: 2
                )
            ]
        )
        let result = ScreenshotUploadExecutionResult(
            executed: true,
            uploadedCount: 1,
            findings: ["Screenshot upload completed with 1 failure(s); inspect failedItems before retrying."],
            failedItems: [
                ScreenshotUploadFailure(
                    phase: "upload",
                    planItemID: "en-US:iOS:APP_IPHONE_67:2:settings.png",
                    fileName: "settings.png",
                    message: "fixture failure"
                )
            ]
        )

        let status = ScreenshotUploadStatusBuilder().build(plan: plan, result: result)

        #expect(status.plannedCount == 2)
        #expect(status.executed == true)
        #expect(status.uploadedCount == 1)
        #expect(status.failedCount == 1)
        #expect(status.readyForRetry)
        #expect(status.retryPlanItemIDs == ["en-US:iOS:APP_IPHONE_67:2:settings.png"])
        #expect(status.nextActions.contains { $0.contains("rerun screenshots upload") })
    }

    @Test("summarizes screenshot locale and display type coverage")
    func summarizesScreenshotCoverage() {
        let plan = ScreenshotPlan(
            inputPath: .uiTestCapture,
            platforms: [.iOS],
            locales: ["en-US", "zh-Hans"],
            items: [
                ScreenshotPlanItem(id: "home", screenName: "Home", order: 1, purpose: "Show home"),
                ScreenshotPlanItem(id: "settings", screenName: "Settings", order: 2, purpose: "Show settings")
            ]
        )
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: "/tmp/raw",
            artifacts: [
                ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/raw/en-US/01.png", fileName: "01.png"),
                ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/raw/en-US/02.png", fileName: "02.png"),
                ScreenshotArtifact(locale: "zh-Hans", platform: .iOS, path: "/tmp/raw/zh-Hans/01.png", fileName: "01.png")
            ]
        )
        let compositionManifest = ScreenshotCompositionManifest(
            mode: .framedPoster,
            artifacts: [
                ScreenshotCompositionArtifact(locale: "en-US", platform: .iOS, inputPath: "/tmp/raw/en-US/01.png", outputPath: "/tmp/out/en-US/01.png", mode: .framedPoster),
                ScreenshotCompositionArtifact(locale: "en-US", platform: .iOS, inputPath: "/tmp/raw/en-US/02.png", outputPath: "/tmp/out/en-US/02.png", mode: .framedPoster),
                ScreenshotCompositionArtifact(locale: "zh-Hans", platform: .iOS, inputPath: "/tmp/raw/zh-Hans/01.png", outputPath: "/tmp/out/zh-Hans/01.png", mode: .framedPoster)
            ]
        )
        let uploadPlan = ScreenshotUploadPlan(
            sourceKind: .composed,
            items: [
                ScreenshotUploadPlanItem(locale: "en-US", platform: .iOS, displayType: "APP_IPHONE_67", appStoreVersionLocalizationID: "loc-1", sourcePath: "/tmp/out/en-US/01.png", fileName: "01.png", order: 1),
                ScreenshotUploadPlanItem(locale: "en-US", platform: .iOS, displayType: "APP_IPHONE_67", appStoreVersionLocalizationID: "loc-1", sourcePath: "/tmp/out/en-US/02.png", fileName: "02.png", order: 2)
            ]
        )

        let report = ScreenshotCoverageBuilder().build(
            plan: plan,
            importManifest: importManifest,
            compositionManifest: compositionManifest,
            uploadPlan: uploadPlan
        )

        #expect(report.complete == false)
        #expect(report.entries.contains {
            $0.locale == "en-US" &&
                $0.displayType == "APP_IPHONE_67" &&
                $0.importedCount == 2 &&
                $0.composedCount == 2 &&
                $0.uploadPlanCount == 2 &&
                $0.complete
        })
        #expect(report.entries.contains {
            $0.locale == "zh-Hans" &&
                $0.displayType == nil &&
                $0.importedCount == 1 &&
                $0.composedCount == 1 &&
                !$0.complete
        })
        #expect(report.findings.contains { $0.contains("zh-Hans/iOS") })
    }

    @Test("creates screenshot copy template from plan")
    func createsScreenshotCopyTemplateFromPlan() {
        let plan = ScreenshotPlan(
            inputPath: .uiTestCapture,
            platforms: [.iOS, .iPadOS],
            locales: ["en-US"],
            items: [
                ScreenshotPlanItem(id: "today", screenName: "Today", order: 1, purpose: "Show today focus"),
                ScreenshotPlanItem(id: "history", screenName: "History", order: 2, purpose: "Show past entries")
            ]
        )

        let copy = ScreenshotCompositionCopyTemplateBuilder().build(plan: plan, locale: "en-US")

        #expect(copy.items.count == 4)
        #expect(copy.items[0] == ScreenshotCompositionCopy(
            locale: "en-US",
            platform: .iOS,
            fileName: "01-today.png",
            title: "Today",
            subtitle: "Show today focus"
        ))
        #expect(copy.items[2].platform == .iPadOS)
        #expect(copy.items[3].fileName == "02-history.png")
    }

    @Test("refreshes screenshot copy template while preserving edited copy")
    func refreshesScreenshotCopyTemplateWhilePreservingEditedCopy() {
        let plan = ScreenshotPlan(
            inputPath: .uiTestCapture,
            platforms: [.iOS],
            locales: ["en-US"],
            items: [
                ScreenshotPlanItem(id: "today", screenName: "Today", order: 1, purpose: "Show today focus"),
                ScreenshotPlanItem(id: "settings", screenName: "Settings", order: 2, purpose: "Show settings")
            ]
        )
        let existing = ScreenshotCompositionCopyManifest(items: [
            ScreenshotCompositionCopy(
                locale: "en-US",
                platform: .iOS,
                fileName: "01-today.png",
                title: "Choose Three",
                subtitle: "Keep today simple"
            ),
            ScreenshotCompositionCopy(
                locale: "en-US",
                platform: .iOS,
                fileName: "03-stale.png",
                title: "Stale"
            )
        ])

        let refreshed = ScreenshotCompositionCopyTemplateBuilder().refresh(
            plan: plan,
            existing: existing,
            locale: "en-US"
        )

        #expect(refreshed.items.count == 2)
        #expect(refreshed.items[0].title == "Choose Three")
        #expect(refreshed.items[0].subtitle == "Keep today simple")
        #expect(refreshed.items[1].fileName == "02-settings.png")
        #expect(refreshed.items[1].title == "Settings")
        #expect(refreshed.items.contains { $0.fileName == "03-stale.png" } == false)
    }

    @Test("lints screenshot copy coverage against imported artifacts")
    func lintsScreenshotCopyCoverage() {
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: "/tmp/raw",
            artifacts: [
                ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/raw/01-today.png", fileName: "01-today.png"),
                ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/raw/02-history.png", fileName: "02-history.png")
            ]
        )
        let copyManifest = ScreenshotCompositionCopyManifest(items: [
            ScreenshotCompositionCopy(
                locale: "en-US",
                platform: .iOS,
                fileName: "01-today.png",
                title: "Today"
            ),
            ScreenshotCompositionCopy(
                locale: "en-US",
                platform: .iOS,
                fileName: "03-settings.png",
                title: "Settings"
            )
        ])

        let report = ScreenshotCompositionCopyLinter().lint(
            importManifest: importManifest,
            copyManifest: copyManifest
        )

        #expect(report.valid == false)
        #expect(report.checkedArtifactCount == 2)
        #expect(report.copyItemCount == 2)
        #expect(report.findings.contains("Missing copy for en-US/iOS/02-history.png."))
        #expect(report.findings.contains("Stale copy item for en-US/iOS/03-settings.png."))
    }

    @Test("validates user-provided import directory structure and image counts")
    func validatesImportDirectoryStructure() throws {
        let root = try TemporaryDirectory()
        let platformDirectory = root.url
            .appendingPathComponent("en-US")
            .appendingPathComponent("iOS")
        try FileManager.default.createDirectory(at: platformDirectory, withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: platformDirectory.appendingPathComponent("home.png"))

        let plan = ScreenshotPlan(
            inputPath: .userProvided,
            platforms: [.iOS],
            locales: ["en-US"],
            items: [
                ScreenshotPlanItem(id: "home", screenName: "Home", order: 1, purpose: "Show home"),
                ScreenshotPlanItem(id: "settings", screenName: "Settings", order: 2, purpose: "Show settings")
            ],
            sourceDirectory: root.url.path
        )

        let result = ScreenshotReadinessEvaluator().evaluate(plan: plan)

        #expect(result.ready == false)
        #expect(result.findings.contains { $0.id == "screenshots.import.en-US.iOS.count" })
    }

    @Test("creates screenshot import manifest from ready source directory")
    func createsImportManifest() throws {
        let root = try TemporaryDirectory()
        let platformDirectory = root.url
            .appendingPathComponent("en-US")
            .appendingPathComponent("iOS")
        try FileManager.default.createDirectory(at: platformDirectory, withIntermediateDirectories: true)
        let first = platformDirectory.appendingPathComponent("01-home.png")
        let second = platformDirectory.appendingPathComponent("02-settings.jpg")
        try Data("fake".utf8).write(to: first)
        try Data("fake".utf8).write(to: second)

        let plan = ScreenshotPlan(
            inputPath: .userProvided,
            platforms: [.iOS],
            locales: ["en-US"],
            items: [
                ScreenshotPlanItem(id: "home", screenName: "Home", order: 1, purpose: "Show home"),
                ScreenshotPlanItem(id: "settings", screenName: "Settings", order: 2, purpose: "Show settings")
            ]
        )

        let readiness = ScreenshotReadinessEvaluator().evaluate(plan: plan, sourceDirectory: root.url)
        let manifest = ScreenshotImporter().makeManifest(plan: plan, sourceDirectory: root.url)

        #expect(readiness.ready)
        #expect(manifest.artifacts.map(\.fileName) == ["01-home.png", "02-settings.jpg"])
    }

    @Test("creates screenshot import manifest from fastlane flat screenshots")
    func createsFastlaneImportManifest() throws {
        let root = try TemporaryDirectory()
        let localeDirectory = root.url.appendingPathComponent("en-US")
        try FileManager.default.createDirectory(at: localeDirectory, withIntermediateDirectories: true)
        let iPhone = localeDirectory.appendingPathComponent("iPhone 17 Pro Max-01_home.png")
        let iPad = localeDirectory.appendingPathComponent("iPad Pro 13-inch (M5)-01_home.png")
        let framed = localeDirectory.appendingPathComponent("iPhone 17 Pro Max-01_home_framed.png")
        try Data("fake".utf8).write(to: iPhone)
        try Data("fake".utf8).write(to: iPad)
        try Data("fake".utf8).write(to: framed)

        let manifest = ScreenshotImporter().makeFastlaneManifest(sourceDirectory: root.url)

        #expect(manifest.artifacts.count == 2)
        #expect(manifest.artifacts.contains { $0.fileName == iPhone.lastPathComponent && $0.platform == .iOS })
        #expect(manifest.artifacts.contains { $0.fileName == iPad.lastPathComponent && $0.platform == .iPadOS })
        #expect(manifest.artifacts.contains { $0.fileName == framed.lastPathComponent } == false)
    }

    @Test("composes imported screenshots into output manifest")
    func composesScreenshots() throws {
        let root = try TemporaryDirectory()
        let input = root.url.appendingPathComponent("source/en-US/iOS/01-home.png")
        try FileManager.default.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake-image".utf8).write(to: input)
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: root.url.appendingPathComponent("source").path,
            artifacts: [
                ScreenshotArtifact(locale: "en-US", platform: .iOS, path: input.path, fileName: "01-home.png")
            ]
        )

        let outputRoot = root.url.appendingPathComponent("composed")
        let manifest = try ScreenshotComposer().compose(
            importManifest: importManifest,
            outputRoot: outputRoot,
            mode: .storeReadyCopy
        )

        #expect(manifest.artifacts.count == 1)
        #expect(FileManager.default.fileExists(atPath: manifest.artifacts[0].outputPath))
        #expect(manifest.artifacts[0].mode == .storeReadyCopy)
    }

    @Test("builds ASC screenshot upload plan from imported artifacts")
    func buildsScreenshotUploadPlan() throws {
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: "/tmp/screenshots",
            artifacts: [
                ScreenshotArtifact(
                    locale: "en-US",
                    platform: .iOS,
                    path: "/tmp/screenshots/en-US/iOS/01-home.png",
                    fileName: "01-home.png"
                )
            ]
        )
        let observed = MetadataObservedState(
            metadataByLocale: [
                "en-US": AppMetadata(
                    locale: "en-US",
                    name: "Demo",
                    description: "Demo description"
                )
            ],
            resourceIDsByLocale: [
                "en-US": MetadataLocalizationResourceIDs(appStoreVersionLocalizationID: "version-loc-1")
            ]
        )

        let plan = ScreenshotUploadPlanBuilder().build(
            importManifest: importManifest,
            compositionManifest: nil,
            observedState: observed
        )

        #expect(plan.dryRunOnly)
        #expect(plan.sourceKind == ScreenshotUploadSourceKind.imported)
        #expect(plan.items.count == 1)
        #expect(plan.items[0].displayType == "APP_IPHONE_67")
        #expect(plan.items[0].appStoreVersionLocalizationID == "version-loc-1")
        #expect(plan.findings.isEmpty)
    }

    @Test("blocks screenshot upload plan when ASC already has screenshots for target set")
    func blocksScreenshotUploadPlanWithExistingRemoteScreenshots() throws {
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: "/tmp/screenshots",
            artifacts: [
                ScreenshotArtifact(
                    locale: "en-US",
                    platform: .iOS,
                    path: "/tmp/screenshots/en-US/iOS/01-home.png",
                    fileName: "01-home.png"
                )
            ]
        )
        let observed = MetadataObservedState(
            metadataByLocale: [
                "en-US": AppMetadata(
                    locale: "en-US",
                    name: "Demo",
                    description: "Demo description"
                )
            ],
            resourceIDsByLocale: [
                "en-US": MetadataLocalizationResourceIDs(appStoreVersionLocalizationID: "version-loc-1")
            ],
            screenshotSetsByLocale: [
                "en-US": [
                    ObservedScreenshotSet(
                        id: "set-1",
                        displayType: "APP_IPHONE_67",
                        screenshots: [
                            ObservedScreenshot(id: "screenshot-1", fileName: "old-home.png", assetDeliveryState: "COMPLETE")
                        ]
                    )
                ]
            ]
        )

        let plan = ScreenshotUploadPlanBuilder().build(
            importManifest: importManifest,
            compositionManifest: nil,
            observedState: observed
        )

        #expect(plan.items.count == 1)
        #expect(plan.findings.contains { $0.contains("ASC already has 1 screenshot(s) for en-US/APP_IPHONE_67") })
        #expect(plan.findings.contains { $0.contains("old-home.png") })
    }

    @Test("plans explicit remote screenshot deletion when replacing existing screenshots")
    func plansRemoteScreenshotDeletionForReplacement() throws {
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: "/tmp/screenshots",
            artifacts: [
                ScreenshotArtifact(
                    locale: "en-US",
                    platform: .iOS,
                    path: "/tmp/screenshots/en-US/iOS/01-home.png",
                    fileName: "01-home.png"
                )
            ]
        )
        let observed = MetadataObservedState(
            metadataByLocale: [
                "en-US": AppMetadata(locale: "en-US", name: "Demo", description: "Demo description")
            ],
            resourceIDsByLocale: [
                "en-US": MetadataLocalizationResourceIDs(appStoreVersionLocalizationID: "version-loc-1")
            ],
            screenshotSetsByLocale: [
                "en-US": [
                    ObservedScreenshotSet(
                        id: "set-1",
                        displayType: "APP_IPHONE_67",
                        screenshots: [
                            ObservedScreenshot(id: "screenshot-1", fileName: "old-home.png", assetDeliveryState: "COMPLETE")
                        ]
                    )
                ]
            ]
        )

        let plan = ScreenshotUploadPlanBuilder().build(
            importManifest: importManifest,
            compositionManifest: nil,
            observedState: observed,
            replaceExistingRemoteScreenshots: true
        )

        #expect(plan.findings.isEmpty)
        #expect(plan.replaceExistingRemoteScreenshots == true)
        #expect(plan.remoteScreenshotsToDelete?.count == 1)
        #expect(plan.remoteScreenshotsToDelete?.first?.appScreenshotID == "screenshot-1")
        #expect(plan.remoteScreenshotsToDelete?.first?.fileName == "old-home.png")
    }

    @Test("renders poster composition as a PNG artifact")
    func rendersPosterComposition() throws {
        let root = try TemporaryDirectory()
        let input = root.url.appendingPathComponent("source/en-US/iOS/01-home.png")
        try FileManager.default.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makePNG(size: NSSize(width: 390, height: 844), url: input)
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: root.url.appendingPathComponent("source").path,
            artifacts: [
                ScreenshotArtifact(locale: "en-US", platform: .iOS, path: input.path, fileName: "01-home.png")
            ]
        )

        let manifest = try ScreenshotComposer().compose(
            importManifest: importManifest,
            outputRoot: root.url.appendingPathComponent("composed"),
            mode: .poster
        )

        #expect(manifest.artifacts.count == 1)
        #expect(manifest.artifacts[0].outputPath.hasSuffix("01-home-poster.png"))
        #expect(NSImage(contentsOfFile: manifest.artifacts[0].outputPath)?.isValid == true)
    }

    @Test("renders device frame composition as a PNG artifact")
    func rendersDeviceFrameComposition() throws {
        let root = try TemporaryDirectory()
        let input = root.url.appendingPathComponent("source/en-US/iOS/01-home.png")
        try FileManager.default.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makePNG(size: NSSize(width: 390, height: 844), url: input)
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: root.url.appendingPathComponent("source").path,
            artifacts: [
                ScreenshotArtifact(locale: "en-US", platform: .iOS, path: input.path, fileName: "01-home.png")
            ]
        )

        let manifest = try ScreenshotComposer().compose(
            importManifest: importManifest,
            outputRoot: root.url.appendingPathComponent("composed"),
            mode: .deviceFrame
        )

        #expect(manifest.artifacts.count == 1)
        #expect(manifest.artifacts[0].outputPath.hasSuffix("01-home-device-frame.png"))
        #expect(NSImage(contentsOfFile: manifest.artifacts[0].outputPath)?.isValid == true)
    }

    @Test("renders framed poster composition at original screenshot size")
    func rendersFramedPosterCompositionAtOriginalSize() throws {
        let root = try TemporaryDirectory()
        let input = root.url.appendingPathComponent("source/en-US/iOS/01-home.png")
        try FileManager.default.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makePNG(size: NSSize(width: 1_320, height: 2_868), url: input)
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: root.url.appendingPathComponent("source").path,
            artifacts: [
                ScreenshotArtifact(locale: "en-US", platform: .iOS, path: input.path, fileName: "01-home.png")
            ]
        )
        let copyManifest = ScreenshotCompositionCopyManifest(items: [
            ScreenshotCompositionCopy(
                locale: "en-US",
                platform: .iOS,
                fileName: "01-home.png",
                title: "Choose Three",
                subtitle: "Keep today simple"
            )
        ])

        let manifest = try ScreenshotComposer().compose(
            importManifest: importManifest,
            outputRoot: root.url.appendingPathComponent("composed"),
            mode: .framedPoster,
            copyManifest: copyManifest
        )

        let output = try #require(NSImage(contentsOfFile: manifest.artifacts[0].outputPath))
        let rep = try #require(output.representations.first)
        #expect(manifest.artifacts.count == 1)
        #expect(manifest.artifacts[0].outputPath.hasSuffix("01-home-framed-poster.png"))
        #expect(manifest.artifacts[0].mode == .framedPoster)
        #expect(rep.pixelsWide == 1_320)
        #expect(rep.pixelsHigh == 2_868)
    }

    private func makePNG(size: NSSize, url: URL) throws {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.20, green: 0.34, blue: 0.52, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AscendKitError.invalidState("Failed to create test PNG")
        }
        try png.write(to: url)
    }
}
