import Foundation
import Testing
@testable import AscendKitCore

@Suite("Submission readiness")
struct SubmissionTests {
    @Test("requires reviewer info when missing")
    func requiresReviewerInfo() {
        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "7"),
                    productType: "com.apple.product-type.application"
                )
            ]
        )

        let report = SubmissionReadinessEvaluator().evaluate(manifest: manifest)

        #expect(report.ready == false)
        #expect(report.items.contains { $0.id == "review.info" && !$0.satisfied })
        #expect(report.items.contains { $0.id == "doctor.report" && !$0.satisfied })
        #expect(report.items.contains { $0.id == "metadata.lint" && !$0.satisfied })
        #expect(report.items.contains { $0.id == "screenshots.import" && !$0.satisfied })
        #expect(report.items.contains { $0.id == "screenshots.composition" && !$0.satisfied })
    }

    @Test("accepts complete reviewer contact without login")
    func acceptsCompleteReviewerInfo() {
        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "7"),
                    productType: "com.apple.product-type.application"
                )
            ]
        )
        let reviewInfo = ReviewInfo(
            contact: ReviewerContact(firstName: "Ada", lastName: "Lovelace", email: "review@example.com", phone: "+15555555555"),
            access: ReviewerAccess(requiresLogin: false),
            notes: "No login required."
        )

        let doctorReport = DoctorReport(findings: [])
        let metadataLint = MetadataLintReport(locale: "en-US", findings: [])
        let screenshotImport = ScreenshotImportManifest(
            sourceDirectory: "/tmp/screenshots",
            artifacts: [
                ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/screenshots/en-US/iOS/01.png", fileName: "01.png")
            ]
        )
        let screenshotComposition = ScreenshotCompositionManifest(
            mode: .poster,
            artifacts: [
                ScreenshotCompositionArtifact(
                    locale: "en-US",
                    platform: .iOS,
                    inputPath: "/tmp/screenshots/en-US/iOS/01.png",
                    outputPath: "/tmp/composed/poster/en-US/iOS/01.png",
                    mode: .poster
                )
            ]
        )
        let builds = BuildCandidatesReport(source: "test", candidates: [
            BuildCandidate(id: "build-7", version: "1.0", buildNumber: "7", processingState: "processed")
        ])
        let ascLookupPlan = readyASCLookupPlan()
        let iapValidation = IAPValidationReport(templates: SubscriptionTemplateFactory.starter(appBundleID: "com.example.demo"))

        let report = SubmissionReadinessEvaluator().evaluate(
            manifest: manifest,
            doctorReport: doctorReport,
            reviewInfo: reviewInfo,
            metadataLintReports: [metadataLint],
            screenshotImportManifest: screenshotImport,
            screenshotCompositionManifest: screenshotComposition,
            ascLookupPlan: ascLookupPlan,
            appPrivacyStatus: readyAppPrivacyStatus(),
            buildCandidatesReport: builds,
            iapValidationReport: iapValidation
        )

        #expect(report.ready)
        #expect(report.items.first { $0.id == "review.contact" }?.satisfied == true)
        #expect(report.items.first { $0.id == "review.access" }?.satisfied == true)
        #expect(report.items.first { $0.id == "metadata.lint" }?.satisfied == true)
        #expect(report.items.first { $0.id == "screenshots.import" }?.satisfied == true)
        #expect(report.items.first { $0.id == "screenshots.composition" }?.satisfied == true)
        #expect(report.items.first { $0.id == "asc.lookup-plan" }?.satisfied == true)
        #expect(report.items.first { $0.id == "build.processable" }?.satisfied == true)
        #expect(report.items.first { $0.id == "app-privacy.published" }?.satisfied == true)
        #expect(report.items.first { $0.id == "iap.validation" }?.satisfied == true)
    }

    @Test("requires published App Privacy answers")
    func requiresPublishedAppPrivacyAnswers() {
        let report = SubmissionReadinessEvaluator().evaluate(
            manifest: readyManifest(),
            doctorReport: DoctorReport(findings: []),
            reviewInfo: readyReviewInfo(),
            metadataLintReports: [MetadataLintReport(locale: "en-US", findings: [])],
            screenshotImportManifest: ScreenshotImportManifest(
                sourceDirectory: "/tmp/screenshots",
                artifacts: [ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/screenshots/en-US/iOS/01.png", fileName: "01.png")]
            ),
            screenshotCompositionManifest: readyScreenshotComposition(),
            ascLookupPlan: readyASCLookupPlan(),
            appPrivacyStatus: AppPrivacyStatus(
                state: .requiresManualAppStoreConnect,
                source: "apple-iris-api-key-unauthorized",
                findings: ["Complete App Privacy in App Store Connect UI."]
            ),
            buildCandidatesReport: readyBuildCandidates()
        )

        #expect(report.ready == false)
        #expect(report.items.first { $0.id == "app-privacy.published" }?.satisfied == false)
        #expect(report.items.first { $0.id == "app-privacy.published" }?.note?.contains("asc privacy status") == true)
        #expect(report.items.first { $0.id == "app-privacy.published" }?.note?.contains("confirm-manual") == true)
    }

    @Test("serializes App Privacy readiness and next actions")
    func serializesAppPrivacyReadinessAndNextActions() throws {
        let status = AppPrivacyStatus(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            state: .requiresManualAppStoreConnect,
            source: "apple-iris-api-key-unauthorized",
            findings: ["Apple IRIS rejected API key auth."]
        )

        let output = try AscendKitJSON.encodeString(status)
        let decoded = try AscendKitJSON.decoder.decode(AppPrivacyStatus.self, from: Data(output.utf8))

        #expect(output.contains("\"readyForSubmission\" : false"))
        #expect(output.contains("\"nextActions\""))
        #expect(output.contains("asc privacy confirm-manual --data-not-collected"))
        #expect(decoded.readyForSubmission == false)
        #expect(decoded.nextActions.contains { $0.contains("App Store Connect UI") })
    }

    @Test("requires ASC lookup dry-run plan")
    func requiresASCLookupPlan() {
        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "7"),
                    productType: "com.apple.product-type.application"
                )
            ]
        )

        let report = SubmissionReadinessEvaluator().evaluate(
            manifest: manifest,
            doctorReport: DoctorReport(findings: []),
            reviewInfo: ReviewInfo(
                contact: ReviewerContact(firstName: "Ada", lastName: "Lovelace", email: "review@example.com", phone: "+15555555555"),
                access: ReviewerAccess(requiresLogin: false)
            ),
            metadataLintReports: [MetadataLintReport(locale: "en-US", findings: [])],
            screenshotImportManifest: ScreenshotImportManifest(
                sourceDirectory: "/tmp/screenshots",
                artifacts: [ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/screenshots/en-US/iOS/01.png", fileName: "01.png")]
            ),
            screenshotCompositionManifest: ScreenshotCompositionManifest(
                mode: .storeReadyCopy,
                artifacts: [
                    ScreenshotCompositionArtifact(
                        locale: "en-US",
                        platform: .iOS,
                        inputPath: "/tmp/screenshots/en-US/iOS/01.png",
                        outputPath: "/tmp/composed/storeReadyCopy/en-US/iOS/01.png",
                        mode: .storeReadyCopy
                    )
                ]
            ),
            buildCandidatesReport: BuildCandidatesReport(
                source: "test",
                candidates: [BuildCandidate(id: "build", version: "1.0", buildNumber: "7", processingState: "processed")]
            )
        )

        #expect(report.ready == false)
        #expect(report.items.first { $0.id == "asc.lookup-plan" }?.satisfied == false)
    }

    @Test("requires composed screenshots after import")
    func requiresComposedScreenshots() {
        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "7"),
                    productType: "com.apple.product-type.application"
                )
            ]
        )

        let report = SubmissionReadinessEvaluator().evaluate(
            manifest: manifest,
            doctorReport: DoctorReport(findings: []),
            reviewInfo: ReviewInfo(
                contact: ReviewerContact(firstName: "Ada", lastName: "Lovelace", email: "review@example.com", phone: "+15555555555"),
                access: ReviewerAccess(requiresLogin: false)
            ),
            metadataLintReports: [MetadataLintReport(locale: "en-US", findings: [])],
            screenshotImportManifest: ScreenshotImportManifest(
                sourceDirectory: "/tmp/screenshots",
                artifacts: [ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/screenshots/en-US/iOS/01.png", fileName: "01.png")]
            ),
            buildCandidatesReport: BuildCandidatesReport(
                source: "test",
                candidates: [BuildCandidate(id: "build", version: "1.0", buildNumber: "7", processingState: "processed")]
            )
        )

        #expect(report.ready == false)
        #expect(report.items.first { $0.id == "screenshots.composition" }?.satisfied == false)
    }

    @Test("requires copy lint for framed poster screenshots")
    func requiresCopyLintForFramedPosterScreenshots() {
        let report = SubmissionReadinessEvaluator().evaluate(
            manifest: readyManifest(),
            doctorReport: DoctorReport(findings: []),
            reviewInfo: readyReviewInfo(),
            metadataLintReports: [MetadataLintReport(locale: "en-US", findings: [])],
            screenshotImportManifest: ScreenshotImportManifest(
                sourceDirectory: "/tmp/screenshots",
                artifacts: [ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/screenshots/en-US/iOS/01.png", fileName: "01.png")]
            ),
            screenshotCompositionManifest: ScreenshotCompositionManifest(
                mode: .framedPoster,
                artifacts: [
                    ScreenshotCompositionArtifact(
                        locale: "en-US",
                        platform: .iOS,
                        inputPath: "/tmp/screenshots/en-US/iOS/01.png",
                        outputPath: "/tmp/composed/framedPoster/en-US/iOS/01.png",
                        mode: .framedPoster
                    )
                ]
            ),
            ascLookupPlan: readyASCLookupPlan(),
            appPrivacyStatus: readyAppPrivacyStatus(),
            buildCandidatesReport: readyBuildCandidates()
        )

        #expect(report.ready == false)
        #expect(report.items.first { $0.id == "screenshots.copy-lint" }?.satisfied == false)
    }

    @Test("fails readiness when metadata lint has findings")
    func failsForMetadataLintFindings() {
        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    productType: "com.apple.product-type.application"
                )
            ]
        )
        let lint = MetadataLintReport(locale: "en-US", findings: [
            MetadataLintFinding(id: "name.required", severity: .error, field: "name", message: "name is required")
        ])

        let report = SubmissionReadinessEvaluator().evaluate(
            manifest: manifest,
            doctorReport: DoctorReport(findings: []),
            reviewInfo: ReviewInfo(
                contact: ReviewerContact(firstName: "Ada", lastName: "Lovelace", email: "review@example.com", phone: "+15555555555"),
                access: ReviewerAccess(requiresLogin: false)
            ),
            metadataLintReports: [lint],
            screenshotImportManifest: ScreenshotImportManifest(
                sourceDirectory: "/tmp/screenshots",
                artifacts: [ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/screenshots/en-US/iOS/01.png", fileName: "01.png")]
            ),
            buildCandidatesReport: BuildCandidatesReport(
                source: "test",
                candidates: [BuildCandidate(id: "build", version: "1.0", buildNumber: "1", processingState: "processed")]
            ),
            iapValidationReport: IAPValidationReport(templates: [
                SubscriptionTemplate(id: "a", referenceName: "A", productID: "com.example.sub", cadence: .monthly, displayName: "A", reviewNotes: "Review A"),
                SubscriptionTemplate(id: "b", referenceName: "B", productID: "com.example.sub", cadence: .yearly, displayName: "B", reviewNotes: "Review B")
            ])
        )

        #expect(report.ready == false)
        #expect(report.items.first { $0.id == "metadata.lint" }?.satisfied == false)
        #expect(report.items.first { $0.id == "iap.validation" }?.satisfied == false)
    }

    @Test("does not require IAP validation when app has no local IAP templates")
    func doesNotRequireIAPWhenAbsent() {
        let manifest = ReleaseManifest(
            releaseID: "demo",
            appSlug: "demo",
            projects: [],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "7"),
                    productType: "com.apple.product-type.application"
                )
            ]
        )
        let report = SubmissionReadinessEvaluator().evaluate(
            manifest: manifest,
            doctorReport: DoctorReport(findings: []),
            reviewInfo: ReviewInfo(
                contact: ReviewerContact(firstName: "Ada", lastName: "Lovelace", email: "review@example.com", phone: "+15555555555"),
                access: ReviewerAccess(requiresLogin: false)
            ),
            metadataLintReports: [MetadataLintReport(locale: "en-US", findings: [])],
            screenshotImportManifest: ScreenshotImportManifest(
                sourceDirectory: "/tmp/screenshots",
                artifacts: [ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/screenshots/en-US/iOS/01.png", fileName: "01.png")]
            ),
            screenshotCompositionManifest: ScreenshotCompositionManifest(
                mode: .storeReadyCopy,
                artifacts: [
                    ScreenshotCompositionArtifact(
                        locale: "en-US",
                        platform: .iOS,
                        inputPath: "/tmp/screenshots/en-US/iOS/01.png",
                        outputPath: "/tmp/composed/storeReadyCopy/en-US/iOS/01.png",
                        mode: .storeReadyCopy
                    )
                ]
            ),
            ascLookupPlan: readyASCLookupPlan(),
            appPrivacyStatus: readyAppPrivacyStatus(),
            buildCandidatesReport: BuildCandidatesReport(
                source: "test",
                candidates: [BuildCandidate(id: "build", version: "1.0", buildNumber: "7", processingState: "processed")]
            )
        )

        #expect(report.ready)
        #expect(report.items.contains { $0.id == "iap.validation" } == false)
    }

    @Test("builds submission preparation summary")
    func buildsPreparationSummary() {
        let manifest = ReleaseManifest(
            releaseID: "demo-1.0",
            appSlug: "demo",
            projects: [],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "7"),
                    productType: "com.apple.product-type.application"
                )
            ]
        )
        let readiness = SubmissionReadinessReport(items: [
            SubmissionChecklistItem(id: "example", title: "Example", satisfied: true)
        ])
        let metadataLint = MetadataLintReport(locale: "en-US", findings: [])
        let screenshots = ScreenshotImportManifest(
            sourceDirectory: "/tmp/screenshots",
            artifacts: [
                ScreenshotArtifact(locale: "en-US", platform: .iOS, path: "/tmp/screenshots/en-US/iOS/01.png", fileName: "01.png")
            ]
        )
        let composedScreenshots = ScreenshotCompositionManifest(
            mode: .storeReadyCopy,
            artifacts: [
                ScreenshotCompositionArtifact(
                    locale: "en-US",
                    platform: .iOS,
                    inputPath: "/tmp/screenshots/en-US/iOS/01.png",
                    outputPath: "/tmp/composed/storeReadyCopy/en-US/iOS/01.png",
                    mode: .storeReadyCopy
                )
            ]
        )
        let reviewInfo = ReviewInfo(notes: "Review notes")
        let builds = BuildCandidatesReport(source: "test", candidates: [
            BuildCandidate(id: "build-7", version: "1.0", buildNumber: "7", processingState: "processed")
        ])
        let ascLookupPlan = readyASCLookupPlan()
        let iapValidation = IAPValidationReport(templates: SubscriptionTemplateFactory.starter(appBundleID: "com.example.demo"))

        let preparation = SubmissionPreparationBuilder().build(
            manifest: manifest,
            readiness: readiness,
            metadataLintReports: [metadataLint],
            screenshotImportManifest: screenshots,
            screenshotCompositionManifest: composedScreenshots,
            ascLookupPlan: ascLookupPlan,
            buildCandidatesReport: builds,
            iapValidationReport: iapValidation,
            reviewInfo: reviewInfo
        )

        #expect(preparation.releaseID == "demo-1.0")
        #expect(preparation.ready)
        #expect(preparation.metadataLocales == ["en-US"])
        #expect(preparation.screenshotArtifactCount == 1)
        #expect(preparation.composedScreenshotArtifactCount == 1)
        #expect(preparation.ascLookupStepCount == 2)
        #expect(preparation.ascLookupFindingCount == 0)
        #expect(preparation.processableBuildCount == 1)
        #expect(preparation.iapFindingCount == 0)
        #expect(preparation.reviewNotesPresent)
        #expect(preparation.targetSummaries == ["Demo (com.example.demo) 1.0 build 7"])
    }

    @Test("allows handoff when only release notes remain unsynced")
    func reviewPlanAllowsOnlyReleaseNotesDiffs() {
        let plan = ReviewSubmissionPlanBuilder().build(
            manifest: readyManifest(),
            reviewInfo: readyReviewInfo(),
            readiness: SubmissionReadinessReport(items: [
                SubmissionChecklistItem(id: "ready", title: "Ready", satisfied: true)
            ]),
            screenshotCompositionManifest: readyScreenshotComposition(),
            appsLookupReport: ASCAppsLookupReport(
                bundleIDs: ["com.example.demo"],
                apps: [ASCObservedApp(id: "app-1", name: "Demo", bundleID: "com.example.demo")]
            ),
            metadataApplyResult: ASCMetadataApplyResult(
                generatedAt: Date(timeIntervalSince1970: 100),
                applied: true
            ),
            metadataDiffReport: MetadataDiffReport(
                generatedAt: Date(timeIntervalSince1970: 101),
                diffs: [
                    MetadataFieldDiff(
                        locale: "en-US",
                        field: "releaseNotes",
                        status: .changed,
                        localValue: "New notes",
                        remoteValue: nil
                    )
                ]
            ),
            appPrivacyStatus: readyAppPrivacyStatus(),
            buildCandidatesReport: readyBuildCandidates()
        )

        #expect(plan.readyForManualReviewSubmission)
        #expect(plan.remoteSubmissionExecutionAllowed == false)
        #expect(plan.metadataRemainingDiffCount == 1)
        #expect(plan.metadataRemainingBlockingDiffCount == 0)
        #expect(plan.findings.contains { $0.contains("releaseNotes/whatsNew remains unsynced") })
    }

    @Test("requires metadata diff after latest metadata apply")
    func reviewPlanRequiresFreshMetadataDiffAfterApply() {
        let plan = ReviewSubmissionPlanBuilder().build(
            manifest: readyManifest(),
            reviewInfo: readyReviewInfo(),
            readiness: SubmissionReadinessReport(items: [
                SubmissionChecklistItem(id: "ready", title: "Ready", satisfied: true)
            ]),
            screenshotCompositionManifest: readyScreenshotComposition(),
            appsLookupReport: ASCAppsLookupReport(
                bundleIDs: ["com.example.demo"],
                apps: [ASCObservedApp(id: "app-1", name: "Demo", bundleID: "com.example.demo")]
            ),
            metadataApplyResult: ASCMetadataApplyResult(
                generatedAt: Date(timeIntervalSince1970: 200),
                applied: true
            ),
            metadataDiffReport: MetadataDiffReport(
                generatedAt: Date(timeIntervalSince1970: 199),
                diffs: []
            ),
            appPrivacyStatus: readyAppPrivacyStatus(),
            buildCandidatesReport: readyBuildCandidates()
        )

        #expect(plan.readyForManualReviewSubmission == false)
        #expect(plan.findings.contains { $0.contains("metadata diff is older") })
    }

    @Test("review plan includes app privacy handoff state")
    func reviewPlanIncludesAppPrivacyHandoffState() {
        let plan = ReviewSubmissionPlanBuilder().build(
            manifest: readyManifest(),
            reviewInfo: readyReviewInfo(),
            readiness: SubmissionReadinessReport(items: [
                SubmissionChecklistItem(id: "ready", title: "Ready", satisfied: true)
            ]),
            screenshotCompositionManifest: readyScreenshotComposition(),
            appsLookupReport: ASCAppsLookupReport(
                bundleIDs: ["com.example.demo"],
                apps: [ASCObservedApp(id: "app-1", name: "Demo", bundleID: "com.example.demo")]
            ),
            metadataApplyResult: ASCMetadataApplyResult(
                generatedAt: Date(timeIntervalSince1970: 100),
                applied: true
            ),
            metadataDiffReport: MetadataDiffReport(
                generatedAt: Date(timeIntervalSince1970: 101),
                diffs: []
            ),
            appPrivacyStatus: AppPrivacyStatus(
                state: .requiresManualAppStoreConnect,
                source: "apple-iris-api-key-unauthorized",
                findings: ["Complete App Privacy in App Store Connect UI."]
            ),
            buildCandidatesReport: readyBuildCandidates()
        )

        #expect(plan.readyForManualReviewSubmission == false)
        #expect(plan.appPrivacyState == "requiresManualAppStoreConnect")
        #expect(plan.appPrivacySource == "apple-iris-api-key-unauthorized")
        #expect(plan.appPrivacyReadyForSubmission == false)
        #expect(plan.appPrivacyNextActions?.contains { $0.contains("confirm-manual") } == true)
        #expect(plan.findings.contains { $0.contains("requiresManualAppStoreConnect") })
        #expect(plan.findings.contains { $0.contains("apple-iris-api-key-unauthorized") })
        #expect(plan.findings.contains { $0.contains("asc privacy status") })
    }

    @Test("review plan includes next actions when App Privacy status is missing")
    func reviewPlanIncludesMissingAppPrivacyNextActions() {
        let plan = ReviewSubmissionPlanBuilder().build(
            manifest: readyManifest(),
            reviewInfo: readyReviewInfo(),
            readiness: SubmissionReadinessReport(items: [
                SubmissionChecklistItem(id: "ready", title: "Ready", satisfied: true)
            ]),
            screenshotCompositionManifest: readyScreenshotComposition(),
            appsLookupReport: ASCAppsLookupReport(
                bundleIDs: ["com.example.demo"],
                apps: [ASCObservedApp(id: "app-1", name: "Demo", bundleID: "com.example.demo")]
            ),
            metadataApplyResult: ASCMetadataApplyResult(
                generatedAt: Date(timeIntervalSince1970: 100),
                applied: true
            ),
            metadataDiffReport: MetadataDiffReport(
                generatedAt: Date(timeIntervalSince1970: 101),
                diffs: []
            ),
            appPrivacyStatus: nil,
            buildCandidatesReport: readyBuildCandidates()
        )

        #expect(plan.appPrivacyState == "unknown")
        #expect(plan.appPrivacySource == "workspace")
        #expect(plan.appPrivacyReadyForSubmission == false)
        #expect(plan.appPrivacyNextActions?.contains { $0.contains("asc privacy set-not-collected") } == true)
        #expect(plan.readyForManualReviewSubmission == false)
    }

    @Test("renders review handoff markdown with explicit MVP boundary")
    func rendersReviewHandoffMarkdown() {
        let plan = ReviewSubmissionPlan(
            releaseID: "demo-1.0",
            appID: "app-1",
            selectedBuildID: "build-7",
            selectedBuildVersion: "1.0",
            selectedBuildNumber: "7",
            reviewerName: "Ada Lovelace",
            reviewerPhone: "+15555555555",
            metadataApplied: true,
            metadataRemainingDiffCount: 0,
            metadataRemainingBlockingDiffCount: 0,
            metadataApplyFindings: [],
            screenshotArtifactCount: 3,
            appPrivacyState: "publishedDataNotCollected",
            appPrivacySource: "manual-app-store-connect",
            appPrivacyReadyForSubmission: true,
            appPrivacyNextActions: [],
            readinessReady: true,
            readyForManualReviewSubmission: true,
            findings: ["Remote review submission execution is intentionally disabled in this MVP boundary."]
        )

        let markdown = ReviewHandoffMarkdown().render(plan: plan)

        #expect(markdown.contains("Manual review submission readiness: ready"))
        #expect(markdown.contains("- Selected build: 1.0 (7)"))
        #expect(markdown.contains("- Composed screenshot artifacts: 3"))
        #expect(markdown.contains("## App Privacy"))
        #expect(markdown.contains("- State: publishedDataNotCollected"))
        #expect(markdown.contains("- Ready for submission: yes"))
        #expect(markdown.contains("AscendKit MVP does not execute remote review submission."))
    }

    private func readyASCLookupPlan() -> ASCLookupPlan {
        ASCLookupPlan(
            releaseID: "demo",
            bundleIDs: ["com.example.demo"],
            version: "1.0",
            buildNumber: "7",
            authConfigured: true,
            steps: [
                ASCLookupStep(id: "apps.lookup-by-bundle-id", kind: .listApps, pathTemplate: "/v1/apps", purpose: "Lookup app"),
                ASCLookupStep(id: "builds.lookup-for-app", kind: .listAppBuilds, pathTemplate: "/v1/apps/{id}/builds", purpose: "Lookup builds")
            ],
            capabilityNotes: [],
            findings: []
        )
    }

    private func readyManifest() -> ReleaseManifest {
        ReleaseManifest(
            releaseID: "demo-1.0",
            appSlug: "demo",
            projects: [],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "7"),
                    productType: "com.apple.product-type.application"
                )
            ]
        )
    }

    private func readyReviewInfo() -> ReviewInfo {
        ReviewInfo(
            contact: ReviewerContact(
                firstName: "Ada",
                lastName: "Lovelace",
                email: "review@example.com",
                phone: "+15555555555"
            ),
            access: ReviewerAccess(requiresLogin: false),
            notes: "No login required."
        )
    }

    private func readyScreenshotComposition() -> ScreenshotCompositionManifest {
        ScreenshotCompositionManifest(
            mode: .deviceFrame,
            artifacts: [
                ScreenshotCompositionArtifact(
                    locale: "en-US",
                    platform: .iOS,
                    inputPath: "/tmp/screenshots/en-US/iOS/01.png",
                    outputPath: "/tmp/composed/deviceFrame/en-US/iOS/01.png",
                    mode: .deviceFrame
                )
            ]
        )
    }

    private func readyBuildCandidates() -> BuildCandidatesReport {
        BuildCandidatesReport(
            source: "test",
            candidates: [
                BuildCandidate(id: "build-7", version: "1.0", buildNumber: "7", processingState: "processed")
            ]
        )
    }

    private func readyAppPrivacyStatus() -> AppPrivacyStatus {
        AppPrivacyStatus(
            state: .publishedDataNotCollected,
            source: "manual-app-store-connect",
            findings: []
        )
    }
}
