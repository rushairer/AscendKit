import CryptoKit
import Foundation
import Testing
@testable import AscendKitCore

@Suite("ASC observation models")
struct ASCTests {
    @Test("identifies processable build candidates")
    func identifiesProcessableBuilds() {
        let report = BuildCandidatesReport(source: "test", candidates: [
            BuildCandidate(id: "processing", version: "1.0", buildNumber: "1", processingState: "processing"),
            BuildCandidate(id: "processed", version: "1.0", buildNumber: "2", processingState: "processed"),
            BuildCandidate(id: "valid", version: "1.0", buildNumber: "3", processingState: "valid")
        ])

        #expect(report.processableCandidates.map(\.id) == ["processed", "valid"])
    }

    @Test("selects exact build before latest same-version valid build")
    func selectsPreferredBuild() {
        let report = BuildCandidatesReport(source: "test", candidates: [
            BuildCandidate(id: "build-7", version: "1.0", buildNumber: "7", processingState: "VALID"),
            BuildCandidate(id: "build-21", version: "1.0", buildNumber: "21", processingState: "VALID"),
            BuildCandidate(id: "build-2", version: "2.0", buildNumber: "2", processingState: "VALID")
        ])

        #expect(report.preferredCandidate(version: "1.0", buildNumber: "7")?.id == "build-7")
        #expect(report.preferredCandidate(version: "1.0", buildNumber: "1")?.id == "build-21")
    }

    @Test("serializes observed metadata state for local ASC import")
    func serializesObservedMetadataState() throws {
        let observed = MetadataObservedState(metadataByLocale: [
            "en-US": AppMetadata(
                locale: "en-US",
                name: "Demo",
                subtitle: "Remote subtitle",
                description: "Remote description",
                releaseNotes: "Bug fixes"
            )
        ])

        let data = try AscendKitJSON.encoder.encode(observed)
        let decoded = try AscendKitJSON.decoder.decode(MetadataObservedState.self, from: data)

        #expect(decoded.metadataByLocale["en-US"]?.name == "Demo")
        #expect(decoded.source == "local-observation")
    }

    @Test("reports redacted ASC auth config status")
    func reportsASCAuthStatus() {
        let config = ASCAuthConfig(
            issuerID: "12345678-ABCD",
            keyID: "KEY1234567",
            privateKey: SecretRef(provider: .keychain, identifier: "com.example.asc.private-key")
        )

        let status = ASCAuthStatus(config: config)

        #expect(status.configured)
        #expect(status.issuerIDRedacted == "12...CD")
        #expect(status.keyIDRedacted == "KE...67")
        #expect(status.privateKeyRefRedacted == "keychain:co...ey")
        #expect(status.findings.isEmpty)
    }

    @Test("reports missing ASC auth fields")
    func reportsMissingASCAuthFields() {
        let config = ASCAuthConfig(
            issuerID: "",
            keyID: "",
            privateKey: SecretRef(provider: .environment, identifier: "")
        )

        let status = ASCAuthStatus(config: config)

        #expect(status.configured == false)
        #expect(status.findings.count == 3)
    }

    @Test("builds ASC lookup dry-run plan from manifest")
    func buildsLookupPlan() {
        let manifest = ReleaseManifest(
            releaseID: "demo-1.0-b7",
            appSlug: "demo",
            projects: [],
            targets: [
                BundleTarget(
                    name: "Demo",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "7"),
                    productType: "com.apple.product-type.application"
                ),
                BundleTarget(
                    name: "DemoTests",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo.tests",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "7"),
                    productType: "com.apple.product-type.bundle.unit-test"
                ),
                BundleTarget(
                    name: "DemoExtension",
                    platform: .iOS,
                    bundleIdentifier: "com.example.demo.extension",
                    version: VersionInfo(marketingVersion: "1.0", buildNumber: "7"),
                    productType: "com.apple.product-type.app-extension",
                    isExtension: true
                )
            ]
        )
        let auth = ASCAuthStatus(config: ASCAuthConfig(
            issuerID: "issuer",
            keyID: "key",
            privateKey: SecretRef(provider: .environment, identifier: "ASC_PRIVATE_KEY")
        ))

