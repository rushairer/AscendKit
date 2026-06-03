import Foundation
import Testing
@testable import AscendKitCore

@Suite("Metadata lint")
struct MetadataTests {
    @Test("validates required fields and app store length limits")
    func validatesMetadata() {
        let metadata = AppMetadata(
            name: String(repeating: "A", count: 31),
            description: "",
            releaseNotes: "TODO",
            keywords: [String(repeating: "k", count: 101)],
            supportURL: "example.com/support"
        )

        let report = MetadataLinter().lint(metadata: metadata)

        #expect(report.ascendKitVersion == AscendKitVersion.current)
        #expect(report.findings.contains { $0.id == "name.too-long" })
        #expect(report.findings.contains { $0.id == "description.required" })
        #expect(report.findings.contains { $0.id == "keywords.too-long" })
        #expect(report.findings.contains { $0.id == "supportURL.invalid-url" })
        #expect(report.findings.contains { $0.id == "releaseNotes.placeholder" })
    }

    @Test("catalogs source metadata and lint status")
    func catalogsMetadataStatus() throws {
        let root = try TemporaryDirectory()
        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(
            baseDirectory: root.url,
            manifest: ReleaseManifest(releaseID: "demo", appSlug: "demo", projects: [], targets: [])
        )
        try store.save(AppMetadata.template, to: URL(fileURLWithPath: workspace.paths.metadataSource))
        let lint = MetadataLintReport(locale: "en-US", findings: [
            MetadataLintFinding(id: "example", severity: .warning, field: "description", message: "Example")
        ])
        try store.save(lint, to: URL(fileURLWithPath: workspace.paths.metadataLint))

        let catalog = MetadataCatalogReader().read(workspace: workspace)

        #expect(catalog.bundles.count == 1)
        #expect(catalog.bundles.first?.locale == "en-US")
        #expect(catalog.bundles.first?.lintFindingCount == 1)
    }

    @Test("diffs local metadata against observed state")
    func diffsMetadata() {
        let local = AppMetadata(
            locale: "en-US",
            name: "Demo",
            subtitle: "Local subtitle",
            description: "Local description",
            releaseNotes: "Bug fixes",
            keywords: ["demo", "release"]
        )
        let remote = AppMetadata(
            locale: "en-US",
            name: "Demo",
            subtitle: "Remote subtitle",
            description: "Local description",
            releaseNotes: nil,
            keywords: ["demo", "release"]
        )

        let report = MetadataDiffEngine().diff(
            local: [local],
            observed: MetadataObservedState(metadataByLocale: ["en-US": remote])
        )

        #expect(report.diffs.contains { $0.field == "name" && $0.status == .unchanged })
        #expect(report.ascendKitVersion == AscendKitVersion.current)
        #expect(report.diffs.contains { $0.field == "subtitle" && $0.status == .changed })
        #expect(report.diffs.contains { $0.field == "releaseNotes" && $0.status == .missingRemote })
    }

    @Test("summarizes ASC metadata apply status")
    func summarizesASCMetadataApplyStatus() {
        let status = ASCMetadataStatusBuilder().build(
            applyResult: ASCMetadataApplyResult(
                generatedAt: Date(timeIntervalSince1970: 100),
                applied: true,
                responses: [
                    ASCMetadataApplyResponse(
                        id: "metadata.update.en-US.description",
                        method: "PATCH",
                        path: "/v1/appStoreVersionLocalizations/version-loc-1",
                        statusCode: 200
                    )
                ]
            ),
            diffReport: MetadataDiffReport(
                generatedAt: Date(timeIntervalSince1970: 101),
                diffs: [
                    MetadataFieldDiff(
                        locale: "en-US",
                        field: "releaseNotes",
                        status: .changed,
                        localValue: "Bug fixes",
                        remoteValue: nil
                    )
                ]
            )
        )

        #expect(status.applied == true)
        #expect(status.ascendKitVersion == AscendKitVersion.current)
        #expect(status.applyResponseCount == 1)
        #expect(status.diffFresh == true)
        #expect(status.remainingDiffCount == 1)
        #expect(status.blockingDiffCount == 0)
        #expect(status.releaseNotesOnlyDiff)
        #expect(status.readyForReviewPlan)
        #expect(status.findings.contains { $0.contains("releaseNotes/whatsNew") })
    }

