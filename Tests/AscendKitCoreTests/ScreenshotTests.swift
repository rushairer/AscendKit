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
            workspaceRoot: URL(fileURLWithPath: "/tmp/Demo/.ascendkit/releases/demo-1.0"),
            onlyTesting: ["DemoUITests/DemoUITests/testSnapshots"]
        )

        #expect(capturePlan.scheme == "Demo")
        #expect(capturePlan.workspacePath == "/tmp/Demo/Demo.xcworkspace")
        #expect(capturePlan.commands.count == 2)
        #expect(capturePlan.destinations.first?.name == "iPhone 17 Pro Max")
        #expect(capturePlan.commands[0].command.contains("-workspace"))
        #expect(capturePlan.commands[0].command.contains("-testLanguage"))
        #expect(capturePlan.commands[0].command.contains("-only-testing:DemoUITests/DemoUITests/testSnapshots"))
        #expect(capturePlan.commands[0].environment["ASCENDKIT_SCREENSHOT_OUTPUT_DIR"]?.hasSuffix("screenshots/raw/en-US/iOS") == true)
        let zhCommand = capturePlan.commands[1].command
        #expect(argumentValue(after: "-testLanguage", in: zhCommand) == "zh-Hans")
        #expect(argumentValue(after: "-testRegion", in: zhCommand) == nil)
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

    @Test("screenshot doctor guides projects without UI test automation")
    func screenshotDoctorGuidesMissingUITestAutomation() throws {
        let manifest = ReleaseManifest(
            releaseID: "demo-1.0",
            appSlug: "Demo",
            projects: [ProjectReference(kind: .xcworkspace, path: "/tmp/Demo/Demo.xcworkspace")],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    productType: "com.apple.product-type.application"
                )
            ]
        )

        let report = ScreenshotDoctor().diagnose(
            manifest: manifest,
            screenshotPlan: nil,
            recommendedDestinations: []
        )

        #expect(report.readyForDeterministicCapture == false)
        #expect(report.projectReference?.path == "/tmp/Demo/Demo.xcworkspace")
        #expect(report.appTargetName == "Demo")
        #expect(report.uiTestTargetNames.isEmpty)
        #expect(report.platforms == [.iOS])
        #expect(report.screenshotPlanPresent == false)
        #expect(report.findings.contains { $0.id == "screenshots.doctor.uitest-target.missing" && $0.severity == .blocker })
        #expect(report.findings.contains { $0.id == "screenshots.doctor.plan.missing" && $0.severity == .blocker })
        #expect(report.findings.contains { $0.id == "screenshots.doctor.destinations.missing" && $0.severity == .warning })
        #expect(report.uiTestGuidance.contains { $0.contains("UI Tests") })
        #expect(report.uiTestAgentPrompt.contains("no real credentials"))
        #expect(report.nextCommands.contains("screenshots scaffold-uitests --workspace PATH --json"))
        #expect(report.nextCommands.contains("screenshots capture-plan --workspace PATH --json"))
        let scaffoldIndex = try #require(report.nextCommands.firstIndex(of: "screenshots scaffold-uitests --workspace PATH --json"))
        let capturePlanIndex = try #require(report.nextCommands.firstIndex(of: "screenshots capture-plan --workspace PATH --json"))
        #expect(scaffoldIndex < capturePlanIndex)
        #expect(report.platformSupport.contains {
            $0.platform == .iOS &&
                $0.deterministicCapture == "default-supported" &&
                $0.appStoreDisplayType == "APP_IPHONE_67"
        })
    }

    @Test("screenshot doctor reports UI test readiness signals")
    func screenshotDoctorReportsUITestReadinessSignals() {
        let manifest = ReleaseManifest(
            releaseID: "demo-1.0",
            appSlug: "Demo",
            projects: [ProjectReference(kind: .xcodeproj, path: "/tmp/Demo/Demo.xcodeproj")],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    productType: "com.apple.product-type.application"
                ),
                BundleTarget(
                    name: "DemoUITests",
                    platform: .iOS,
                    productType: "com.apple.product-type.bundle.ui-testing"
                )
            ]
        )
        let plan = ScreenshotPlan(
            inputPath: .uiTestCapture,
            platforms: [.iOS, .iPadOS],
            locales: ["en-US"],
            items: [
                ScreenshotPlanItem(id: "home", screenName: "Home", order: 1, purpose: "Show home")
            ]
        )

        let report = ScreenshotDoctor().diagnose(
            manifest: manifest,
            screenshotPlan: plan,
            recommendedDestinations: [
                ScreenshotCaptureDestination(
                    platform: .iOS,
                    name: "iPhone 17 Pro Max",
                    xcodebuildDestination: "platform=iOS Simulator,name=iPhone 17 Pro Max"
                )
            ]
        )

        #expect(report.readyForDeterministicCapture == true)
        #expect(report.uiTestTargetNames == ["DemoUITests"])
        #expect(report.platforms == [.iOS, .iPadOS])
        #expect(report.locales == ["en-US"])
        #expect(report.recommendedDestinations.count == 1)
        #expect(report.screenshotPlanPresent == true)
        #expect(report.findings.contains { $0.id == "screenshots.doctor.uitest-target.present" && $0.severity == .info })
        #expect(!report.findings.contains { $0.severity == .blocker })
        #expect(!report.nextCommands.contains("screenshots scaffold-uitests --workspace PATH --json"))
    }

    @Test("screenshot doctor explains non-default platform capture support")
    func screenshotDoctorExplainsNonDefaultPlatformCaptureSupport() {
        let manifest = ReleaseManifest(
            releaseID: "demo-1.0",
            appSlug: "Demo",
            projects: [ProjectReference(kind: .xcodeproj, path: "/tmp/Demo/Demo.xcodeproj")],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .visionOS,
                    productType: "com.apple.product-type.application"
                ),
                BundleTarget(
                    name: "DemoUITests",
                    platform: .visionOS,
                    productType: "com.apple.product-type.bundle.ui-testing"
                )
            ]
        )
        let plan = ScreenshotPlan(
            inputPath: .uiTestCapture,
            platforms: [.tvOS, .watchOS, .visionOS],
            locales: ["en-US"],
            items: [
                ScreenshotPlanItem(id: "home", screenName: "Home", order: 1, purpose: "Show home")
            ]
        )

        let report = ScreenshotDoctor().diagnose(
            manifest: manifest,
            screenshotPlan: plan,
            recommendedDestinations: []
        )

        #expect(report.platformSupport.map(\.platform) == [.tvOS, .visionOS, .watchOS])
        #expect(report.platformSupport.allSatisfy { $0.deterministicCapture == "explicit-destination-required" })
        #expect(report.platformSupport.contains { $0.platform == .tvOS && $0.appStoreDisplayType == "APP_APPLE_TV" })
        #expect(report.platformSupport.contains { $0.platform == .watchOS && $0.appStoreDisplayType == "APP_WATCH_ULTRA" })
        #expect(report.platformSupport.contains { $0.platform == .visionOS && $0.appStoreDisplayType == "APP_VISION_PRO" })
        #expect(report.platformSupport.allSatisfy { $0.compositionSupport.contains("framedPoster") })
    }

    @Test("builds safe UI test scaffold from screenshot plan")
    func buildsSafeUITestScaffold() {
        let manifest = ReleaseManifest(
            releaseID: "demo-1.0",
            appSlug: "Demo",
            projects: [ProjectReference(kind: .xcodeproj, path: "/tmp/Demo/Demo.xcodeproj")],
            targets: [
                BundleTarget(name: "Demo", platform: .iOS, productType: "com.apple.product-type.application"),
                BundleTarget(name: "DemoUITests", platform: .iOS, productType: "com.apple.product-type.bundle.ui-testing")
            ]
        )
        let plan = ScreenshotPlan(
            inputPath: .uiTestCapture,
            platforms: [.iOS],
            locales: ["en-US"],
            items: [
                ScreenshotPlanItem(id: "home", screenName: "Home", order: 1, purpose: "Show home"),
                ScreenshotPlanItem(id: "premium-upgrade", screenName: "Premium Upgrade", order: 2, purpose: "Show upgrade path")
            ]
        )

        let result = ScreenshotUITestScaffoldBuilder().build(
            manifest: manifest,
            screenshotPlan: plan,
            outputURL: URL(fileURLWithPath: "/tmp/Demo/AscendKitScreenshotUITests.swift")
        )

        #expect(result.appTargetName == "Demo")
        #expect(result.uiTestTargetNames == ["DemoUITests"])
        #expect(result.screenCount == 2)
        #expect(result.launchArguments.contains("--ascendkit-screenshot-mode"))
        #expect(result.environmentKeys.contains("ASCENDKIT_SCREENSHOT_OUTPUT_DIR"))
        #expect(result.navigationPlaceholders.map(\.outputFileName) == ["01-home.png", "02-premium-upgrade.png"])
        #expect(result.navigationPlaceholders.first?.screenName == "Home")
        #expect(result.navigationPlaceholders.first?.replacementGuidance.contains("without real credentials") == true)
        #expect(result.swiftSource.contains("final class AscendKitScreenshotUITests"))
        #expect(result.swiftSource.contains("captureScreenshot(named: \"01-home.png\")"))
        #expect(result.swiftSource.contains("captureScreenshot(named: \"02-premium-upgrade.png\")"))
        #expect(result.swiftSource.contains("XCTAttachment(screenshot: screenshot)"))
        #expect(result.swiftSource.contains("ASCENDKIT_SCREENSHOT_OUTPUT_DIR"))
        #expect(result.instructions.contains { $0.contains("Do not use real credentials") })
        #expect(result.agentPrompt.contains("avoid real credentials"))
        #expect(!result.swiftSource.localizedCaseInsensitiveContains("password"))
        #expect(!result.swiftSource.localizedCaseInsensitiveContains("token"))
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
        #expect(result.ascendKitVersion == AscendKitVersion.current)
        #expect(result.succeeded)
        #expect(result.succeededCount == 1)
        #expect(result.items.first?.outputFiles.map { URL(fileURLWithPath: $0).lastPathComponent } == ["01-home.png"])
        #expect(FileManager.default.fileExists(atPath: result.items[0].stdoutLogPath ?? ""))
        #expect(FileManager.default.fileExists(atPath: result.items[0].stderrLogPath ?? ""))
    }

    @Test("retries transient simulator busy capture failures")
    func retriesTransientSimulatorBusyCaptureFailures() throws {
        let root = try TemporaryDirectory()
        let rawDirectory = root.url.appendingPathComponent("screenshots/raw/en-US/iOS")
        let stateFile = root.url.appendingPathComponent("retry-state.txt")
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
                    environment: [
                        "ASCENDKIT_SCREENSHOT_OUTPUT_DIR": rawDirectory.path,
                        "STATE_FILE": stateFile.path
                    ],
                    command: [
                        "/bin/sh",
                        "-c",
                        """
                        if [ ! -f "$STATE_FILE" ]; then
                          echo first > "$STATE_FILE"
                          echo 'BSErrorCodeDescription = Busy;' >&2
                          echo 'Application failed preflight checks' >&2
                          exit 65
                        fi
                        mkdir -p "$ASCENDKIT_SCREENSHOT_OUTPUT_DIR"
                        printf retry > "$ASCENDKIT_SCREENSHOT_OUTPUT_DIR/01-home.png"
                        """
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
        #expect(FileManager.default.fileExists(atPath: stateFile.path))
    }

    @Test("imports fresh fastlane screenshots when raw output is empty")
    func importsFreshFastlaneScreenshotsWhenRawOutputIsEmpty() throws {
        let root = try TemporaryDirectory()
        let rawDirectory = root.url.appendingPathComponent("screenshots/raw/en-US/iOS")
        let fastlaneDirectory = root.url.appendingPathComponent("fastlane/screenshots")
        let fastlaneCacheDirectory = root.url.appendingPathComponent("fastlane/cache")
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
                    environment: [
                        "ASCENDKIT_FASTLANE_CACHE_DIR": fastlaneCacheDirectory.path,
                        "ASCENDKIT_FASTLANE_SCREENSHOTS_DIR": fastlaneDirectory.path
                    ],
                    command: [
                        "/bin/sh",
                        "-c",
                        "mkdir -p \"$ASCENDKIT_FASTLANE_SCREENSHOTS_DIR\" && printf fake > \"$ASCENDKIT_FASTLANE_SCREENSHOTS_DIR/iPhone 17 Pro Max-01_home.png\""
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
        #expect(result.items.first?.outputFiles.map { URL(fileURLWithPath: $0).lastPathComponent } == ["iPhone 17 Pro Max-01_home.png"])
        #expect(FileManager.default.fileExists(atPath: rawDirectory.appendingPathComponent("iPhone 17 Pro Max-01_home.png").path))
        #expect(try String(contentsOf: fastlaneCacheDirectory.appendingPathComponent("language.txt")) == "en-US")
        #expect(try String(contentsOf: fastlaneCacheDirectory.appendingPathComponent("locale.txt")) == "en-US")
    }

    @Test("preserves existing raw screenshots when clean capture is disabled")
    func preservesExistingRawScreenshotsWhenCleanCaptureIsDisabled() throws {
        let root = try TemporaryDirectory()
        let rawDirectory = root.url.appendingPathComponent("screenshots/raw/en-US/iOS")
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: rawDirectory.appendingPathComponent("01-old.png"))
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
                        "printf new > \"$ASCENDKIT_SCREENSHOT_OUTPUT_DIR/02-new.png\""
                    ]
                )
            ]
        )

        let result = try ScreenshotCaptureExecutor().execute(
            plan: plan,
            logsDirectory: root.url.appendingPathComponent("logs"),
            cleanOutputDirectories: false
        )

        #expect(result.succeeded)
        let outputNames = result.items.first?.outputFiles.map { URL(fileURLWithPath: $0).lastPathComponent }.sorted()
        #expect(outputNames == ["01-old.png", "02-new.png"])
    }

    @Test("cleans existing raw screenshots when clean capture is enabled")
    func cleansExistingRawScreenshotsWhenCleanCaptureIsEnabled() throws {
        let root = try TemporaryDirectory()
        let rawDirectory = root.url.appendingPathComponent("screenshots/raw/en-US/iOS")
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: rawDirectory.appendingPathComponent("01-old.png"))
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
                        "printf new > \"$ASCENDKIT_SCREENSHOT_OUTPUT_DIR/02-new.png\""
                    ]
                )
            ]
        )

        let result = try ScreenshotCaptureExecutor().execute(
            plan: plan,
            logsDirectory: root.url.appendingPathComponent("logs"),
            cleanOutputDirectories: true
        )

        #expect(result.succeeded)
        let outputNames = result.items.first?.outputFiles.map { URL(fileURLWithPath: $0).lastPathComponent }
        #expect(outputNames == ["02-new.png"])
        #expect(!FileManager.default.fileExists(atPath: rawDirectory.appendingPathComponent("01-old.png").path))
    }

    @Test("writes full locale into fastlane cache for script locales")
    func writesFullLocaleIntoFastlaneCacheForScriptLocales() throws {
        let root = try TemporaryDirectory()
        let rawDirectory = root.url.appendingPathComponent("screenshots/raw/zh-Hans/iOS")
        let fastlaneDirectory = root.url.appendingPathComponent("fastlane/screenshots")
        let fastlaneCacheDirectory = root.url.appendingPathComponent("fastlane/cache")
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
            locales: ["zh-Hans"],
            commands: [
                ScreenshotCaptureCommand(
                    locale: "zh-Hans",
                    platform: .iOS,
                    destinationName: "Test Device",
                    resultBundlePath: root.url.appendingPathComponent("capture/result.xcresult").path,
                    rawOutputDirectory: rawDirectory.path,
                    environment: [
                        "ASCENDKIT_FASTLANE_CACHE_DIR": fastlaneCacheDirectory.path,
                        "ASCENDKIT_FASTLANE_SCREENSHOTS_DIR": fastlaneDirectory.path
                    ],
                    command: [
                        "/bin/sh",
                        "-c",
                        "mkdir -p \"$ASCENDKIT_FASTLANE_SCREENSHOTS_DIR\" && printf fake > \"$ASCENDKIT_FASTLANE_SCREENSHOTS_DIR/iPhone 17 Pro Max-01_home.png\""
                    ]
                )
            ]
        )

        let result = try ScreenshotCaptureExecutor().execute(
            plan: plan,
            logsDirectory: root.url.appendingPathComponent("logs")
        )

        #expect(result.succeeded)
        #expect(try String(contentsOf: fastlaneCacheDirectory.appendingPathComponent("language.txt")) == "zh-Hans")
        #expect(try String(contentsOf: fastlaneCacheDirectory.appendingPathComponent("locale.txt")) == "zh-Hans")
    }

    @Test("imports ordered xcresult screenshot attachments")
    func importsOrderedXcresultScreenshotAttachments() throws {
        let root = try TemporaryDirectory()
        let attachmentsDirectory = root.url.appendingPathComponent("attachments")
        let rawDirectory = root.url.appendingPathComponent("raw")
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: attachmentsDirectory.appendingPathComponent("A.png"))
        try Data("ignored".utf8).write(to: attachmentsDirectory.appendingPathComponent("B.png"))
        try Data("second".utf8).write(to: attachmentsDirectory.appendingPathComponent("C.png"))
        let manifest = """
        [
          {
            "attachments": [
              {
                "exportedFileName": "B.png",
                "suggestedHumanReadableName": "Launch Screen.png",
                "timestamp": 1
              },
              {
                "exportedFileName": "C.png",
                "suggestedHumanReadableName": "02_history_ABC.png",
                "timestamp": 3
              },
              {
                "exportedFileName": "A.png",
                "suggestedHumanReadableName": "01-today_ABC.png",
                "timestamp": 2
              }
            ]
          }
        ]
        """
        try Data(manifest.utf8).write(to: attachmentsDirectory.appendingPathComponent("manifest.json"))

        let result = try ScreenshotAttachmentImporter().import(
            exportedAttachmentsDirectory: attachmentsDirectory,
            rawOutputDirectory: rawDirectory
        )

        #expect(result.findings.isEmpty)
        #expect(result.importedFiles.map { URL(fileURLWithPath: $0).lastPathComponent } == ["01-today.png", "02-history.png"])
        #expect(try String(contentsOf: rawDirectory.appendingPathComponent("01-today.png")) == "first")
        #expect(try String(contentsOf: rawDirectory.appendingPathComponent("02-history.png")) == "second")
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
        #expect(decoded.ascendKitVersion == AscendKitVersion.current)
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
        #expect(report.ascendKitVersion == AscendKitVersion.current)
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
        #expect(status.ascendKitVersion == AscendKitVersion.current)
        #expect(status.executed == true)
        #expect(status.uploadedCount == 1)
        #expect(status.failedCount == 1)
        #expect(status.readyForReview == false)
        #expect(status.readyForRetry)
        #expect(status.retryPlanItemIDs == ["en-US:iOS:APP_IPHONE_67:2:settings.png"])
        #expect(status.nextActions.contains { $0.contains("rerun screenshots upload") })
        #expect(status.recoveryCommands.contains("screenshots upload --workspace PATH --confirm-remote-mutation --json"))
    }

    @Test("treats already committed screenshot upload failure as complete")
    func treatsAlreadyCommittedScreenshotUploadFailureAsComplete() {
        let plan = ScreenshotUploadPlan(
            sourceKind: .composed,
            items: [
                ScreenshotUploadPlanItem(
                    locale: "en-US",
                    platform: .iPadOS,
                    displayType: "APP_IPAD_PRO_3GEN_129",
                    appStoreVersionLocalizationID: "version-loc-1",
                    sourcePath: "/tmp/home.png",
                    fileName: "home.png",
                    order: 1
                )
            ]
        )
        let result = ScreenshotUploadExecutionResult(
            executed: true,
            uploadedCount: 0,
            findings: ["Screenshot upload completed with 1 failure(s); inspect failedItems before retrying."],
            failedItems: [
                ScreenshotUploadFailure(
                    phase: "upload",
                    planItemID: "en-US:iPadOS:APP_IPAD_PRO_3GEN_129:1:home.png",
                    fileName: "home.png",
                    message: """
                    ASC app-screenshot.commit failed with HTTP 409: {
                      "errors" : [ {
                        "status" : "409",
                        "code" : "STATE_ERROR",
                        "detail" : "Asset in Completed! can't be re-committed!"
                      }, {
                        "status" : "409",
                        "code" : "STATE_ERROR",
                        "detail" : "Asset is already Approved! can't commit Asset!"
                      } ]
                    }
                    """
                )
            ]
        )

        let status = ScreenshotUploadStatusBuilder().build(plan: plan, result: result)

        #expect(status.uploadedCount == 1)
        #expect(status.failedCount == 0)
        #expect(status.deliveryCompleteCount == 1)
        #expect(status.readyForReview)
        #expect(!status.readyForRetry)
        #expect(status.retryPlanItemIDs.isEmpty)
        #expect(status.findings.contains { $0.contains("already complete; treated as uploaded") })
        #expect(!status.findings.contains { $0.contains("completed with 1 failure") })
    }

    @Test("summarizes screenshot asset delivery recovery status")
    func summarizesScreenshotAssetDeliveryRecoveryStatus() {
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
                ),
                ScreenshotUploadPlanItem(
                    locale: "en-US",
                    platform: .iOS,
                    displayType: "APP_IPHONE_67",
                    appStoreVersionLocalizationID: "version-loc-1",
                    sourcePath: "/tmp/paywall.png",
                    fileName: "paywall.png",
                    order: 3
                )
            ]
        )
        let result = ScreenshotUploadExecutionResult(
            executed: true,
            uploadedCount: 3,
            items: [
                ScreenshotUploadExecutionItem(
                    planItemID: "en-US:iOS:APP_IPHONE_67:1:home.png",
                    appScreenshotSetID: "set-1",
                    appScreenshotID: "screenshot-1",
                    fileName: "home.png",
                    checksum: "checksum-1",
                    assetDeliveryState: "COMPLETE"
                ),
                ScreenshotUploadExecutionItem(
                    planItemID: "en-US:iOS:APP_IPHONE_67:2:settings.png",
                    appScreenshotSetID: "set-1",
                    appScreenshotID: "screenshot-2",
                    fileName: "settings.png",
                    checksum: "checksum-2",
                    assetDeliveryState: "FAILED"
                ),
                ScreenshotUploadExecutionItem(
                    planItemID: "en-US:iOS:APP_IPHONE_67:3:paywall.png",
                    appScreenshotSetID: "set-1",
                    appScreenshotID: "screenshot-3",
                    fileName: "paywall.png",
                    checksum: "checksum-3",
                    assetDeliveryState: "PROCESSING"
                )
            ]
        )

        let status = ScreenshotUploadStatusBuilder().build(plan: plan, result: result)

        #expect(status.deliveryCompleteCount == 1)
        #expect(status.deliveryFailedCount == 1)
        #expect(status.deliveryPendingCount == 1)
        #expect(status.deliveryUnknownCount == 0)
        #expect(status.deliveryFailedItemIDs == ["en-US:iOS:APP_IPHONE_67:2:settings.png"])
        #expect(status.deliveryPendingItemIDs == ["en-US:iOS:APP_IPHONE_67:3:paywall.png"])
        #expect(status.requiresRemoteRecovery)
        #expect(status.readyForReview == false)
        #expect(status.readyForRetry == false)
        #expect(status.findings.contains("Screenshot asset delivery failed for 1 uploaded item(s)."))
        #expect(status.findings.contains("Screenshot asset delivery is still pending for 1 uploaded item(s)."))
        #expect(status.nextActions.contains { $0.contains("upload-plan --replace-existing") })
        #expect(status.nextActions.contains { $0.contains("Wait for App Store Connect screenshot processing") })
        #expect(status.recoveryCommands == [
            "asc metadata observe --workspace PATH --json",
            "screenshots upload-status --workspace PATH --json"
        ])
    }

    @Test("marks screenshot upload ready for review after complete delivery")
    func marksScreenshotUploadReadyForReviewAfterCompleteDelivery() {
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
                )
            ]
        )
        let result = ScreenshotUploadExecutionResult(
            executed: true,
            uploadedCount: 1,
            items: [
                ScreenshotUploadExecutionItem(
                    planItemID: "en-US:iOS:APP_IPHONE_67:1:home.png",
                    appScreenshotSetID: "set-1",
                    appScreenshotID: "screenshot-1",
                    fileName: "home.png",
                    checksum: "checksum-1",
                    assetDeliveryState: "COMPLETE"
                )
            ]
        )

        let status = ScreenshotUploadStatusBuilder().build(plan: plan, result: result)

        #expect(status.readyForReview)
        #expect(status.readyForRetry == false)
        #expect(status.requiresRemoteRecovery == false)
        #expect(status.deliveryCompleteCount == 1)
        #expect(status.nextActions.contains { $0.contains("submit readiness") })
        #expect(status.recoveryCommands == [
            "workspace summary --workspace PATH --json",
            "submit readiness --workspace PATH --json"
        ])
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

    @Test("merges user screenshot copy over inferred plan copy")
    func mergesUserScreenshotCopyOverInferredPlanCopy() {
        let inferred = ScreenshotCompositionCopyManifest(items: [
            ScreenshotCompositionCopy(
                locale: "en-US",
                platform: .iOS,
                fileName: "01-today.png",
                title: "Today",
                subtitle: "Show today focus"
            ),
            ScreenshotCompositionCopy(
                locale: "zh-Hans",
                platform: .iOS,
                fileName: "01-today.png",
                title: "Today",
                subtitle: "Show today focus"
            )
        ])
        let userCopy = ScreenshotCompositionCopyManifest(items: [
            ScreenshotCompositionCopy(
                locale: "zh-Hans",
                platform: .iOS,
                fileName: "01-today.png",
                title: "专注今日",
                subtitle: "保持简单"
            )
        ])

        let merged = userCopy.merged(with: inferred)

        #expect(merged.copy(locale: "en-US", platform: .iOS, fileName: "01-today.png")?.title == "Today")
        #expect(merged.copy(locale: "zh-Hans", platform: .iOS, fileName: "01-today.png")?.title == "专注今日")
        #expect(merged.copy(locale: "zh-Hans", platform: .iOS, fileName: "01-today.png")?.subtitle == "保持简单")
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

    @Test("warns about invalid or suspiciously small screenshot images")
    func warnsAboutInvalidOrSmallScreenshotImages() throws {
        let root = try TemporaryDirectory()
        let platformDirectory = root.url
            .appendingPathComponent("en-US")
            .appendingPathComponent("iOS")
        try FileManager.default.createDirectory(at: platformDirectory, withIntermediateDirectories: true)
        try Data("not-an-image".utf8).write(to: platformDirectory.appendingPathComponent("01-home.png"))
        try makePNG(size: NSSize(width: 120, height: 240), url: platformDirectory.appendingPathComponent("02-small.png"))

        let plan = ScreenshotPlan(
            inputPath: .userProvided,
            platforms: [.iOS],
            locales: ["en-US"],
            items: [
                ScreenshotPlanItem(id: "home", screenName: "Home", order: 1, purpose: "Show home"),
                ScreenshotPlanItem(id: "small", screenName: "Small", order: 2, purpose: "Show small")
            ]
        )

        let readiness = ScreenshotReadinessEvaluator().evaluate(plan: plan, sourceDirectory: root.url)

        #expect(readiness.ready)
        #expect(readiness.findings.contains { $0.id == "screenshots.import.en-US.iOS.01-home.decode" && $0.severity == .warning })
        #expect(readiness.findings.contains { $0.id == "screenshots.import.en-US.iOS.02-small.dimensions" && $0.severity == .warning })
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
        try makePNG(size: NSSize(width: 390, height: 844), url: input)
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

    @Test("store-ready copy flattens transparent screenshots")
    func storeReadyCopyFlattensTransparentScreenshots() throws {
        let root = try TemporaryDirectory()
        let input = root.url.appendingPathComponent("source/en-US/iOS/01-home.png")
        try FileManager.default.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeTransparentRoundedPNG(size: NSSize(width: 390, height: 844), url: input)
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: root.url.appendingPathComponent("source").path,
            artifacts: [
                ScreenshotArtifact(locale: "en-US", platform: .iOS, path: input.path, fileName: "01-home.png")
            ]
        )

        let manifest = try ScreenshotComposer().compose(
            importManifest: importManifest,
            outputRoot: root.url.appendingPathComponent("composed"),
            mode: .storeReadyCopy
        )

        #expect(manifest.artifacts[0].outputPath.hasSuffix("01-home.png"))
        try expectPNGHasNoAlpha(at: URL(fileURLWithPath: manifest.artifacts[0].outputPath))
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

    @Test("builds upload plan display types per platform")
    func buildsUploadPlanDisplayTypesPerPlatform() throws {
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: "/tmp/screenshots",
            artifacts: [
                ScreenshotArtifact(
                    locale: "en-US",
                    platform: .iOS,
                    path: "/tmp/screenshots/en-US/iOS/01-home.png",
                    fileName: "iphone-home.png"
                ),
                ScreenshotArtifact(
                    locale: "en-US",
                    platform: .iPadOS,
                    path: "/tmp/screenshots/en-US/iPadOS/01-home.png",
                    fileName: "ipad-home.png"
                )
            ]
        )
        let observed = MetadataObservedState(
            metadataByLocale: ["en-US": AppMetadata(locale: "en-US", name: "Demo", description: "Demo description")],
            resourceIDsByLocale: [
                "en-US": MetadataLocalizationResourceIDs(appStoreVersionLocalizationID: "version-loc-1")
            ]
        )

        let plan = ScreenshotUploadPlanBuilder().build(
            importManifest: importManifest,
            compositionManifest: nil,
            observedState: observed
        )

        #expect(plan.findings.isEmpty)
        #expect(plan.items.first { $0.platform == .iOS }?.displayType == "APP_IPHONE_67")
        #expect(plan.items.first { $0.platform == .iPadOS }?.displayType == "APP_IPAD_PRO_3GEN_129")
    }

    @Test("filters upload plan artifacts by display type override")
    func filtersUploadPlanArtifactsByDisplayTypeOverride() throws {
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: "/tmp/screenshots",
            artifacts: [
                ScreenshotArtifact(
                    locale: "en-US",
                    platform: .iOS,
                    path: "/tmp/screenshots/en-US/iOS/01-home.png",
                    fileName: "iphone-home.png"
                ),
                ScreenshotArtifact(
                    locale: "en-US",
                    platform: .iPadOS,
                    path: "/tmp/screenshots/en-US/iPadOS/01-home.png",
                    fileName: "ipad-home.png"
                )
            ]
        )
        let observed = MetadataObservedState(
            metadataByLocale: ["en-US": AppMetadata(locale: "en-US", name: "Demo", description: "Demo description")],
            resourceIDsByLocale: [
                "en-US": MetadataLocalizationResourceIDs(appStoreVersionLocalizationID: "version-loc-1")
            ]
        )

        let plan = ScreenshotUploadPlanBuilder().build(
            importManifest: importManifest,
            compositionManifest: nil,
            observedState: observed,
            displayTypeOverride: "APP_IPHONE_67"
        )

        #expect(plan.findings.isEmpty)
        #expect(plan.items.count == 1)
        #expect(plan.items[0].platform == .iOS)
        #expect(plan.items[0].displayType == "APP_IPHONE_67")
        #expect(plan.items[0].fileName == "iphone-home.png")
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

    @Test("plans targeted screenshot replacement by item and matching remote file")
    func plansTargetedScreenshotReplacementByItemAndMatchingRemoteFile() throws {
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: "/tmp/screenshots",
            artifacts: [
                ScreenshotArtifact(
                    locale: "en-US",
                    platform: .iPadOS,
                    path: "/tmp/screenshots/en-US/iPadOS/01-home.png",
                    fileName: "01-home.png"
                ),
                ScreenshotArtifact(
                    locale: "en-US",
                    platform: .iPadOS,
                    path: "/tmp/screenshots/en-US/iPadOS/02-beats.png",
                    fileName: "02-beats.png"
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
                        displayType: "APP_IPAD_PRO_3GEN_129",
                        screenshots: [
                            ObservedScreenshot(id: "screenshot-1", fileName: "01-home.png", assetDeliveryState: "COMPLETE"),
                            ObservedScreenshot(id: "screenshot-2", fileName: "02-beats.png", assetDeliveryState: "COMPLETE")
                        ]
                    )
                ]
            ]
        )

        let plan = ScreenshotUploadPlanBuilder().build(
            importManifest: importManifest,
            compositionManifest: nil,
            observedState: observed,
            displayTypeOverride: "APP_IPAD_PRO_3GEN_129",
            replaceExistingRemoteScreenshots: true,
            onlyPlanItemIDs: ["en-US:iPadOS:APP_IPAD_PRO_3GEN_129:2:02-beats.png"],
            deleteOnlyMatchingRemoteFiles: true
        )

        #expect(plan.findings.isEmpty)
        #expect(plan.items.map(\.fileName) == ["02-beats.png"])
        #expect(plan.remoteScreenshotsToDelete?.map(\.fileName) == ["02-beats.png"])
        #expect(plan.remoteScreenshotsToDelete?.map(\.appScreenshotID) == ["screenshot-2"])
    }

    @Test("delete-matching-files-only without --only-item clears upload items")
    func deleteMatchingFilesOnlyClearsUploadItemsWhenNoOnlyItem() throws {
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: "/tmp/screenshots",
            artifacts: [
                ScreenshotArtifact(
                    locale: "en-US",
                    platform: .iPadOS,
                    path: "/tmp/screenshots/en-US/iPadOS/01-home.png",
                    fileName: "01-home.png"
                ),
                ScreenshotArtifact(
                    locale: "en-US",
                    platform: .iPadOS,
                    path: "/tmp/screenshots/en-US/iPadOS/02-beats.png",
                    fileName: "02-beats.png"
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
                        displayType: "APP_IPAD_PRO_3GEN_129",
                        screenshots: [
                            ObservedScreenshot(id: "screenshot-1", fileName: "01-home.png", assetDeliveryState: "COMPLETE"),
                            ObservedScreenshot(id: "screenshot-2", fileName: "02-beats.png", assetDeliveryState: "COMPLETE")
                        ]
                    )
                ]
            ]
        )

        let plan = ScreenshotUploadPlanBuilder().build(
            importManifest: importManifest,
            compositionManifest: nil,
            observedState: observed,
            displayTypeOverride: "APP_IPAD_PRO_3GEN_129",
            replaceExistingRemoteScreenshots: true,
            onlyPlanItemIDs: [],
            deleteOnlyMatchingRemoteFiles: true
        )

        #expect(plan.items.isEmpty)
        #expect(plan.remoteScreenshotsToDelete?.isEmpty == false)
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
        try expectPNGHasNoAlpha(at: URL(fileURLWithPath: manifest.artifacts[0].outputPath))
    }

    @Test("device frame request renders framed App Store marketing poster")
    func deviceFrameRequestRendersFramedMarketingPoster() throws {
        let root = try TemporaryDirectory()
        let input = root.url.appendingPathComponent("source/en-US/iOS/01-home.png")
        try FileManager.default.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeScaledPNG(pixelSize: NSSize(width: 1_320, height: 2_868), pointSize: NSSize(width: 1_320, height: 2_868), url: input)
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
        #expect(manifest.mode == .framedPoster)
        #expect(manifest.artifacts[0].mode == .framedPoster)
        #expect(manifest.artifacts[0].outputPath.hasSuffix("01-home-framed-poster.png"))
        #expect(NSImage(contentsOfFile: manifest.artifacts[0].outputPath)?.isValid == true)
        try expectPNGHasNoAlpha(at: URL(fileURLWithPath: manifest.artifacts[0].outputPath))
    }

    @Test("renders framed poster composition at original screenshot size")
    func rendersFramedPosterCompositionAtOriginalSize() throws {
        let root = try TemporaryDirectory()
        let input = root.url.appendingPathComponent("source/en-US/iOS/01-home.png")
        try FileManager.default.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeScaledPNG(pixelSize: NSSize(width: 1_320, height: 2_868), pointSize: NSSize(width: 1_320, height: 2_868), url: input)
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
        try expectPNGHasNoAlpha(at: URL(fileURLWithPath: manifest.artifacts[0].outputPath))
    }

    @Test("renders long framed poster title on one line")
    func rendersLongFramedPosterTitleOnOneLine() throws {
        let root = try TemporaryDirectory()
        let input = root.url.appendingPathComponent("source/th/iPadOS/01-home.png")
        try FileManager.default.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeScaledPNG(pixelSize: NSSize(width: 2_064, height: 2_752), pointSize: NSSize(width: 2_064, height: 2_752), url: input)
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: root.url.appendingPathComponent("source").path,
            artifacts: [
                ScreenshotArtifact(locale: "th", platform: .iPadOS, path: input.path, fileName: "01-home.png")
            ]
        )
        let copyManifest = ScreenshotCompositionCopyManifest(items: [
            ScreenshotCompositionCopy(
                locale: "th",
                platform: .iPadOS,
                fileName: "01-home.png",
                title: "เสียงเครื่องดนตรีสมจริงมากสำหรับการฝึกซ้อม",
                subtitle: "Keep the subtitle below"
            )
        ])

        let manifest = try ScreenshotComposer().compose(
            importManifest: importManifest,
            outputRoot: root.url.appendingPathComponent("composed"),
            mode: .framedPoster,
            copyManifest: copyManifest
        )

        #expect(manifest.artifacts.count == 1)
        #expect(NSImage(contentsOfFile: manifest.artifacts[0].outputPath)?.isValid == true)
        try expectPNGHasNoAlpha(at: URL(fileURLWithPath: manifest.artifacts[0].outputPath))
    }

    @Test("matches inferred screenshot copy against device-prefixed filenames")
    func matchesScreenshotCopyAgainstDevicePrefixedFilenames() {
        let manifest = ScreenshotCompositionCopyManifest(items: [
            ScreenshotCompositionCopy(
                locale: "en-US",
                platform: .iOS,
                fileName: "01-home.png",
                title: "Home",
                subtitle: "Stay on beat"
            )
        ])

        let copy = manifest.copy(
            locale: "en-US",
            platform: .iOS,
            fileName: "iPhone 17 Pro Max-iPhone 17 Pro Max-01_home-framed-poster.png"
        )

        #expect(copy?.title == "Home")
        #expect(copy?.subtitle == "Stay on beat")
    }

    @Test("imports screenshot semantics from device-prefixed filenames when plan is present")
    func importsScreenshotSemanticsFromDevicePrefixedFilenames() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source/en-US/iOS")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let imageURL = source.appendingPathComponent("iPhone 17 Pro Max-iPhone 17 Pro Max-01_home.png")
        try makePNG(size: NSSize(width: 390, height: 844), url: imageURL)

        let plan = ScreenshotPlan(
            inputPath: .uiTestCapture,
            platforms: [.iOS],
            locales: ["en-US"],
            items: [
                ScreenshotPlanItem(
                    id: "home",
                    screenName: "Home",
                    order: 1,
                    purpose: "Show the app's first meaningful screen."
                )
            ]
        )

        let manifest = ScreenshotImporter().makeManifest(plan: plan, sourceDirectory: root.url.appendingPathComponent("source"))
        let artifact = try #require(manifest.artifacts.first)
        #expect(artifact.planItemID == "home")
        #expect(artifact.screenName == "Home")
        #expect(artifact.purpose == "Show the app's first meaningful screen.")
    }

    @Test("renders framed poster composition at bitmap pixel size for scaled PNGs")
    func rendersFramedPosterCompositionAtBitmapPixelSizeForScaledPNGs() throws {
        let root = try TemporaryDirectory()
        let input = root.url.appendingPathComponent("source/en-US/iOS/01-home.png")
        try FileManager.default.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeScaledPNG(pixelSize: NSSize(width: 1_320, height: 2_868), pointSize: NSSize(width: 440, height: 956), url: input)

        let importManifest = ScreenshotImportManifest(
            sourceDirectory: root.url.appendingPathComponent("source").path,
            artifacts: [
                ScreenshotArtifact(locale: "en-US", platform: .iOS, path: input.path, fileName: "iPhone 17 Pro Max-iPhone 17 Pro Max-01_home.png")
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
        let bitmap = try #require(output.representations.compactMap { $0 as? NSBitmapImageRep }.first)
        #expect(manifest.artifacts[0].title == "Choose Three")
        #expect(manifest.artifacts[0].subtitle == "Keep today simple")
        #expect(bitmap.pixelsWide == 1_320)
        #expect(bitmap.pixelsHigh == 2_868)
        try expectPNGHasNoAlpha(at: URL(fileURLWithPath: manifest.artifacts[0].outputPath))
    }

    @Test("uses imported screenshot semantics when marketing copy is absent")
    func usesImportedScreenshotSemanticsWhenMarketingCopyIsAbsent() throws {
        let root = try TemporaryDirectory()
        let input = root.url.appendingPathComponent("source/en-US/iOS/iPhone 17 Pro Max-iPhone 17 Pro Max-01_home.png")
        try FileManager.default.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeScaledPNG(pixelSize: NSSize(width: 1_320, height: 2_868), pointSize: NSSize(width: 1_320, height: 2_868), url: input)

        let importManifest = ScreenshotImportManifest(
            sourceDirectory: root.url.appendingPathComponent("source").path,
            artifacts: [
                ScreenshotArtifact(
                    locale: "en-US",
                    platform: .iOS,
                    path: input.path,
                    fileName: input.lastPathComponent,
                    planItemID: "home",
                    screenName: "Home",
                    purpose: "Show the app's first meaningful screen."
                )
            ]
        )

        let manifest = try ScreenshotComposer().compose(
            importManifest: importManifest,
            outputRoot: root.url.appendingPathComponent("composed"),
            mode: .framedPoster
        )

        #expect(manifest.artifacts[0].planItemID == "home")
        #expect(manifest.artifacts[0].screenName == "Home")
        #expect(manifest.artifacts[0].title == "Home")
        #expect(manifest.artifacts[0].subtitle == "Show the app's first meaningful screen.")
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

    private func makeTransparentRoundedPNG(size: NSSize, url: URL) throws {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(calibratedRed: 0.20, green: 0.34, blue: 0.52, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 64, yRadius: 64).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AscendKitError.invalidState("Failed to create transparent test PNG")
        }
        try png.write(to: url)
    }

    private func makeScaledPNG(pixelSize: NSSize, pointSize: NSSize, url: URL) throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = pointSize
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedRed: 0.20, green: 0.34, blue: 0.52, alpha: 1).setFill()
        NSRect(origin: .zero, size: pointSize).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AscendKitError.invalidState("Failed to create scaled test PNG")
        }
        try png.write(to: url)
    }

    private func expectPNGHasNoAlpha(at url: URL) throws {
        let data = try Data(contentsOf: url)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        #expect(bitmap.hasAlpha == false)
        #expect(bitmap.samplesPerPixel == 3)
    }

    private func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }
        return arguments[arguments.index(after: index)]
    }

    // MARK: - Theme Tests

    @Test("all named themes produce valid framed poster PNG output")
    func allThemesProduceValidFramedPosterOutput() throws {
        let root = try TemporaryDirectory()
        let input = root.url.appendingPathComponent("source/en-US/iOS/01-home.png")
        try FileManager.default.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeScaledPNG(
            pixelSize: NSSize(width: 1_320, height: 2_868),
            pointSize: NSSize(width: 1_320, height: 2_868),
            url: input
        )
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
                title: "Theme Test",
                subtitle: "Verifying all presets"
            )
        ])

        for theme in ScreenshotTheme.allCases {
            let outputRoot = root.url.appendingPathComponent("composed-\(theme.name)")
            let manifest = try ScreenshotComposer().compose(
                importManifest: importManifest,
                outputRoot: outputRoot,
                mode: .framedPoster,
                copyManifest: copyManifest,
                theme: theme
            )
            #expect(manifest.artifacts.count == 1)
            #expect(NSImage(contentsOfFile: manifest.artifacts[0].outputPath)?.isValid == true)
            try expectPNGHasNoAlpha(at: URL(fileURLWithPath: manifest.artifacts[0].outputPath))
        }
    }

    @Test("all named themes produce valid poster PNG output")
    func allThemesProduceValidPosterOutput() throws {
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

        for theme in ScreenshotTheme.allCases {
            let outputRoot = root.url.appendingPathComponent("poster-\(theme.name)")
            let manifest = try ScreenshotComposer().compose(
                importManifest: importManifest,
                outputRoot: outputRoot,
                mode: .poster,
                theme: theme
            )
            #expect(manifest.artifacts.count == 1)
            #expect(manifest.artifacts[0].outputPath.hasSuffix("01-home-poster.png"))
            #expect(NSImage(contentsOfFile: manifest.artifacts[0].outputPath)?.isValid == true)
            try expectPNGHasNoAlpha(at: URL(fileURLWithPath: manifest.artifacts[0].outputPath))
        }
    }

    @Test("auto theme selection produces valid output")
    func autoThemeProducesValidOutput() throws {
        let root = try TemporaryDirectory()
        let input = root.url.appendingPathComponent("source/en-US/iOS/01-home.png")
        try FileManager.default.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeScaledPNG(
            pixelSize: NSSize(width: 1_320, height: 2_868),
            pointSize: NSSize(width: 1_320, height: 2_868),
            url: input
        )
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
                title: "Auto Theme",
                subtitle: "Randomly selected"
            )
        ])

        let manifest = try ScreenshotComposer().compose(
            importManifest: importManifest,
            outputRoot: root.url.appendingPathComponent("composed-auto"),
            mode: .framedPoster,
            copyManifest: copyManifest,
            theme: .auto
        )
        #expect(manifest.artifacts.count == 1)
        #expect(NSImage(contentsOfFile: manifest.artifacts[0].outputPath)?.isValid == true)
        try expectPNGHasNoAlpha(at: URL(fileURLWithPath: manifest.artifacts[0].outputPath))
    }
}
