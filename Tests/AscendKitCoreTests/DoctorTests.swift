import Foundation
import Testing
@testable import AscendKitCore

@Suite("Release doctor")
struct DoctorTests {
    @Test("reports blockers for empty manifest")
    func reportsEmptyManifest() {
        let manifest = ReleaseManifest(
            releaseID: "empty",
            appSlug: "empty",
            projects: [],
            targets: []
        )

        let report = ReleaseDoctor().run(manifest: manifest)

        #expect(report.hasBlockers)
        #expect(report.findings.contains { $0.id == "intake.no-project" })
    }

    @Test("inspects Info.plist release sensitive keys")
    func inspectsInfoPlist() throws {
        let root = try TemporaryDirectory()
        let project = root.url.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let plistURL = root.url.appendingPathComponent("Demo/Info.plist")
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "NSCameraUsageDescription": "TODO"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)

        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [ProjectReference(kind: .xcodeproj, path: project.path)],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "1"),
                    infoPlistPath: "Demo/Info.plist"
                )
            ]
        )

        let report = ReleaseDoctor().run(manifest: manifest)

        #expect(report.findings.contains { $0.id == "plist.Demo.encryption-key-missing" })
        #expect(report.findings.contains { $0.id == "plist.Demo.NSCameraUsageDescription.placeholder" })
    }

    @Test("detects missing privacy purpose strings from conservative source signals")
    func detectsMissingPrivacyPurposeStrings() throws {
        let root = try TemporaryDirectory()
        let project = root.url.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let plistURL = root.url.appendingPathComponent("Demo/Info.plist")
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleDisplayName": "Demo",
            "ITSAppUsesNonExemptEncryption": false
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
        let sourceURL = root.url.appendingPathComponent("Demo/CameraFeature.swift")
        try Data("let camera = AVCaptureSession()".utf8).write(to: sourceURL)

        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [ProjectReference(kind: .xcodeproj, path: project.path)],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "1"),
                    infoPlistPath: "Demo/Info.plist",
                    productType: "com.apple.product-type.application"
                )
            ]
        )

        let report = ReleaseDoctor().run(manifest: manifest)

        #expect(report.findings.contains { $0.id == "plist.Demo.camera.usage-description-missing" && $0.category == .privacy })
    }

    @Test("reports missing app icon asset set")
    func reportsMissingAppIcon() throws {
        let root = try TemporaryDirectory()
        let project = root.url.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [ProjectReference(kind: .xcodeproj, path: project.path)],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "1"),
                    appIconName: "AppIcon",
                    productType: "com.apple.product-type.application"
                )
            ]
        )

        let report = ReleaseDoctor().run(manifest: manifest)

        #expect(report.findings.contains { $0.id == "assets.Demo.app-icon-missing" && $0.severity == .blocker })
    }

    @Test("does not require screenshot source after import manifest exists")
    func acceptsImportedScreenshotsForDoctor() {
        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [ProjectReference(kind: .xcodeproj, path: "/tmp/Demo.xcodeproj")],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "1"),
                    productType: "com.apple.product-type.application"
                )
            ]
        )
        let plan = ScreenshotPlan(
            inputPath: .userProvided,
            platforms: [.iOS],
            locales: ["en-US"],
            items: [ScreenshotPlanItem(id: "home", screenName: "Home", order: 1, purpose: "Show home")]
        )
        let importManifest = ScreenshotImportManifest(
            sourceDirectory: "/tmp/screenshots",
            artifacts: [
                ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/screenshots/en-US/iOS/home.png", fileName: "home.png")
            ]
        )

        let report = ReleaseDoctor().run(
            manifest: manifest,
            screenshotPlan: plan,
            screenshotImportManifest: importManifest
        )

        #expect(report.findings.contains { $0.id == "screenshots.readiness.screenshots.import.source-missing" } == false)
    }

    @Test("accepts Xcode icon bundle app icon")
    func acceptsXcodeIconBundle() throws {
        let root = try TemporaryDirectory()
        let project = root.url.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let icon = root.url.appendingPathComponent("Demo/AppIcon.icon")
        try FileManager.default.createDirectory(at: icon, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: icon.appendingPathComponent("icon.json"))
        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [ProjectReference(kind: .xcodeproj, path: project.path)],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "1"),
                    appIconName: "AppIcon",
                    productType: "com.apple.product-type.application"
                )
            ]
        )

        let report = ReleaseDoctor().run(manifest: manifest)

        #expect(report.findings.contains { $0.id == "assets.Demo.app-icon-missing" } == false)
        #expect(report.findings.contains { $0.id == "assets.Demo.app-icon-contents-missing" } == false)
    }

    @Test("inspects release-sensitive entitlements")
    func inspectsEntitlements() throws {
        let root = try TemporaryDirectory()
        let project = root.url.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let entitlementsURL = root.url.appendingPathComponent("Demo/Demo.entitlements")
        try FileManager.default.createDirectory(at: entitlementsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let entitlements: [String: Any] = [
            "aps-environment": "development",
            "com.apple.developer.associated-domains": ["applinks:example.com"],
            "com.apple.security.application-groups": []
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
        try data.write(to: entitlementsURL)

        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [ProjectReference(kind: .xcodeproj, path: project.path)],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "1"),
                    entitlementsPath: "Demo/Demo.entitlements",
                    productType: "com.apple.product-type.application"
                )
            ]
        )

        let report = ReleaseDoctor().run(manifest: manifest)

        #expect(report.findings.contains { $0.id == "entitlements.Demo.push-enabled" && $0.severity == .warning })
        #expect(report.findings.contains { $0.id == "entitlements.Demo.associated-domains.enabled" && $0.category == .capabilities })
        #expect(report.findings.contains { $0.id == "entitlements.Demo.application-groups.empty" && $0.severity == .error })
    }

    @Test("reports missing configured entitlements file")
    func reportsMissingEntitlementsFile() throws {
        let root = try TemporaryDirectory()
        let project = root.url.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [ProjectReference(kind: .xcodeproj, path: project.path)],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    entitlementsPath: "Demo/Missing.entitlements",
                    productType: "com.apple.product-type.application"
                )
            ]
        )

        let report = ReleaseDoctor().run(manifest: manifest)

        #expect(report.findings.contains { $0.id == "entitlements.Demo.not-found" && $0.category == .capabilities })
    }

    @Test("detects local release hygiene residue")
    func detectsReleaseHygieneResidue() throws {
        let root = try TemporaryDirectory()
        let project = root.url.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let source = root.url.appendingPathComponent("Demo/ReleaseConfig.swift")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"let apiBaseURL = "https://staging.example.com""#.utf8).write(to: source)

        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [ProjectReference(kind: .xcodeproj, path: project.path)],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    productType: "com.apple.product-type.application"
                )
            ]
        )

        let report = ReleaseDoctor().run(manifest: manifest)

        #expect(report.findings.contains { $0.id.hasSuffix("staging-residue") })
    }

    @Test("includes invalid local IAP templates")
    func includesInvalidIAPTemplates() {
        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [],
            targets: []
        )
        let iap = IAPValidationReport(templates: [
            SubscriptionTemplate(id: "a", referenceName: "A", productID: "duplicate", cadence: .monthly, displayName: "A"),
            SubscriptionTemplate(id: "b", referenceName: "B", productID: "duplicate", cadence: .yearly, displayName: "B")
        ])

        let report = ReleaseDoctor().run(manifest: manifest, iapValidationReport: iap)

        #expect(report.findings.contains { $0.id == "iap.validation.failed" && $0.category == .iap })
    }
}