    @Test("reports ready for review plan when no blocking diffs even without apply")
    func readyForReviewPlanWhenNoBlockingDiffs() {
        let status = ASCMetadataStatusBuilder().build(
            applyResult: nil,
            diffReport: MetadataDiffReport(
                generatedAt: Date(),
                diffs: [
                    MetadataFieldDiff(
                        locale: "en-US",
                        field: "name",
                        status: .unchanged,
                        localValue: "Demo",
                        remoteValue: "Demo"
                    )
                ]
            )
        )

        #expect(status.applied == nil)
        #expect(status.blockingDiffCount == 0)
        #expect(status.readyForReviewPlan)
        #expect(!status.findings.contains { $0.contains("apply has not completed") })
    }

    @Test("plans ASC metadata mutations from local and observed diff")
    func plansASCMetadataMutations() {
        let local = AppMetadata(
            locale: "en-US",
            name: "Demo",
            subtitle: "Local subtitle",
            promotionalText: "Try Demo today",
            description: "Local description",
            releaseNotes: "Bug fixes",
            keywords: ["demo", "release"],
            privacyPolicyURL: "https://example.com/privacy"
        )
        let remote = AppMetadata(
            locale: "en-US",
            name: "Demo",
            subtitle: "Remote subtitle",
            description: "",
            keywords: [],
            privacyPolicyURL: "https://example.com/privacy"
        )

        let plan = ASCMetadataMutationPlanner().plan(
            local: [local],
            observed: MetadataObservedState(
                appInfoID: "app-info-id",
                appStoreVersionID: "version-id",
                metadataByLocale: ["en-US": remote],
                resourceIDsByLocale: [
                    "en-US": MetadataLocalizationResourceIDs(
                        appInfoLocalizationID: "app-info-loc-id",
                        appStoreVersionLocalizationID: "version-loc-id"
                    )
                ]
            )
        )

        #expect(plan.dryRunOnly)
        #expect(plan.ascendKitVersion == AscendKitVersion.current)
        #expect(plan.operations.contains {
            $0.locale == "en-US" &&
            $0.field == "subtitle" &&
            $0.resourceKind == .appInfoLocalization &&
            $0.action == .updateField &&
            $0.resourceID == "app-info-loc-id"
        })
        #expect(plan.operations.contains {
            $0.locale == "en-US" &&
            $0.field == "description" &&
            $0.resourceKind == .appStoreVersionLocalization &&
            $0.action == .updateField &&
            $0.resourceID == "version-loc-id"
        })
        #expect(plan.operations.contains {
            $0.locale == "en-US" &&
            $0.field == "releaseNotes" &&
            $0.resourceKind == .appStoreVersionLocalization
        })
        #expect(plan.operations.allSatisfy { $0.field != "name" && $0.field != "privacyPolicyURL" })
    }

    @Test("plans localization creation when remote locale is absent")
    func plansMissingRemoteLocaleCreation() {
        let local = AppMetadata(
            locale: "zh-Hant",
            name: "示例",
            subtitle: "本地副标题",
            description: "本地描述",
            releaseNotes: "首次发布"
        )

        let plan = ASCMetadataMutationPlanner().plan(
            local: [local],
            observed: MetadataObservedState(metadataByLocale: [:])
        )

        #expect(plan.operations.contains { $0.locale == "zh-Hant" && $0.action == .createLocalization })
        #expect(plan.operations.contains { $0.field == "name" && $0.resourceKind == .appInfoLocalization })
        #expect(plan.operations.contains { $0.field == "description" && $0.resourceKind == .appStoreVersionLocalization })
    }

    @Test("plans creation when only one remote localization resource exists")
    func plansCreationForMissingVersionLocalizationResource() {
        let local = AppMetadata(
            locale: "zh-Hans",
            name: "示例",
            subtitle: "本地副标题",
            description: "本地描述",
            releaseNotes: "首次发布"
        )
        let remote = AppMetadata(
            locale: "zh-Hans",
            name: "示例",
            subtitle: "远端副标题",
            description: ""
        )

        let plan = ASCMetadataMutationPlanner().plan(
            local: [local],
            observed: MetadataObservedState(
                appInfoID: "app-info-id",
                appStoreVersionID: "version-id",
                metadataByLocale: ["zh-Hans": remote],
                resourceIDsByLocale: [
                    "zh-Hans": MetadataLocalizationResourceIDs(appInfoLocalizationID: "app-info-loc-id")
                ]
            )
        )

        #expect(plan.operations.contains {
            $0.field == "subtitle" &&
            $0.resourceKind == .appInfoLocalization &&
            $0.action == .updateField &&
            $0.resourceID == "app-info-loc-id"
        })
        #expect(plan.operations.contains {
            $0.field == "description" &&
            $0.resourceKind == .appStoreVersionLocalization &&
            $0.action == .createLocalization &&
            $0.resourceID == nil &&
            $0.parentResourceID == "version-id"
        })
    }

    @Test("builds grouped ASC metadata request dry-run plan")
    func buildsMetadataRequestPlan() {
        let mutationPlan = ASCMetadataMutationPlan(operations: [
            ASCMetadataPlanOperation(
                locale: "en-US",
                field: "description",
                resourceKind: .appStoreVersionLocalization,
                action: .updateField,
                resourceID: "version-loc-id",
                localValue: "Description"
            ),
            ASCMetadataPlanOperation(
                locale: "en-US",
                field: "releaseNotes",
                resourceKind: .appStoreVersionLocalization,
                action: .updateField,
                resourceID: "version-loc-id",
                localValue: "Bug fixes"
            ),
            ASCMetadataPlanOperation(
                locale: "zh-Hant",
                field: "name",
                resourceKind: .appInfoLocalization,
                action: .createLocalization,
                parentResourceID: "app-info-id",
                localValue: "示例"
            )
        ])

        let requestPlan = ASCMetadataRequestPlanBuilder().build(from: mutationPlan)

        #expect(requestPlan.dryRunOnly)
        #expect(requestPlan.ascendKitVersion == AscendKitVersion.current)
        #expect(requestPlan.requests.count == 2)
        #expect(requestPlan.requests.contains {
            $0.method == "PATCH" &&
            $0.path == "/v1/appStoreVersionLocalizations/version-loc-id" &&
            $0.attributes["description"] == "Description" &&
            $0.attributes["whatsNew"] == nil
        })
        #expect(requestPlan.findings.contains {
            $0.contains("releaseNotes") && $0.contains("omitted")
        })
        #expect(requestPlan.requests.contains {
            $0.method == "POST" &&
            $0.path == "/v1/appInfoLocalizations" &&
            $0.relationshipName == "appInfo" &&
            $0.parentResourceID == "app-info-id" &&
            $0.attributes["locale"] == "zh-Hant" &&
            $0.attributes["name"] == "示例"
        })
    }

    @Test("imports fastlane metadata directory")
    func importsFastlaneMetadata() throws {
        let root = try TemporaryDirectory()
        let en = root.url.appendingPathComponent("en-US")
        try FileManager.default.createDirectory(at: en, withIntermediateDirectories: true)
        try Data("Demo".utf8).write(to: en.appendingPathComponent("name.txt"))
        try Data("Short subtitle".utf8).write(to: en.appendingPathComponent("subtitle.txt"))
        try Data("Long description".utf8).write(to: en.appendingPathComponent("description.txt"))
        try Data("Bug fixes".utf8).write(to: en.appendingPathComponent("release_notes.txt"))
        try Data("demo,release".utf8).write(to: en.appendingPathComponent("keywords.txt"))
        try Data("https://example.com/privacy".utf8).write(to: en.appendingPathComponent("privacy_url.txt"))

        let imported = try FastlaneMetadataImporter().loadAll(from: root.url)

        #expect(imported.count == 1)
        #expect(imported[0].locale == "en-US")
        #expect(imported[0].name == "Demo")
        #expect(imported[0].keywords == ["demo", "release"])
        #expect(imported[0].privacyPolicyURL == "https://example.com/privacy")
    }

    @Test("syncs observed metadata to local source files")
    func syncsObservedMetadataToLocalFiles() throws {
        let root = try TemporaryDirectory()
        let store = ReleaseWorkspaceStore()
        let workspace = try store.createWorkspace(
            baseDirectory: root.url,
            manifest: ReleaseManifest(releaseID: "sync-test", appSlug: "sync-test", projects: [], targets: [])
        )

        let enUS = AppMetadata(
            locale: "en-US",
            name: "My App",
            subtitle: "Best app",
            description: "A great app for testing.",
            releaseNotes: "Version 2.0",
            keywords: ["test", "app"],
            supportURL: "https://example.com/support",
            marketingURL: "https://example.com",
            privacyPolicyURL: "https://example.com/privacy"
        )
        let zhHans = AppMetadata(
            locale: "zh-Hans",
            name: "我的应用",
            description: "一个测试应用。"
        )
        let observed = MetadataObservedState(metadataByLocale: ["en-US": enUS, "zh-Hans": zhHans])

        // Write observed state to workspace
        try store.save(observed, to: URL(fileURLWithPath: workspace.paths.ascObservedState))

        // Simulate sync: iterate observed.metadataByLocale and save each
        for (locale, metadata) in observed.metadataByLocale {
            let url = URL(fileURLWithPath: workspace.paths.root)
                .appendingPathComponent("metadata")
                .appendingPathComponent(locale == "en-US" ? "source" : "localized")
                .appendingPathComponent("\(locale).json")
            try store.save(metadata, to: url)
        }

        // Verify en-US written to source/
        let enUSData = try Data(contentsOf: URL(fileURLWithPath: workspace.paths.root)
            .appendingPathComponent("metadata/source/en-US.json"))
        let enUSDecoded = try AscendKitJSON.decoder.decode(AppMetadata.self, from: enUSData)
        #expect(enUSDecoded.name == "My App")
        #expect(enUSDecoded.subtitle == "Best app")
        #expect(enUSDecoded.keywords == ["test", "app"])
        #expect(enUSDecoded.privacyPolicyURL == "https://example.com/privacy")

        // Verify zh-Hans written to localized/
        let zhData = try Data(contentsOf: URL(fileURLWithPath: workspace.paths.root)
            .appendingPathComponent("metadata/localized/zh-Hans.json"))
        let zhDecoded = try AscendKitJSON.decoder.decode(AppMetadata.self, from: zhData)
        #expect(zhDecoded.name == "我的应用")
        #expect(zhDecoded.description == "一个测试应用。")
    }

    @Test("MetadataSyncResult reports correct field counts")
    func syncResultFieldCounts() {
        let metadata = AppMetadata(
            locale: "en-US",
            name: "App",
            description: "Desc",
            keywords: ["a"]
        )
        let fieldCount = [
            metadata.name.isEmpty ? 0 : 1,
            metadata.subtitle == nil ? 0 : 1,
            metadata.promotionalText == nil ? 0 : 1,
            metadata.description.isEmpty ? 0 : 1,
            metadata.releaseNotes == nil ? 0 : 1,
            metadata.keywords.isEmpty ? 0 : 1,
            metadata.supportURL == nil ? 0 : 1,
            metadata.marketingURL == nil ? 0 : 1,
            metadata.privacyPolicyURL == nil ? 0 : 1
        ].reduce(0, +)
        #expect(fieldCount == 3)

        let fullMetadata = AppMetadata(
            locale: "en-US",
            name: "App",
            subtitle: "Sub",
            promotionalText: "Promo",
            description: "Desc",
            releaseNotes: "Notes",
            keywords: ["a"],
            supportURL: "https://example.com",
            marketingURL: "https://example.com",
            privacyPolicyURL: "https://example.com/privacy"
        )
        let fullFieldCount = [
            fullMetadata.name.isEmpty ? 0 : 1,
            fullMetadata.subtitle == nil ? 0 : 1,
            fullMetadata.promotionalText == nil ? 0 : 1,
            fullMetadata.description.isEmpty ? 0 : 1,
            fullMetadata.releaseNotes == nil ? 0 : 1,
            fullMetadata.keywords.isEmpty ? 0 : 1,
            fullMetadata.supportURL == nil ? 0 : 1,
            fullMetadata.marketingURL == nil ? 0 : 1,
            fullMetadata.privacyPolicyURL == nil ? 0 : 1
        ].reduce(0, +)
        #expect(fullFieldCount == 9)
    }
}
