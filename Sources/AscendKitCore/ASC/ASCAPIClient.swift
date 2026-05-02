import CryptoKit
import Foundation

public struct ASCSecretResolver {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func resolve(_ ref: SecretRef) throws -> String {
        switch ref.provider {
        case .environment:
            guard let value = ProcessInfo.processInfo.environment[ref.identifier], !value.isEmpty else {
                throw AscendKitError.invalidState("Missing environment secret: \(ref.identifier)")
            }
            return value
        case .file:
            let path = expandHome(ref.identifier)
            guard fileManager.fileExists(atPath: path) else {
                throw AscendKitError.fileNotFound(path)
            }
            return try String(contentsOfFile: path, encoding: .utf8)
        case .keychain:
            throw AscendKitError.unsupported("Keychain secret references are not supported in this release; use file or environment references.")
        }
    }

    private func expandHome(_ path: String) -> String {
        if path == "~" {
            return NSHomeDirectory()
        }
        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(String(path.dropFirst(2)))
                .path
        }
        return path
    }
}

public struct ASCJWTSigner {
    public init() {}

    public func token(config: ASCAuthConfig, privateKeyPEM: String, issuedAt: Date = Date()) throws -> String {
        let header = ["alg": "ES256", "kid": config.keyID, "typ": "JWT"]
        let claims: [String: Any] = [
            "iss": config.issuerID,
            "iat": Int(issuedAt.timeIntervalSince1970),
            "exp": Int(issuedAt.addingTimeInterval(20 * 60).timeIntervalSince1970),
            "aud": "appstoreconnect-v1"
        ]
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let claimsData = try JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
        let signingInput = "\(base64URL(headerData)).\(base64URL(claimsData))"
        let key = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        let signature = try key.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(base64URL(signature.rawRepresentation))"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct ASCAPIClient {
    public let baseURL: URL
    public let irisBaseURL: URL
    public let session: URLSession

    public init(
        baseURL: URL = URL(string: "https://api.appstoreconnect.apple.com")!,
        irisBaseURL: URL = URL(string: "https://appstoreconnect.apple.com/iris")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.irisBaseURL = irisBaseURL
        self.session = session
    }

    public func lookupApps(bundleIDs: [String], token: String) async throws -> ASCAppsLookupReport {
        guard !bundleIDs.isEmpty else {
            return ASCAppsLookupReport(bundleIDs: [], apps: [], findings: ["No bundle identifiers were provided."])
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("v1/apps"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "filter[bundleId]", value: bundleIDs.joined(separator: ",")),
            URLQueryItem(name: "limit", value: "200")
        ]
        guard let url = components.url else {
            throw AscendKitError.invalidState("Failed to construct ASC apps lookup URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataWithRetry(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AscendKitError.invalidState("ASC apps lookup did not return an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AscendKitError.invalidState("ASC apps lookup failed with HTTP \(http.statusCode): \(String(decoding: data.prefix(512), as: UTF8.self))")
        }

        let decoded = try JSONDecoder().decode(AppsResponse.self, from: data)
        let apps = decoded.data.map { app in
            ASCObservedApp(
                id: app.id,
                name: app.attributes.name,
                bundleID: app.attributes.bundleId,
                sku: app.attributes.sku,
                primaryLocale: app.attributes.primaryLocale
            )
        }
        let foundBundleIDs = Set(apps.compactMap(\.bundleID))
        let findings = bundleIDs.filter { !foundBundleIDs.contains($0) }.map {
            "No App Store Connect app matched bundle identifier \($0)."
        }
        return ASCAppsLookupReport(bundleIDs: bundleIDs, apps: apps, findings: findings)
    }

    public func observeMetadata(appID: String, versionString: String?, platform: ApplePlatform? = nil, token: String) async throws -> MetadataObservedState {
        let appInfos = try await getList(
            path: "v1/apps/\(appID)/appInfos",
            query: ["limit": "10"],
            token: token,
            as: AppInfoResource.self
        )
        guard let appInfo = appInfos.first else {
            return MetadataObservedState(source: "app-store-connect-api", metadataByLocale: [:])
        }

        let appInfoLocalizations = try await getList(
            path: "v1/appInfos/\(appInfo.id)/appInfoLocalizations",
            query: ["limit": "200"],
            token: token,
            as: AppInfoLocalizationResource.self
        )
        var resourceIDsByLocale: [String: MetadataLocalizationResourceIDs] = [:]
        var metadataByLocale: [String: AppMetadata] = Dictionary(uniqueKeysWithValues: appInfoLocalizations.compactMap { resource in
            guard let locale = resource.attributes.locale else { return nil }
            resourceIDsByLocale[locale, default: MetadataLocalizationResourceIDs()].appInfoLocalizationID = resource.id
            return (
                locale,
                AppMetadata(
                    locale: locale,
                    name: resource.attributes.name ?? "",
                    subtitle: resource.attributes.subtitle,
                    description: "",
                    privacyPolicyURL: resource.attributes.privacyPolicyUrl
                )
            )
        })

        var versionQuery = ["limit": "200"]
        if let versionString, !versionString.isEmpty {
            versionQuery["filter[versionString]"] = versionString
        }
        var versions = try await getList(
            path: "v1/apps/\(appID)/appStoreVersions",
            query: versionQuery,
            token: token,
            as: AppStoreVersionResource.self
        )
        if versions.isEmpty, versionString != nil {
            versions = try await getList(
                path: "v1/apps/\(appID)/appStoreVersions",
                query: ["limit": "200"],
                token: token,
                as: AppStoreVersionResource.self
            )
        }
        let selectedVersion = selectVersion(from: versions, versionString: versionString, platform: platform)
        var screenshotSetsByLocale: [String: [ObservedScreenshotSet]] = [:]
        if let version = selectedVersion {
            let versionLocalizations = try await getList(
                path: "v1/appStoreVersions/\(version.id)/appStoreVersionLocalizations",
                query: ["limit": "200"],
                token: token,
                as: AppStoreVersionLocalizationResource.self
            )
            for resource in versionLocalizations {
                guard let locale = resource.attributes.locale else { continue }
                let existing = metadataByLocale[locale]
                resourceIDsByLocale[locale, default: MetadataLocalizationResourceIDs()].appStoreVersionLocalizationID = resource.id
                metadataByLocale[locale] = AppMetadata(
                    locale: locale,
                    name: existing?.name ?? "",
                    subtitle: existing?.subtitle,
                    promotionalText: resource.attributes.promotionalText,
                    description: resource.attributes.description ?? "",
                    releaseNotes: resource.attributes.whatsNew,
                    keywords: (resource.attributes.keywords ?? "")
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty },
                    supportURL: resource.attributes.supportUrl,
                    marketingURL: resource.attributes.marketingUrl,
                    privacyPolicyURL: existing?.privacyPolicyURL
                )
                screenshotSetsByLocale[locale] = try await observeScreenshotSets(
                    appStoreVersionLocalizationID: resource.id,
                    token: token
                )
            }
        }

        return MetadataObservedState(
            source: "app-store-connect-api",
            appInfoID: appInfo.id,
            appStoreVersionID: selectedVersion?.id,
            appStoreVersionPlatform: selectedVersion?.attributes.platform,
            metadataByLocale: metadataByLocale,
            resourceIDsByLocale: resourceIDsByLocale,
            screenshotSetsByLocale: screenshotSetsByLocale.isEmpty ? nil : screenshotSetsByLocale
        )
    }

    public func applyMetadataRequests(_ requestPlan: ASCMetadataRequestPlan, token: String) async throws -> ASCMetadataApplyResult {
        guard !requestPlan.requests.isEmpty else {
            return ASCMetadataApplyResult(applied: false, findings: ["No ASC metadata requests were planned."])
        }

        var responses: [ASCMetadataApplyResponse] = []
        for plannedRequest in requestPlan.requests {
            let payload = try makeJSONAPIPayload(for: plannedRequest)
            var request = URLRequest(url: baseURL.appendingPathComponent(String(plannedRequest.path.dropFirst())))
            request.httpMethod = plannedRequest.method
            request.httpBody = payload
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await dataWithRetry(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AscendKitError.invalidState("ASC metadata request did not return an HTTP response for \(plannedRequest.id).")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AscendKitError.invalidState("ASC metadata request failed for \(plannedRequest.id) with HTTP \(http.statusCode): \(String(decoding: data.prefix(512), as: UTF8.self))")
            }
            let responseID = try? JSONDecoder().decode(ResourceResponse.self, from: data).data.id
            responses.append(ASCMetadataApplyResponse(
                id: plannedRequest.id,
                method: plannedRequest.method,
                path: plannedRequest.path,
                statusCode: http.statusCode,
                responseResourceID: responseID
            ))
        }

        return ASCMetadataApplyResult(applied: true, responses: responses, findings: requestPlan.findings)
    }

    public func lookupBuilds(
        appID: String,
        version: String?,
        buildNumber: String?,
        token: String
    ) async throws -> BuildCandidatesReport {
        let query = ["limit": "200"]
        let response = try await getListResponse(
            path: "v1/apps/\(appID)/builds",
            query: query,
            token: token,
            as: BuildResource.self,
            includedAs: IncludedResource.self
        )
        let preReleaseVersions = Dictionary(uniqueKeysWithValues: response.included.compactMap { resource -> (String, String)? in
            guard resource.type == "preReleaseVersions",
                  let version = resource.attributes?.version else {
                return nil
            }
            return (resource.id, version)
        })
        let preReleasePlatforms = Dictionary(uniqueKeysWithValues: response.included.compactMap { resource -> (String, String)? in
            guard resource.type == "preReleaseVersions",
                  let platform = resource.attributes?.platform else {
                return nil
            }
            return (resource.id, platform)
        })
        let candidates = response.data.map { build in
            let preReleaseID = build.relationships?.preReleaseVersion?.data?.id
            return BuildCandidate(
                id: build.id,
                version: preReleaseID.flatMap { preReleaseVersions[$0] } ?? version ?? "",
                buildNumber: build.attributes.version ?? "",
                processingState: build.attributes.processingState ?? "unknown",
                platform: preReleaseID.flatMap { preReleasePlatforms[$0] } ?? build.attributes.platform
            )
        }
        return BuildCandidatesReport(source: "app-store-connect-api", candidates: candidates)
    }

    public func setFreeAppPricing(
        appID: String,
        baseTerritory: String = "USA",
        confirmRemoteMutation: Bool,
        token: String
    ) async throws -> ASCAppPricingResult {
        let pricePoints = try await getList(
            path: "v1/apps/\(appID)/appPricePoints",
            query: [
                "filter[territory]": baseTerritory,
                "limit": "200"
            ],
            token: token,
            as: AppPricePointResource.self
        )
        guard let freePricePoint = pricePoints.first(where: { $0.attributes.customerPrice == "0.0" || $0.attributes.customerPrice == "0" }) else {
            throw AscendKitError.invalidState("No free app price point was found for territory \(baseTerritory).")
        }

        guard confirmRemoteMutation else {
            return ASCAppPricingResult(
                executed: false,
                appID: appID,
                baseTerritory: baseTerritory,
                pricePointID: freePricePoint.id,
                findings: [
                    "Free pricing request was planned but not executed. Re-run with --confirm-remote-mutation to create the App Store Connect price schedule."
                ]
            )
        }

        let localPriceID = "${price1}"
        let response = try await sendJSONAPIRequest(
            id: "app-pricing.set-free",
            method: "POST",
            path: "/v1/appPriceSchedules",
            payload: [
                "data": [
                    "type": "appPriceSchedules",
                    "relationships": [
                        "app": [
                            "data": [
                                "type": "apps",
                                "id": appID
                            ]
                        ],
                        "baseTerritory": [
                            "data": [
                                "type": "territories",
                                "id": baseTerritory
                            ]
                        ],
                        "manualPrices": [
                            "data": [
                                [
                                    "type": "appPrices",
                                    "id": localPriceID
                                ]
                            ]
                        ]
                    ]
                ],
                "included": [
                    [
                        "type": "appPrices",
                        "id": localPriceID,
                        "attributes": [
                            "startDate": NSNull()
                        ],
                        "relationships": [
                            "appPricePoint": [
                                "data": [
                                    "type": "appPricePoints",
                                    "id": freePricePoint.id
                                ]
                            ]
                        ]
                    ]
                ]
            ],
            token: token
        )

        return ASCAppPricingResult(
            executed: true,
            appID: appID,
            baseTerritory: baseTerritory,
            pricePointID: freePricePoint.id,
            priceScheduleID: response.resourceID,
            responses: [response],
            findings: ["Free pricing was set through the official App Store Connect appPriceSchedules API."]
        )
    }

    public func executeScreenshotUpload(
        plan: ScreenshotUploadPlan,
        confirmRemoteMutation: Bool,
        token: String
    ) async throws -> ScreenshotUploadExecutionResult {
        guard confirmRemoteMutation else {
            return ScreenshotUploadExecutionResult(
                executed: false,
                findings: ["Missing --confirm-remote-mutation. No screenshot upload request was executed."]
            )
        }
        guard plan.findings.isEmpty else {
            return ScreenshotUploadExecutionResult(
                executed: false,
                findings: plan.findings + ["Screenshot upload plan has findings. Resolve them before executing remote upload."]
            )
        }
        guard !plan.items.isEmpty else {
            return ScreenshotUploadExecutionResult(
                executed: false,
                findings: ["Screenshot upload plan has no items."]
            )
        }

        var uploadedItems: [ScreenshotUploadExecutionItem] = []
        var deletedScreenshots: [ScreenshotRemoteDeletion] = []
        var failedItems: [ScreenshotUploadFailure] = []
        var setIDs: [String: String] = [:]
        let deletions = plan.replaceExistingRemoteScreenshots == true
            ? uniqueDeletions(plan.remoteScreenshotsToDelete ?? [])
            : []

        for deletion in deletions {
            do {
                _ = try await deleteAppScreenshot(screenshotID: deletion.appScreenshotID, token: token)
                deletedScreenshots.append(deletion)
            } catch {
                failedItems.append(ScreenshotUploadFailure(
                    phase: "delete",
                    appScreenshotID: deletion.appScreenshotID,
                    fileName: deletion.fileName,
                    message: String(describing: error)
                ))
            }
        }

        for item in plan.items {
            do {
                let fileURL = URL(fileURLWithPath: item.sourcePath)
                let data = try Data(contentsOf: fileURL)
                let checksum = Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined()
                let setKey = "\(item.appStoreVersionLocalizationID)|\(item.displayType)"
                let setID: String
                if let cached = setIDs[setKey] {
                    setID = cached
                } else {
                    setID = try await findOrCreateScreenshotSet(
                        appStoreVersionLocalizationID: item.appStoreVersionLocalizationID,
                        displayType: item.displayType,
                        token: token
                    )
                    setIDs[setKey] = setID
                }

                let reservation = try await createAppScreenshotReservation(
                    appScreenshotSetID: setID,
                    fileName: item.fileName,
                    fileSize: data.count,
                    token: token
                )
                try await uploadAssetParts(
                    uploadOperations: reservation.uploadOperations,
                    data: data
                )
                let commitResponse = try await commitAppScreenshot(
                    screenshotID: reservation.id,
                    checksum: checksum,
                    token: token
                )
                let deliveryState = try await pollAppScreenshotDeliveryState(
                    screenshotID: reservation.id,
                    token: token
                )
                uploadedItems.append(ScreenshotUploadExecutionItem(
                    planItemID: item.id,
                    appScreenshotSetID: setID,
                    appScreenshotID: reservation.id,
                    fileName: item.fileName,
                    checksum: checksum,
                    assetDeliveryState: deliveryState.state,
                    assetDeliveryPollAttempts: deliveryState.attempts,
                    responses: [
                        reservation.response,
                        commitResponse
                    ]
                ))
            } catch {
                failedItems.append(ScreenshotUploadFailure(
                    phase: "upload",
                    planItemID: item.id,
                    fileName: item.fileName,
                    message: String(describing: error)
                ))
            }
        }

        let executed = !uploadedItems.isEmpty || !deletedScreenshots.isEmpty || !failedItems.isEmpty
        var findings = [
            "Screenshot upload executed through the official App Store Connect screenshot asset API."
        ]
        if !deletedScreenshots.isEmpty {
            findings.append("Deleted \(deletedScreenshots.count) existing remote screenshot(s) before upload.")
        }
        if !failedItems.isEmpty {
            findings.append("Screenshot upload completed with \(failedItems.count) failure(s); inspect failedItems before retrying.")
        }

        return ScreenshotUploadExecutionResult(
            executed: executed,
            uploadedCount: uploadedItems.count,
            items: uploadedItems,
            findings: findings,
            deletedScreenshots: deletedScreenshots,
            failedItems: failedItems
        )
    }

    private func uniqueDeletions(_ deletions: [ScreenshotRemoteDeletion]) -> [ScreenshotRemoteDeletion] {
        var seen = Set<String>()
        var unique: [ScreenshotRemoteDeletion] = []
        for deletion in deletions.sorted(by: { $0.appScreenshotID < $1.appScreenshotID }) {
            guard !deletion.appScreenshotID.isEmpty, !seen.contains(deletion.appScreenshotID) else {
                continue
            }
            seen.insert(deletion.appScreenshotID)
            unique.append(deletion)
        }
        return unique
    }

    public func executeReviewSubmission(
        appID: String,
        appInfoID: String?,
        appStoreVersionID: String,
        buildID: String,
        platform: ApplePlatform,
        reviewInfo: ReviewInfo,
        token: String
    ) async throws -> ReviewSubmissionExecutionResult {
        let platformValue = ascPlatformValue(for: platform)
        var responses: [ReviewSubmissionExecutionResponse] = []

        let buildResponse = try await sendJSONAPIRequest(
            id: "app-store-version.attach-build",
            method: "PATCH",
            path: "/v1/appStoreVersions/\(appStoreVersionID)",
            payload: [
                "data": [
                    "type": "appStoreVersions",
                    "id": appStoreVersionID,
                    "relationships": [
                        "build": [
                            "data": [
                                "type": "builds",
                                "id": buildID
                            ]
                        ]
                    ]
                ]
            ],
            token: token
        )
        responses.append(buildResponse)

        let buildEncryptionResponse = try await sendJSONAPIRequest(
            id: "build.export-compliance.update",
            method: "PATCH",
            path: "/v1/builds/\(buildID)",
            payload: [
                "data": [
                    "type": "builds",
                    "id": buildID,
                    "attributes": [
                        "usesNonExemptEncryption": false
                    ]
                ]
            ],
            token: token
        )
        responses.append(buildEncryptionResponse)

        let appInfoResponse = try await updateAppInfo(appInfoID: appInfoID, token: token)
        if let appInfoResponse {
            responses.append(appInfoResponse)
        }

        let appResponse = try await sendJSONAPIRequest(
            id: "app.content-rights.update",
            method: "PATCH",
            path: "/v1/apps/\(appID)",
            payload: [
                "data": [
                    "type": "apps",
                    "id": appID,
                    "attributes": [
                        "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"
                    ]
                ]
            ],
            token: token
        )
        responses.append(appResponse)

        do {
            responses.append(contentsOf: try await publishDataNotCollectedPrivacyAnswers(appID: appID, token: token))
        } catch AscendKitError.invalidState(let message) where message.contains("HTTP 401") || message.contains("NOT_AUTHORIZED") {
            responses.append(ReviewSubmissionExecutionResponse(
                id: "app-privacy.data-not-collected.skip-iris-unauthorized",
                method: "SKIP",
                path: "/iris/v1/apps/\(appID)/dataUsages",
                statusCode: 401
            ))
        }

        let copyrightResponse = try await sendJSONAPIRequest(
            id: "app-store-version.copyright.update",
            method: "PATCH",
            path: "/v1/appStoreVersions/\(appStoreVersionID)",
            payload: [
                "data": [
                    "type": "appStoreVersions",
                    "id": appStoreVersionID,
                    "attributes": [
                        "copyright": copyrightText(reviewInfo: reviewInfo)
                    ]
                ]
            ],
            token: token
        )
        responses.append(copyrightResponse)

        let reviewDetailID = try await upsertReviewDetail(
            appStoreVersionID: appStoreVersionID,
            reviewInfo: reviewInfo,
            token: token,
            responses: &responses
        )

        let existingAgeRatingDeclarationID: String?
        if let appInfoID {
            existingAgeRatingDeclarationID = try await getRelationshipResourceID(
                path: "v1/appInfos/\(appInfoID)/relationships/ageRatingDeclaration",
                token: token
            )
        } else {
            existingAgeRatingDeclarationID = nil
        }
        let ageRatingResponse: ReviewSubmissionExecutionResponse
        if let ageRatingDeclarationID = existingAgeRatingDeclarationID {
            ageRatingResponse = try await sendJSONAPIRequest(
                id: "age-rating-declaration.update",
                method: "PATCH",
                path: "/v1/ageRatingDeclarations/\(ageRatingDeclarationID)",
                payload: [
                    "data": [
                        "type": "ageRatingDeclarations",
                        "id": ageRatingDeclarationID,
                        "attributes": defaultAgeRatingDeclarationAttributes()
                    ]
                ],
                token: token
            )
        } else {
            ageRatingResponse = try await sendJSONAPIRequest(
                id: "age-rating-declaration.create",
                method: "POST",
                path: "/v1/ageRatingDeclarations",
                payload: [
                    "data": [
                        "type": "ageRatingDeclarations",
                        "attributes": defaultAgeRatingDeclarationAttributes(),
                        "relationships": [
                            "appStoreVersion": [
                                "data": [
                                    "type": "appStoreVersions",
                                    "id": appStoreVersionID
                                ]
                            ]
                        ]
                    ]
                ],
                token: token
            )
        }
        responses.append(ageRatingResponse)

        let reviewSubmissionID: String
        if let reusableReviewSubmissionID = try await findReusableReviewSubmissionID(
            appID: appID,
            platform: platformValue,
            token: token
        ) {
            reviewSubmissionID = reusableReviewSubmissionID
            responses.append(ReviewSubmissionExecutionResponse(
                id: "review-submission.reuse",
                method: "GET",
                path: "/v1/apps/\(appID)/reviewSubmissions",
                statusCode: 200,
                resourceID: reusableReviewSubmissionID
            ))
        } else {
            let reviewSubmissionResponse = try await sendJSONAPIRequest(
                id: "review-submission.create",
                method: "POST",
                path: "/v1/reviewSubmissions",
                payload: [
                    "data": [
                        "type": "reviewSubmissions",
                        "attributes": [
                            "platform": platformValue
                        ],
                        "relationships": [
                            "app": [
                                "data": [
                                    "type": "apps",
                                    "id": appID
                                ]
                            ]
                        ]
                    ]
                ],
                token: token
            )
            responses.append(reviewSubmissionResponse)
            guard let createdReviewSubmissionID = reviewSubmissionResponse.resourceID else {
                throw AscendKitError.invalidState("ASC did not return a review submission id.")
            }
            reviewSubmissionID = createdReviewSubmissionID
        }

        let itemResponse = try await sendJSONAPIRequest(
            id: "review-submission-item.create",
            method: "POST",
            path: "/v1/reviewSubmissionItems",
            payload: [
                "data": [
                    "type": "reviewSubmissionItems",
                    "relationships": [
                        "appStoreVersion": [
                            "data": [
                                "type": "appStoreVersions",
                                "id": appStoreVersionID
                            ]
                        ],
                        "reviewSubmission": [
                            "data": [
                                "type": "reviewSubmissions",
                                "id": reviewSubmissionID
                            ]
                        ]
                    ]
                ]
            ],
            token: token
        )
        responses.append(itemResponse)

        let submitResponse = try await sendJSONAPIRequest(
            id: "review-submission.submit",
            method: "PATCH",
            path: "/v1/reviewSubmissions/\(reviewSubmissionID)",
            payload: [
                "data": [
                    "type": "reviewSubmissions",
                    "id": reviewSubmissionID,
                    "attributes": [
                        "submitted": true
                    ]
                ]
            ],
            token: token
        )
        responses.append(submitResponse)

        return ReviewSubmissionExecutionResult(
            executed: true,
            appStoreVersionID: appStoreVersionID,
            buildID: buildID,
            appStoreReviewDetailID: reviewDetailID,
            reviewSubmissionID: reviewSubmissionID,
            reviewSubmissionItemID: itemResponse.resourceID,
            submitted: true,
            responses: responses,
            findings: ["Remote review submission execution was explicitly confirmed and executed."]
        )
    }

    private func getList<Resource: Decodable>(
        path: String,
        query: [String: String],
        token: String,
        as type: Resource.Type,
        requestBaseURL: URL? = nil
    ) async throws -> [Resource] {
        let rootURL = requestBaseURL ?? baseURL
        var components = URLComponents(url: rootURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            throw AscendKitError.invalidState("Failed to construct ASC URL for \(path).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataWithRetry(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AscendKitError.invalidState("ASC request did not return an HTTP response for \(path).")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AscendKitError.invalidState("ASC request failed for \(path) with HTTP \(http.statusCode): \(String(decoding: data.prefix(512), as: UTF8.self))")
        }
        return try JSONDecoder().decode(ListResponse<Resource>.self, from: data).data
    }

    private func getListResponse<Resource: Decodable, Included: Decodable>(
        path: String,
        query: [String: String],
        token: String,
        as type: Resource.Type,
        includedAs includedType: Included.Type
    ) async throws -> ListResponseWithIncluded<Resource, Included> {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            throw AscendKitError.invalidState("Failed to construct ASC URL for \(path).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataWithRetry(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AscendKitError.invalidState("ASC request did not return an HTTP response for \(path).")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AscendKitError.invalidState("ASC request failed for \(path) with HTTP \(http.statusCode): \(String(decoding: data.prefix(512), as: UTF8.self))")
        }
        return try JSONDecoder().decode(ListResponseWithIncluded<Resource, Included>.self, from: data)
    }

    private func getResource<Resource: Decodable>(
        path: String,
        token: String,
        as type: Resource.Type
    ) async throws -> Resource {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataWithRetry(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AscendKitError.invalidState("ASC request did not return an HTTP response for \(path).")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AscendKitError.invalidState("ASC request failed for \(path) with HTTP \(http.statusCode): \(String(decoding: data.prefix(512), as: UTF8.self))")
        }
        return try JSONDecoder().decode(SingleResponse<Resource>.self, from: data).data
    }

    private func getRelationshipResourceID(path: String, token: String, requestBaseURL: URL? = nil) async throws -> String? {
        let rootURL = requestBaseURL ?? baseURL
        var request = URLRequest(url: rootURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataWithRetry(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AscendKitError.invalidState("ASC request did not return an HTTP response for \(path).")
        }
        if http.statusCode == 404 {
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AscendKitError.invalidState("ASC request failed for \(path) with HTTP \(http.statusCode): \(String(decoding: data.prefix(512), as: UTF8.self))")
        }
        return try JSONDecoder().decode(OptionalResourceResponse.self, from: data).data?.id
    }

    private func findOrCreateScreenshotSet(
        appStoreVersionLocalizationID: String,
        displayType: String,
        token: String
    ) async throws -> String {
        let existingSets = try await getList(
            path: "v1/appStoreVersionLocalizations/\(appStoreVersionLocalizationID)/appScreenshotSets",
            query: ["limit": "200"],
            token: token,
            as: AppScreenshotSetResource.self
        )
        if let existing = existingSets.first(where: { $0.attributes.screenshotDisplayType == displayType }) {
            return existing.id
        }

        let response = try await sendJSONAPIRequest(
            id: "app-screenshot-set.create",
            method: "POST",
            path: "/v1/appScreenshotSets",
            payload: [
                "data": [
                    "type": "appScreenshotSets",
                    "attributes": [
                        "screenshotDisplayType": displayType
                    ],
                    "relationships": [
                        "appStoreVersionLocalization": [
                            "data": [
                                "type": "appStoreVersionLocalizations",
                                "id": appStoreVersionLocalizationID
                            ]
                        ]
                    ]
                ]
            ],
            token: token
        )
        guard let setID = response.resourceID else {
            throw AscendKitError.invalidState("ASC did not return an appScreenshotSet id.")
        }
        return setID
    }

    private func observeScreenshotSets(
        appStoreVersionLocalizationID: String,
        token: String
    ) async throws -> [ObservedScreenshotSet] {
        let existingSets = try await getList(
            path: "v1/appStoreVersionLocalizations/\(appStoreVersionLocalizationID)/appScreenshotSets",
            query: ["limit": "200"],
            token: token,
            as: AppScreenshotSetResource.self
        )

        var observedSets: [ObservedScreenshotSet] = []
        for set in existingSets {
            let screenshots = try await getList(
                path: "v1/appScreenshotSets/\(set.id)/appScreenshots",
                query: ["limit": "200"],
                token: token,
                as: AppScreenshotResource.self
            )
            observedSets.append(ObservedScreenshotSet(
                id: set.id,
                displayType: set.attributes.screenshotDisplayType,
                screenshots: screenshots.map {
                    ObservedScreenshot(
                        id: $0.id,
                        fileName: $0.attributes.fileName,
                        assetDeliveryState: $0.attributes.assetDeliveryState?.state
                    )
                }
            ))
        }
        return observedSets.sorted { $0.displayType < $1.displayType }
    }

    private func createAppScreenshotReservation(
        appScreenshotSetID: String,
        fileName: String,
        fileSize: Int,
        token: String
    ) async throws -> AppScreenshotReservation {
        let payload: [String: Any] = [
            "data": [
                "type": "appScreenshots",
                "attributes": [
                    "fileName": fileName,
                    "fileSize": fileSize
                ],
                "relationships": [
                    "appScreenshotSet": [
                        "data": [
                            "type": "appScreenshotSets",
                            "id": appScreenshotSetID
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/appScreenshots"))
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await dataWithRetry(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AscendKitError.invalidState("ASC app-screenshot.create request did not return an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AscendKitError.invalidState("ASC app-screenshot.create failed with HTTP \(http.statusCode): \(String(decoding: responseData.prefix(8192), as: UTF8.self))")
        }
        let decoded = try JSONDecoder().decode(AppScreenshotResponse.self, from: responseData)
        return AppScreenshotReservation(
            id: decoded.data.id,
            uploadOperations: decoded.data.attributes.uploadOperations ?? [],
            response: ReviewSubmissionExecutionResponse(
                id: "app-screenshot.create",
                method: "POST",
                path: "/v1/appScreenshots",
                statusCode: http.statusCode,
                resourceID: decoded.data.id
            )
        )
    }

    private func uploadAssetParts(uploadOperations: [UploadOperation], data: Data) async throws {
        guard !uploadOperations.isEmpty else {
            throw AscendKitError.invalidState("ASC app screenshot reservation did not include upload operations.")
        }

        for operation in uploadOperations {
            guard let url = URL(string: operation.url) else {
                throw AscendKitError.invalidState("ASC upload operation has an invalid URL: \(operation.url)")
            }
            let lowerBound = operation.offset ?? 0
            let length = operation.length ?? (data.count - lowerBound)
            guard lowerBound >= 0, length >= 0, lowerBound + length <= data.count else {
                throw AscendKitError.invalidState("ASC upload operation range is outside local screenshot data.")
            }

            var request = URLRequest(url: url)
            request.httpMethod = operation.method
            for header in operation.requestHeaders {
                request.setValue(header.value, forHTTPHeaderField: header.name)
            }
            request.httpBody = data.subdata(in: lowerBound..<(lowerBound + length))

            let (responseData, response) = try await dataWithRetry(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AscendKitError.invalidState("ASC upload operation did not return an HTTP response.")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AscendKitError.invalidState("ASC upload operation failed with HTTP \(http.statusCode): \(String(decoding: responseData.prefix(1024), as: UTF8.self))")
            }
        }
    }

    private func commitAppScreenshot(
        screenshotID: String,
        checksum: String,
        token: String
    ) async throws -> ReviewSubmissionExecutionResponse {
        try await sendJSONAPIRequest(
            id: "app-screenshot.commit",
            method: "PATCH",
            path: "/v1/appScreenshots/\(screenshotID)",
            payload: [
                "data": [
                    "type": "appScreenshots",
                    "id": screenshotID,
                    "attributes": [
                        "uploaded": true,
                        "sourceFileChecksum": checksum
                    ]
                ]
            ],
            token: token
        )
    }

    private func deleteAppScreenshot(
        screenshotID: String,
        token: String
    ) async throws -> ReviewSubmissionExecutionResponse {
        try await sendEmptyRequest(
            id: "app-screenshot.delete",
            method: "DELETE",
            path: "/v1/appScreenshots/\(screenshotID)",
            token: token
        )
    }

    private func pollAppScreenshotDeliveryState(
        screenshotID: String,
        token: String
    ) async throws -> (state: String?, attempts: Int) {
        let maxAttempts = 6
        for attempt in 1...maxAttempts {
            let resource = try await getResource(
                path: "v1/appScreenshots/\(screenshotID)",
                token: token,
                as: AppScreenshotResource.self
            )
            let state = resource.attributes.assetDeliveryState?.state
            if isTerminalAssetDeliveryState(state) || attempt == maxAttempts {
                return (state, attempt)
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        return (nil, maxAttempts)
    }

    private func isTerminalAssetDeliveryState(_ state: String?) -> Bool {
        guard let state = state?.uppercased() else {
            return false
        }
        return state == "COMPLETE" || state == "FAILED"
    }

    private func upsertReviewDetail(
        appStoreVersionID: String,
        reviewInfo: ReviewInfo,
        token: String,
        responses: inout [ReviewSubmissionExecutionResponse]
    ) async throws -> String? {
        let existingID = try await getRelationshipResourceID(
            path: "v1/appStoreVersions/\(appStoreVersionID)/appStoreReviewDetail",
            token: token
        )
        let attributes = reviewDetailAttributes(reviewInfo)
        if let existingID {
            let response = try await sendJSONAPIRequest(
                id: "app-store-review-detail.update",
                method: "PATCH",
                path: "/v1/appStoreReviewDetails/\(existingID)",
                payload: [
                    "data": [
                        "type": "appStoreReviewDetails",
                        "id": existingID,
                        "attributes": attributes
                    ]
                ],
                token: token
            )
            responses.append(response)
            return existingID
        }

        let response = try await sendJSONAPIRequest(
            id: "app-store-review-detail.create",
            method: "POST",
            path: "/v1/appStoreReviewDetails",
            payload: [
                "data": [
                    "type": "appStoreReviewDetails",
                    "attributes": attributes,
                    "relationships": [
                        "appStoreVersion": [
                            "data": [
                                "type": "appStoreVersions",
                                "id": appStoreVersionID
                            ]
                        ]
                    ]
                ]
            ],
            token: token
        )
        responses.append(response)
        return response.resourceID
    }

    private func reviewDetailAttributes(_ reviewInfo: ReviewInfo) -> [String: Any] {
        var attributes: [String: Any] = [
            "contactFirstName": reviewInfo.contact.firstName,
            "contactLastName": reviewInfo.contact.lastName,
            "contactEmail": reviewInfo.contact.email,
            "contactPhone": reviewInfo.contact.phone,
            "demoAccountRequired": reviewInfo.access.requiresLogin,
            "notes": reviewInfo.notes
        ]
        if reviewInfo.access.requiresLogin {
            attributes["demoAccountName"] = reviewInfo.access.credentialReference?.redactedDescription ?? ""
            attributes["demoAccountPassword"] = ""
        }
        return attributes
    }

    private func copyrightText(reviewInfo: ReviewInfo, date: Date = Date()) -> String {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        let holder = [
            reviewInfo.contact.firstName,
            reviewInfo.contact.lastName
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if holder.isEmpty {
            return "Copyright \(year)"
        }
        return "Copyright \(year) \(holder)"
    }

    private func updateAppInfo(appInfoID: String?, token: String) async throws -> ReviewSubmissionExecutionResponse? {
        guard let appInfoID else {
            return nil
        }
        return try await sendJSONAPIRequest(
            id: "app-info.primary-category.update",
            method: "PATCH",
            path: "/v1/appInfos/\(appInfoID)",
            payload: [
                "data": [
                    "type": "appInfos",
                    "id": appInfoID,
                    "relationships": [
                        "primaryCategory": [
                            "data": [
                                "type": "appCategories",
                                "id": "LIFESTYLE"
                            ]
                        ]
                    ]
                ]
            ],
            token: token
        )
    }

    public func publishDataNotCollectedPrivacyAnswers(appID: String, token: String) async throws -> [ReviewSubmissionExecutionResponse] {
        let existingUsages = try await getList(
            path: "v1/apps/\(appID)/dataUsages",
            query: ["limit": "500"],
            token: token,
            as: ResourceIdentifier.self,
            requestBaseURL: irisBaseURL
        )
        var responses: [ReviewSubmissionExecutionResponse] = []
        for usage in existingUsages {
            responses.append(try await sendEmptyRequest(
                id: "app-privacy.data-usage.delete",
                method: "DELETE",
                path: "/v1/appDataUsages/\(usage.id)",
                token: token,
                requestBaseURL: irisBaseURL
            ))
        }

        responses.append(try await createAppDataUsage(
            appID: appID,
            category: nil,
            purpose: nil,
            dataProtection: "DATA_NOT_COLLECTED",
            token: token,
            requestBaseURL: irisBaseURL
        ))

        let publishStateID = try await getRelationshipResourceID(
            path: "v1/apps/\(appID)/dataUsagePublishState",
            token: token,
            requestBaseURL: irisBaseURL
        )
        if let publishStateID {
            responses.append(try await sendJSONAPIRequest(
                id: "app-privacy.publish",
                method: "PATCH",
                path: "/v1/appDataUsagesPublishState/\(publishStateID)",
                payload: [
                    "data": [
                        "type": "appDataUsagesPublishState",
                        "id": publishStateID,
                        "attributes": [
                            "published": true
                        ]
                    ]
                ],
                token: token,
                requestBaseURL: irisBaseURL
            ))
        }
        return responses
    }

    private func createAppDataUsage(
        appID: String,
        category: String?,
        purpose: String?,
        dataProtection: String,
        token: String,
        requestBaseURL: URL? = nil
    ) async throws -> ReviewSubmissionExecutionResponse {
        var relationships: [String: Any] = [
            "app": [
                "data": [
                    "type": "apps",
                    "id": appID
                ]
            ],
            "dataProtection": [
                "data": [
                    "type": "appDataUsageDataProtections",
                    "id": dataProtection
                ]
            ]
        ]
        if let category {
            relationships["category"] = [
                "data": [
                    "type": "appDataUsageCategories",
                    "id": category
                ]
            ]
        }
        if let purpose {
            relationships["purpose"] = [
                "data": [
                    "type": "appDataUsagePurposes",
                    "id": purpose
                ]
            ]
        }
        return try await sendJSONAPIRequest(
            id: "app-privacy.data-usage.create.\(dataProtection)",
            method: "POST",
            path: "/v1/appDataUsages",
            payload: [
                "data": [
                    "type": "appDataUsages",
                    "relationships": relationships
                ]
            ],
            token: token,
            requestBaseURL: requestBaseURL
        )
    }

    private func findReusableReviewSubmissionID(appID: String, platform: String, token: String) async throws -> String? {
        let submissions = try await getList(
            path: "v1/apps/\(appID)/reviewSubmissions",
            query: ["limit": "200"],
            token: token,
            as: ReviewSubmissionResource.self
        )
        return submissions.first { submission in
            submission.attributes.platform == platform && submission.attributes.submitted != true
        }?.id
    }

    private func defaultAgeRatingDeclarationAttributes() -> [String: Any] {
        [
            "advertising": false,
            "ageAssurance": false,
            "alcoholTobaccoOrDrugUseOrReferences": "NONE",
            "contests": "NONE",
            "gambling": false,
            "gamblingSimulated": "NONE",
            "gunsOrOtherWeapons": "NONE",
            "healthOrWellnessTopics": false,
            "horrorOrFearThemes": "NONE",
            "kidsAgeBand": NSNull(),
            "lootBox": false,
            "matureOrSuggestiveThemes": "NONE",
            "medicalOrTreatmentInformation": "NONE",
            "messagingAndChat": false,
            "parentalControls": false,
            "profanityOrCrudeHumor": "NONE",
            "sexualContentGraphicAndNudity": "NONE",
            "sexualContentOrNudity": "NONE",
            "unrestrictedWebAccess": false,
            "userGeneratedContent": false,
            "violenceCartoonOrFantasy": "NONE",
            "violenceRealistic": "NONE",
            "violenceRealisticProlongedGraphicOrSadistic": "NONE"
        ]
    }

    private func sendJSONAPIRequest(
        id: String,
        method: String,
        path: String,
        payload: [String: Any],
        token: String,
        requestBaseURL: URL? = nil
    ) async throws -> ReviewSubmissionExecutionResponse {
        let rootURL = requestBaseURL ?? baseURL
        var request = URLRequest(url: rootURL.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await dataWithRetry(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AscendKitError.invalidState("ASC \(id) request did not return an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AscendKitError.invalidState("ASC \(id) failed with HTTP \(http.statusCode): \(String(decoding: data.prefix(8192), as: UTF8.self))")
        }
        let responseID = try? JSONDecoder().decode(ResourceResponse.self, from: data).data.id
        return ReviewSubmissionExecutionResponse(
            id: id,
            method: method,
            path: path,
            statusCode: http.statusCode,
            resourceID: responseID
        )
    }

    private func sendEmptyRequest(
        id: String,
        method: String,
        path: String,
        token: String,
        requestBaseURL: URL? = nil
    ) async throws -> ReviewSubmissionExecutionResponse {
        let rootURL = requestBaseURL ?? baseURL
        var request = URLRequest(url: rootURL.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataWithRetry(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AscendKitError.invalidState("ASC \(id) request did not return an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AscendKitError.invalidState("ASC \(id) failed with HTTP \(http.statusCode): \(String(decoding: data.prefix(8192), as: UTF8.self))")
        }
        return ReviewSubmissionExecutionResponse(
            id: id,
            method: method,
            path: path,
            statusCode: http.statusCode
        )
    }

    private func dataWithRetry(for request: URLRequest, maxAttempts: Int = 3) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, shouldRetry(statusCode: http.statusCode), attempt < maxAttempts {
                    try await sleepBeforeRetry(attempt: attempt)
                    continue
                }
                return (data, response)
            } catch {
                lastError = error
                guard attempt < maxAttempts, shouldRetry(error: error) else {
                    throw error
                }
                try await sleepBeforeRetry(attempt: attempt)
            }
        }
        throw lastError ?? AscendKitError.invalidState("Request failed after retry attempts.")
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 429 || (500...599).contains(statusCode)
    }

    private func shouldRetry(error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }
        switch urlError.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    private func sleepBeforeRetry(attempt: Int) async throws {
        let delay = UInt64(250_000_000 * max(1, attempt))
        try await Task.sleep(nanoseconds: delay)
    }

    private func ascPlatformValue(for platform: ApplePlatform) -> String {
        switch platform {
        case .macOS:
            return "MAC_OS"
        case .tvOS:
            return "TV_OS"
        case .watchOS:
            return "WATCH_OS"
        case .visionOS:
            return "VISION_OS"
        case .iOS, .iPadOS, .unknown:
            return "IOS"
        }
    }

    private func selectVersion(from versions: [AppStoreVersionResource], versionString: String?, platform: ApplePlatform?) -> AppStoreVersionResource? {
        let targetPlatform = platform.map(ascPlatformValue)
        if let versionString, let targetPlatform, let match = versions.first(where: {
            $0.attributes.versionString == versionString && $0.attributes.platform == targetPlatform
        }) {
            return match
        }
        if let targetPlatform, let match = versions.first(where: { $0.attributes.platform == targetPlatform }) {
            return match
        }
        if let versionString, let match = versions.first(where: { $0.attributes.versionString == versionString }) {
            return match
        }
        return versions.first
    }

    private func makeJSONAPIPayload(for request: ASCMetadataPlannedRequest) throws -> Data {
        var data: [String: Any] = [
            "type": resourceType(for: request.resourceKind),
            "attributes": request.attributes
        ]
        if request.method == "PATCH" {
            guard let resourceID = request.resourceID else {
                throw AscendKitError.invalidState("Missing ASC resource id for metadata PATCH request \(request.id).")
            }
            data["id"] = resourceID
        }
        if request.method == "POST" {
            guard let parentResourceID = request.parentResourceID,
                  let relationshipName = request.relationshipName else {
                throw AscendKitError.invalidState("Missing ASC parent resource for metadata POST request \(request.id).")
            }
            data["relationships"] = [
                relationshipName: [
                    "data": [
                        "id": parentResourceID,
                        "type": parentResourceType(for: request.resourceKind)
                    ]
                ]
            ]
        }
        return try JSONSerialization.data(withJSONObject: ["data": data], options: [.sortedKeys])
    }

    private func resourceType(for kind: ASCMetadataResourceKind) -> String {
        switch kind {
        case .appInfoLocalization:
            return "appInfoLocalizations"
        case .appStoreVersionLocalization:
            return "appStoreVersionLocalizations"
        }
    }

    private func parentResourceType(for kind: ASCMetadataResourceKind) -> String {
        switch kind {
        case .appInfoLocalization:
            return "appInfos"
        case .appStoreVersionLocalization:
            return "appStoreVersions"
        }
    }

    private struct AppsResponse: Decodable {
        var data: [AppResource]
    }

    private struct AppResource: Decodable {
        var id: String
        var attributes: Attributes
    }

    private struct Attributes: Decodable {
        var name: String?
        var bundleId: String?
        var sku: String?
        var primaryLocale: String?
    }

    private struct ListResponse<Resource: Decodable>: Decodable {
        var data: [Resource]
    }

    private struct SingleResponse<Resource: Decodable>: Decodable {
        var data: Resource
    }

    private struct ListResponseWithIncluded<Resource: Decodable, Included: Decodable>: Decodable {
        var data: [Resource]
        var included: [Included]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.data = try container.decode([Resource].self, forKey: .data)
            self.included = try container.decodeIfPresent([Included].self, forKey: .included) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case data
            case included
        }
    }

    private struct ResourceResponse: Decodable {
        var data: ResourceIdentifier
    }

    private struct OptionalResourceResponse: Decodable {
        var data: ResourceIdentifier?
    }

    private struct ResourceIdentifier: Decodable {
        var id: String
    }

    private struct AppPricePointResource: Decodable {
        var id: String
        var attributes: AppPricePointAttributes
    }

    private struct AppPricePointAttributes: Decodable {
        var customerPrice: String
    }

    private struct AppScreenshotSetResource: Decodable {
        var id: String
        var attributes: AppScreenshotSetAttributes
    }

    private struct AppScreenshotSetAttributes: Decodable {
        var screenshotDisplayType: String
    }

    private struct AppScreenshotReservation {
        var id: String
        var uploadOperations: [UploadOperation]
        var response: ReviewSubmissionExecutionResponse
    }

    private struct AppScreenshotResponse: Decodable {
        var data: AppScreenshotResource
    }

    private struct AppScreenshotResource: Decodable {
        var id: String
        var attributes: AppScreenshotAttributes
    }

    private struct AppScreenshotAttributes: Decodable {
        var fileName: String?
        var uploadOperations: [UploadOperation]?
        var assetDeliveryState: AssetDeliveryState?
    }

    private struct AssetDeliveryState: Decodable {
        var state: String?
    }

    private struct UploadOperation: Decodable {
        var method: String
        var url: String
        var offset: Int?
        var length: Int?
        var requestHeaders: [UploadOperationHeader]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.method = try container.decodeIfPresent(String.self, forKey: .method) ?? "PUT"
            self.url = try container.decode(String.self, forKey: .url)
            self.offset = try container.decodeIfPresent(Int.self, forKey: .offset)
            self.length = try container.decodeIfPresent(Int.self, forKey: .length)
            self.requestHeaders = try container.decodeIfPresent([UploadOperationHeader].self, forKey: .requestHeaders)
                ?? container.decodeIfPresent([UploadOperationHeader].self, forKey: .headers)
                ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case method
            case url
            case offset
            case length
            case requestHeaders
            case headers
        }
    }

    private struct UploadOperationHeader: Decodable {
        var name: String
        var value: String
    }

    private struct AppInfoResource: Decodable {
        var id: String
    }

    private struct AppInfoLocalizationResource: Decodable {
        var id: String
        var attributes: AppInfoLocalizationAttributes
    }

    private struct AppInfoLocalizationAttributes: Decodable {
        var locale: String?
        var name: String?
        var subtitle: String?
        var privacyPolicyUrl: String?
    }

    private struct AppStoreVersionResource: Decodable {
        var id: String
        var attributes: AppStoreVersionAttributes
    }

    private struct ReviewSubmissionResource: Decodable {
        var id: String
        var attributes: ReviewSubmissionAttributes
    }

    private struct ReviewSubmissionAttributes: Decodable {
        var platform: String?
        var submitted: Bool?
    }

    private struct AppStoreVersionAttributes: Decodable {
        var versionString: String?
        var platform: String?
    }

    private struct AppStoreVersionLocalizationResource: Decodable {
        var id: String
        var attributes: AppStoreVersionLocalizationAttributes
    }

    private struct AppStoreVersionLocalizationAttributes: Decodable {
        var locale: String?
        var description: String?
        var keywords: String?
        var marketingUrl: String?
        var promotionalText: String?
        var supportUrl: String?
        var whatsNew: String?
    }

    private struct BuildResource: Decodable {
        var id: String
        var attributes: BuildAttributes
        var relationships: BuildRelationships?
    }

    private struct BuildAttributes: Decodable {
        var version: String?
        var processingState: String?
        var platform: String?
    }

    private struct BuildRelationships: Decodable {
        var preReleaseVersion: RelationshipToOne?
    }

    private struct RelationshipToOne: Decodable {
        var data: ResourceIdentifier?
    }

    private struct IncludedResource: Decodable {
        var id: String
        var type: String
        var attributes: IncludedAttributes?
    }

    private struct IncludedAttributes: Decodable {
        var version: String?
        var platform: String?
    }
}