        let plan = ASCLookupPlanBuilder().build(manifest: manifest, authStatus: auth)

        #expect(plan.dryRunOnly)
        #expect(plan.authConfigured)
        #expect(plan.bundleIDs == ["com.example.demo"])
        #expect(plan.version == "1.0")
        #expect(plan.buildNumber == "7")
        #expect(plan.steps.map(\.pathTemplate) == ["/v1/apps", "/v1/apps/{id}/builds"])
        #expect(plan.steps[0].query["filter[bundleId]"] == "com.example.demo")
        #expect(plan.steps[1].query["filter[version]"] == "7")
        #expect(plan.capabilityNotes.allSatisfy { $0.status == .observationOnly })
        #expect(plan.findings.isEmpty)
    }

    @Test("lookup plan records missing auth and release identifiers")
    func lookupPlanRecordsMissingInputs() {
        let manifest = ReleaseManifest(
            releaseID: "empty",
            appSlug: "empty",
            projects: [],
            targets: []
        )

        let plan = ASCLookupPlanBuilder().build(manifest: manifest, authStatus: ASCAuthStatus(config: nil))

        #expect(plan.authConfigured == false)
        #expect(plan.findings.contains("No release bundle identifier is available for ASC app lookup."))
        #expect(plan.findings.contains("ASC auth config is missing."))
    }

    @Test("stores ASC auth profile with secret reference only")
    func storesASCAuthProfile() throws {
        let root = try TemporaryDirectory()
        let store = ASCAuthProfileStore(root: root.url)
        let profile = ASCAuthProfile(
            name: "default",
            config: ASCAuthConfig(
                issuerID: "issuer",
                keyID: "key",
                privateKey: SecretRef(provider: .file, identifier: "/secure/AuthKey.p8")
            )
        )

        let url = try store.save(profile)
        let loaded = try store.load(name: "default")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

        #expect(loaded.config.privateKey.identifier == "/secure/AuthKey.p8")
        #expect(store.list().map(\.name) == ["default"])
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("signs ASC JWT without exposing private key material")
    func signsASCJWT() throws {
        let key = P256.Signing.PrivateKey()
        let config = ASCAuthConfig(
            issuerID: "issuer-id",
            keyID: "KEYID12345",
            privateKey: SecretRef(provider: .environment, identifier: "ASC_PRIVATE_KEY")
        )

        let token = try ASCJWTSigner().token(
            config: config,
            privateKeyPEM: key.pemRepresentation,
            issuedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let parts = token.split(separator: ".").map(String.init)
        let header = try JSONSerialization.jsonObject(with: try decodeBase64URL(parts[0])) as? [String: String]
        let claims = try JSONSerialization.jsonObject(with: try decodeBase64URL(parts[1])) as? [String: Any]

        #expect(parts.count == 3)
        #expect(header?["alg"] == "ES256")
        #expect(header?["kid"] == "KEYID12345")
        #expect(claims?["iss"] as? String == "issuer-id")
        #expect(claims?["aud"] as? String == "appstoreconnect-v1")
        #expect(claims?["iat"] as? Int == 1_700_000_000)
        #expect(claims?["exp"] as? Int == 1_700_001_200)
        #expect(!token.contains(key.pemRepresentation))
    }

    @Test("serializes ASC apps lookup report")
    func serializesAppsLookupReport() throws {
        let report = ASCAppsLookupReport(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            bundleIDs: ["com.example.demo"],
            apps: [
                ASCObservedApp(
                    id: "123",
                    name: "Demo",
                    bundleID: "com.example.demo",
                    sku: "DEMO",
                    primaryLocale: "en-US"
                )
            ]
        )

        let data = try AscendKitJSON.encoder.encode(report)
        let decoded = try AscendKitJSON.decoder.decode(ASCAppsLookupReport.self, from: data)

        #expect(decoded.source == "app-store-connect-api")
        #expect(decoded.bundleIDs == ["com.example.demo"])
        #expect(decoded.apps.first?.id == "123")
        #expect(decoded.apps.first?.bundleID == "com.example.demo")
    }

    @Test("serializes ASC app pricing result")
    func serializesAppPricingResult() throws {
        let result = ASCAppPricingResult(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            executed: true,
            appID: "123",
            baseTerritory: "USA",
            pricePointID: "free-price-point",
            priceScheduleID: "123",
            responses: [
                ReviewSubmissionExecutionResponse(
                    id: "app-pricing.set-free",
                    method: "POST",
                    path: "/v1/appPriceSchedules",
                    statusCode: 201,
                    resourceID: "123"
                )
            ],
            findings: ["Free pricing was set through the official App Store Connect appPriceSchedules API."]
        )

        let data = try AscendKitJSON.encoder.encode(result)
        let decoded = try AscendKitJSON.decoder.decode(ASCAppPricingResult.self, from: data)

        #expect(decoded.executed)
        #expect(decoded.appID == "123")
        #expect(decoded.baseTerritory == "USA")
        #expect(decoded.pricePointID == "free-price-point")
        #expect(decoded.responses.first?.id == "app-pricing.set-free")
    }

    @Test("serializes screenshot upload execution result")
    func serializesScreenshotUploadExecutionResult() throws {
        let result = ScreenshotUploadExecutionResult(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            executed: true,
            uploadedCount: 1,
            items: [
                ScreenshotUploadExecutionItem(
                    planItemID: "en-US:iOS:APP_IPHONE_67:1:home.png",
                    appScreenshotSetID: "set-1",
                    appScreenshotID: "screenshot-1",
                    fileName: "home.png",
                    checksum: "d41d8cd98f00b204e9800998ecf8427e",
                    assetDeliveryState: "COMPLETE",
                    responses: [
                        ReviewSubmissionExecutionResponse(
                            id: "app-screenshot.commit",
                            method: "PATCH",
                            path: "/v1/appScreenshots/screenshot-1",
                            statusCode: 200,
                            resourceID: "screenshot-1"
                        )
                    ]
                )
            ],
            findings: ["Screenshot upload executed through the official App Store Connect screenshot asset API."]
        )

        let data = try AscendKitJSON.encoder.encode(result)
        let decoded = try AscendKitJSON.decoder.decode(ScreenshotUploadExecutionResult.self, from: data)

        #expect(decoded.executed)
        #expect(decoded.uploadedCount == 1)
        #expect(decoded.items.first?.appScreenshotSetID == "set-1")
        #expect(decoded.items.first?.checksum == "d41d8cd98f00b204e9800998ecf8427e")
    }

    @Test("screenshot upload execution requires explicit confirmation")
    func screenshotUploadRequiresConfirmation() async throws {
        let plan = ScreenshotUploadPlan(
            sourceKind: .imported,
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

        let result = try await ASCAPIClient().executeScreenshotUpload(
            plan: plan,
            confirmRemoteMutation: false,
            token: "unused"
        )

        #expect(result.executed == false)
        #expect(result.findings.contains("Missing --confirm-remote-mutation. No screenshot upload request was executed."))
    }

    @Test("serializes review submission execution result")
    func serializesReviewSubmissionExecutionResult() throws {
        let result = ReviewSubmissionExecutionResult(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            executed: true,
            appStoreVersionID: "version-1",
            buildID: "build-7",
            appStoreReviewDetailID: "review-detail-1",
            reviewSubmissionID: "submission-1",
            reviewSubmissionItemID: "submission-item-1",
            submitted: true,
            responses: [
                ReviewSubmissionExecutionResponse(
                    id: "review-submission.submit",
                    method: "PATCH",
                    path: "/v1/reviewSubmissions/submission-1",
                    statusCode: 200,
                    resourceID: "submission-1"
                )
            ],
            findings: ["Remote review submission execution was explicitly confirmed and executed."]
        )

        let data = try AscendKitJSON.encoder.encode(result)
        let decoded = try AscendKitJSON.decoder.decode(ReviewSubmissionExecutionResult.self, from: data)

        #expect(decoded.executed)
        #expect(decoded.submitted)
        #expect(decoded.reviewSubmissionID == "submission-1")
        #expect(decoded.responses.first?.id == "review-submission.submit")
    }

    private func decodeBase64URL(_ value: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64) else {
            throw AscendKitError.invalidState("Invalid base64url value.")
        }
        return data
    }
}
