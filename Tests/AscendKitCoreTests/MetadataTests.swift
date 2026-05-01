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
        #expect(report.diffs.contains { $0.field == "subtitle" && $0.status == .changed })
        #expect(report.diffs.contains { $0.field == "releaseNotes" && $0.status == .missingRemote })
    }

    @Test("summarizes ASC metadata sync status")
    func summarizesASCMetadataSyncStatus() {
        let status = ASCMetadataSyncStatusBuilder().build(
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
        #expect(status.applyResponseCount == 1)
        #expect(status.diffFresh == true)
        #expect(status.remainingDiffCount == 1)
        #expect(status.blockingDiffCount == 0)
        #expect(status.releaseNotesOnlyDiff)
        #expect(status.readyForReviewPlan)
        #expect(status.findings.contains { $0.contains("releaseNotes/whatsNew") })
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
}
