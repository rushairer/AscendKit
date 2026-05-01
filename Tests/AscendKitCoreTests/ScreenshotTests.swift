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
