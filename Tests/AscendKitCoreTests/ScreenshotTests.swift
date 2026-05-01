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
            destinationOverrides: ["platform=iOS Simulator,name=iPhone 16 Pro Max"]
        )

        #expect(capturePlan.scheme == "Demo")
        #expect(capturePlan.workspacePath == "/tmp/Demo/Demo.xcworkspace")
        #expect(capturePlan.commands.count == 2)
        #expect(capturePlan.commands[0].command.contains("-workspace"))
        #expect(capturePlan.commands[0].command.contains("-testLanguage"))
        #expect(capturePlan.commands[0].environment["ASCENDKIT_SCREENSHOT_OUTPUT_DIR"]?.hasSuffix("screenshots/raw/en-US/iOS") == true)
        #expect(capturePlan.findings.isEmpty)
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
