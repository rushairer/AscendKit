import Foundation

public struct ASCOperationPlan: Encodable, Sendable {
    public let domain: String
    public let action: String
    public let method: String
    public let path: String
    public let query: [String: String]
    public let accept: String
    public let payload: PPOJSONValue?
    public let sourcePath: String?
    public let requiresSubmissionConfirmation: Bool

    public var mutatesRemote: Bool { method != "GET" || sourcePath != nil }
}

public struct ASCOperationResult: Encodable, Sendable {
    public let plan: ASCOperationPlan
    public let executed: Bool
    public let responses: [PPOJSONValue]
    public let findings: [String]

    public init(plan: ASCOperationPlan, executed: Bool, responses: [PPOJSONValue] = [], findings: [String] = []) {
        self.plan = plan
        self.executed = executed
        self.responses = responses
        self.findings = findings
    }
}

public struct ASCOperationPlanner: Sendable {
    public init() {}

    public static var domains: [String] { routes.keys.sorted() }

    public func requiresAppID(domain: String, action: String) -> Bool {
        guard let route = Self.routes[domain]?.first(where: { $0.action == action }) else { return false }
        return route.idOption == "app-id" || route.body == .reviewCreate
    }

    public static func usage(for domain: String) -> [String] {
        guard let routes = routes[domain] else { return [] }
        return routes.map { route -> String in
            var parts = ["ascendkit asc \(domain) \(route.action) --workspace PATH"]
            for key in route.requiredOptions {
                parts.append(key == "app-id" ? "[--app-id ID]" : usageOption(key))
            }
            for key in route.optionalOptions {
                parts.append("[\(usageOption(key))]")
            }
            if !route.query.isEmpty {
                parts.append("[--query NAME=VALUE ...]")
            }
            if route.method != "GET" || route.body == .upload {
                parts.append("[--confirm-remote-mutation]")
            }
            if route.body == .reviewSubmit {
                parts.append("[--confirm-remote-submission]")
            }
            parts.append("[--json]")
            return parts.joined(separator: " ")
        }
    }

    private static func usageOption(_ key: String) -> String {
        let value: String
        switch key {
        case "file": value = "PATH"
        case "blocked", "shared-location", "dating-and-relationships", "social-media", "social-media-age-restricted":
            value = "true|false"
        case "offer-ids": value = "ID,ID"
        case "plan-type": value = "MONTHLY|UPFRONT"
        case "version-type": value = "IAP|SUBSCRIPTION|GROUP"
        case "category": value = "CREATIVE_ASSETS|APP_SCREENSHOTS_AND_PREVIEWS"
        default: value = key.hasSuffix("-id") ? "ID" : "VALUE"
        }
        return "--\(key) \(value)"
    }

    public func plan(
        domain: String,
        action: String,
        options: [String: String],
        query: [String: String] = [:]
    ) throws -> ASCOperationPlan {
        guard let route = Self.routes[domain]?.first(where: { $0.action == action }) else {
            throw AscendKitError.invalidArguments("Unknown ASC operation \(domain) \(action). Run ascendkit asc \(domain) --help.")
        }
        let allowed = Set(route.requiredOptions + route.optionalOptions)
        if let unexpected = options.keys.filter({ !allowed.contains($0) }).sorted().first {
            throw AscendKitError.invalidArguments("Unexpected option --\(unexpected) for \(domain) \(action).")
        }
        let acceptedQueries = route.query.split(separator: " ").map(String.init)
        if let unexpected = query.keys.filter({ !acceptedQueries.contains($0) }).sorted().first {
            throw AscendKitError.invalidArguments("Unsupported query parameter \(unexpected) for \(domain) \(action).")
        }
        guard query.values.allSatisfy({ !$0.isEmpty }) else {
            throw AscendKitError.invalidArguments("ASC query values must be nonempty.")
        }
        var resolvedQuery = query
        if let required = route.requiredQuery, let key = route.requiredQueryOption {
            guard query[required] == nil else {
                throw AscendKitError.invalidArguments("Use --\(key) for \(required).")
            }
            let value = try Self.required(key, in: options)
            if key == "plan-type", !["MONTHLY", "UPFRONT"].contains(value) {
                throw AscendKitError.invalidArguments("--plan-type must be MONTHLY or UPFRONT.")
            }
            resolvedQuery[required] = try Self.identifier(value, label: "--\(key)")
        }

        let id = try route.idOption.map { try Self.identifier(Self.required($0, in: options), label: "--\($0)") }
        let path = route.idOption.flatMap { key in id.map { route.path.replacingOccurrences(of: "{\(key)}", with: $0) } } ?? route.path
        let payload: PPOJSONValue?
        let sourcePath: String?
        if route.body == .upload {
            let source = URL(fileURLWithPath: try Self.required("file", in: options)).standardizedFileURL
            let attributes = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard attributes.isRegularFile == true, let size = attributes.fileSize, size > 0, size <= 9_007_199_254_740_991 else {
                throw AscendKitError.invalidArguments("Asset upload requires a nonempty regular file.")
            }
            sourcePath = source.path
            payload = route.method == "GET" ? nil : try assetReservation(path: path, source: source, size: size, options: options)
        } else {
            sourcePath = nil
            payload = try makePayload(route: route, id: id, options: options)
        }
        return ASCOperationPlan(domain: domain, action: action, method: route.method, path: path, query: resolvedQuery, accept: route.accept,
                                payload: payload, sourcePath: sourcePath, requiresSubmissionConfirmation: route.body == .reviewSubmit)
    }

    private func makePayload(route: Route, id: String?, options: [String: String]) throws -> PPOJSONValue? {
        func option(_ key: String) throws -> String { try Self.required(key, in: options) }
        func link(_ type: String, option key: String) throws -> PPOJSONValue {
            Self.link(type, try Self.identifier(option(key), label: "--\(key)"))
        }
        func boolean(_ key: String) throws -> PPOJSONValue {
            let value = try option(key)
            guard value == "true" || value == "false" else {
                throw AscendKitError.invalidArguments("--\(key) must be true or false.")
            }
            return .bool(value == "true")
        }
        func choice(_ key: String, from choices: [String]) throws -> PPOJSONValue {
            let value = try option(key)
            guard choices.contains(value) else {
                throw AscendKitError.invalidArguments("--\(key) must be one of \(choices.joined(separator: ", ")).")
            }
            return .string(value)
        }
        switch route.body {
        case .none, .upload:
            return nil
        case let .document(type, list, matchingID, required):
            let file = URL(fileURLWithPath: try option("file"))
            let fileData = try Data(contentsOf: file)
            let document: PPOJSONValue
            do {
                document = try AscendKitJSON.decoder.decode(PPOJSONValue.self, from: fileData)
            } catch {
                throw AscendKitError.invalidArguments("--file must contain a valid ASC JSON request.")
            }
            guard let data = document["data"] else {
                throw AscendKitError.invalidArguments("--file must contain an ASC JSON request with a data member.")
            }
            if list {
                guard case .array(let links) = data, !links.isEmpty || type == "territories" else {
                    throw AscendKitError.invalidArguments("--file data must be an array of \(type) resource identifiers.")
                }
                for link in links { try Self.validateResource(link, type: type, needsID: true) }
            } else {
                try Self.validateResource(data, type: type, needsID: matchingID)
                if matchingID, let id, data["id"] != .string(id) {
                    throw AscendKitError.invalidArguments("--file data.id must match --\(route.idOption ?? "id").")
                }
                for key in required.split(separator: " ").map(String.init) {
                    guard case .object(let fields)? = data[key], !fields.isEmpty else {
                        throw AscendKitError.invalidArguments("--file data.\(key) must be a nonempty object.")
                    }
                }
            }
            return document
        case .ageRating:
            var attributes: [String: PPOJSONValue] = [:]
            if options["shared-location"] != nil { attributes["sharedLocation"] = try boolean("shared-location") }
            if options["dating-and-relationships"] != nil { attributes["datingAndRelationships"] = try boolean("dating-and-relationships") }
            if options["social-media"] != nil { attributes["socialMedia"] = try boolean("social-media") }
            if options["social-media-age-restricted"] != nil { attributes["socialMediaAgeRestricted"] = try boolean("social-media-age-restricted") }
            if options["korea-age-rating-override"] != nil {
                attributes["koreaAgeRatingOverride"] = try choice("korea-age-rating-override", from: ["NONE", "ALL", "TWELVE_PLUS", "FIFTEEN_PLUS", "NINETEEN_PLUS"])
            }
            guard !attributes.isEmpty else {
                throw AscendKitError.invalidArguments("Set at least one age rating option. Run ascendkit asc age-rating --help.")
            }
            return Self.document("ageRatingDeclarations", id: id, attributes: attributes)
        case .blocked:
            let type = route.action == "score-set" ? "gameCenterScoreModerations" : "gameCenterDetailPlayers"
            var attributes = ["blocked": try boolean("blocked")]
            if options["bundle-id"] != nil {
                attributes["bundleId"] = .string(try option("bundle-id"))
            }
            return Self.document(type, id: id, attributes: attributes)
        case .multiSeat:
            var attributes: [String: PPOJSONValue] = [:]
            if options["multi-seat-status"] != nil {
                attributes["multiSeatStatus"] = try choice("multi-seat-status", from: ["ENABLED", "DISABLED"])
            }
            if options["market-settings"] != nil {
                let markets = try option("market-settings").components(separatedBy: ",")
                guard markets.allSatisfy(["APP_STORE", "APPLE_BUSINESS", "APPLE_SCHOOL"].contains),
                      Set(markets).count == markets.count else {
                    throw AscendKitError.invalidArguments("--market-settings requires unique comma-separated APP_STORE, APPLE_BUSINESS, or APPLE_SCHOOL values.")
                }
                attributes["marketSettings"] = .array(markets.map(PPOJSONValue.string))
            }
            guard !attributes.isEmpty else {
                throw AscendKitError.invalidArguments("Specify --multi-seat-status or --market-settings.")
            }
            return Self.document("subscriptions", id: id, attributes: attributes)
        case .invitationMode:
            return Self.document("apps", id: id, attributes: [
                "groupPurchaseInvitationMode": try choice("group-purchase-invitation-mode", from: ["APPLE_HOSTED", "DEVELOPER_HOSTED"])
            ])
        case .messageLink:
            return .object(["data": try link("retentionMessages", option: "message-id")])
        case .offerLinks:
            let ids = try option("offer-ids").components(separatedBy: ",")
            guard Set(ids).count == ids.count else {
                throw AscendKitError.invalidArguments("--offer-ids requires unique comma-separated offer IDs.")
            }
            return .object(["data": .array(try ids.map { Self.link("retentionOffers", try Self.identifier($0, label: "--offer-ids")) })])
        case .reviewCreate:
            let platform = try options["platform"].map { _ in
                try choice("platform", from: ["IOS", "MAC_OS", "TV_OS", "VISION_OS"])
            } ?? .string("IOS")
            return Self.document("reviewSubmissions", attributes: ["platform": platform],
                                 relationships: ["app": try link("apps", option: "app-id")])
        case .retentionReviewAdd:
            return Self.document("reviewSubmissionItems", relationships: [
                "reviewSubmission": try link("reviewSubmissions", option: "review-submission-id"),
                "retentionMessageVersion": try link("retentionMessageVersions", option: "version-id")
            ])
        case .purchaseReviewAdd:
            let kinds = ["IAP": "inAppPurchaseVersion", "SUBSCRIPTION": "subscriptionVersion", "GROUP": "subscriptionGroupVersion"]
            guard let kind = kinds[try option("version-type")] else {
                throw AscendKitError.invalidArguments("--version-type must be IAP, SUBSCRIPTION, or GROUP.")
            }
            return Self.document("reviewSubmissionItems", relationships: [
                "reviewSubmission": try link("reviewSubmissions", option: "review-submission-id"),
                kind: try link(kind + "s", option: "version-id")
            ])
        case .assetReviewAdd:
            let assetOptions = ["image-id", "video-id"].filter { options[$0] != nil }
            guard assetOptions.count == 1, let assetOption = assetOptions.first else {
                throw AscendKitError.invalidArguments("Specify exactly one of --image-id or --video-id.")
            }
            let kind = assetOption == "image-id" ? "Image" : "Video"
            return Self.document("reviewSubmissionItems", relationships: [
                "reviewSubmission": try link("reviewSubmissions", option: "review-submission-id"),
                "appAssetLibrary\(kind)": try link("appAssetLibrary\(kind)s", option: assetOption)
            ])
        case .reviewSubmit:
            return Self.document("reviewSubmissions", id: id, attributes: ["submitted": .bool(true)])
        }
    }

    private func assetReservation(path: String, source: URL, size: Int, options: [String: String]) throws -> PPOJSONValue {
        let fileAttributes: [String: PPOJSONValue] = [
            "fileName": .string(source.lastPathComponent), "fileSize": .number(Double(size))
        ]
        if path.hasPrefix("v2/") {
            let isIAP = path == "v2/inAppPurchaseImages"
            let version = try Self.identifier(Self.required("version-id", in: options), label: "--version-id")
            return Self.document(isIAP ? "inAppPurchaseImages" : "subscriptionImages", attributes: fileAttributes,
                                 relationships: ["version": Self.link(isIAP ? "inAppPurchaseVersions" : "subscriptionVersions", version)])
        }
        let category = try Self.required("category", in: options)
        guard ["CREATIVE_ASSETS", "APP_SCREENSHOTS_AND_PREVIEWS"].contains(category) else {
            throw AscendKitError.invalidArguments("--category must be CREATIVE_ASSETS or APP_SCREENSHOTS_AND_PREVIEWS.")
        }
        let libraryID = try Self.identifier(Self.required("library-id", in: options), label: "--library-id")
        let isVideo = path.hasSuffix("Videos")
        var attributes = fileAttributes
        attributes["category"] = .string(category)
        if let name = options["reference-name"] { attributes["referenceName"] = .string(name) }
        if let timeCode = options["preview-frame-time-code"] { attributes["previewFrameTimeCode"] = .string(timeCode) }
        return Self.document(isVideo ? "appAssetLibraryVideos" : "appAssetLibraryImages", attributes: attributes,
                             relationships: ["assetLibrary": Self.link("appAssetLibraries", libraryID)])
    }

    static func identifier(_ value: String, label: String) throws -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~=:")
        guard !value.isEmpty, value != ".", value != "..",
              value.unicodeScalars.allSatisfy(allowed.contains) else {
            throw AscendKitError.invalidArguments("Invalid \(label). Expected an ASC resource ID.")
        }
        return value
    }

    private static func required(_ key: String, in options: [String: String]) throws -> String {
        guard let value = options[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AscendKitError.invalidArguments("Missing --\(key).")
        }
        return value
    }

    private static func validateResource(_ resource: PPOJSONValue, type: String, needsID: Bool) throws {
        guard resource["type"] == .string(type) else {
            throw AscendKitError.invalidArguments("--file resource type must be \(type).")
        }
        if needsID {
            guard case .string(let id)? = resource["id"] else {
                throw AscendKitError.invalidArguments("--file data.id is required.")
            }
            _ = try identifier(id, label: "--file data.id")
        }
    }

    private static func link(_ type: String, _ id: String) -> PPOJSONValue {
        .object(["type": .string(type), "id": .string(id)])
    }

    private static func document(
        _ type: String, id: String? = nil, attributes: [String: PPOJSONValue] = [:],
        relationships: [String: PPOJSONValue] = [:]
    ) -> PPOJSONValue {
        var resource = ["type": PPOJSONValue.string(type)]
        if let id { resource["id"] = .string(id) }
        if !attributes.isEmpty { resource["attributes"] = .object(attributes) }
        if !relationships.isEmpty { resource["relationships"] = .object(relationships.mapValues { .object(["data": $0]) }) }
        return .object(["data": .object(resource)])
    }

    private enum Body: Equatable, Sendable {
        case none, ageRating, blocked, multiSeat, invitationMode, messageLink, offerLinks, upload
        case reviewCreate, retentionReviewAdd, assetReviewAdd, purchaseReviewAdd, reviewSubmit
        case document(String, list: Bool = false, matchingID: Bool = false, required: String = "")

        var requiredOptions: [String] {
            switch self {
            case .document: ["file"]
            case .blocked: ["blocked"]
            case .invitationMode: ["group-purchase-invitation-mode"]
            case .messageLink: ["message-id"]
            case .offerLinks: ["offer-ids"]
            case .upload: ["file"]
            case .reviewCreate: ["app-id"]
            case .retentionReviewAdd: ["review-submission-id", "version-id"]
            case .purchaseReviewAdd: ["review-submission-id", "version-id", "version-type"]
            case .assetReviewAdd: ["review-submission-id"]
            default: []
            }
        }

        var optionalOptions: [String] {
            switch self {
            case .ageRating: ["shared-location", "dating-and-relationships", "korea-age-rating-override", "social-media", "social-media-age-restricted"]
            case .multiSeat: ["multi-seat-status", "market-settings"]
            case .reviewCreate: ["platform"]
            case .assetReviewAdd: ["image-id", "video-id"]
            default: []
            }
        }
    }

    private struct Route: Sendable {
        let action: String
        let method: String
        let path: String
        let query: String
        let requiredQuery: String?
        let accept: String
        let body: Body

        var requiredQueryOption: String? {
            switch requiredQuery {
            case "filter[subscription]": "subscription-id"
            case "filter[planType]": "plan-type"
            default: nil
            }
        }

        var idOption: String? {
            guard let start = path.firstIndex(of: "{"), let end = path.firstIndex(of: "}") else { return nil }
            return String(path[path.index(after: start)..<end])
        }

        var requiredOptions: [String] {
            var options = body.requiredOptions
            if let idOption { options.append(idOption) }
            if let requiredQueryOption { options.append(requiredQueryOption) }
            if body == .upload, method == "POST" {
                options += path.hasPrefix("v2/") ? ["version-id"] : ["library-id", "category"]
            }
            return options
        }

        var optionalOptions: [String] {
            switch action {
            case "player-set": ["bundle-id"]
            case "image-upload": ["reference-name"]
            case "video-upload": ["reference-name", "preview-frame-time-code"]
            default: body.optionalOptions
            }
        }

        init(_ action: String, _ method: String, _ path: String, query: String = "", requiredQuery: String? = nil, accept: String = "application/json", body: Body = .none) {
            self.action = action
            self.method = method
            self.path = path
            self.query = query
            self.requiredQuery = requiredQuery
            self.accept = accept
            self.body = body
        }
    }

    // Public operations checked against Apple's App Store Connect OpenAPI 4.6.1.
    private static let routes: [String: [Route]] = [
        "age-rating": [
            .init("app-infos", "GET", "v1/apps/{app-id}/appInfos", query: "fields[appInfos] fields[apps] fields[ageRatingDeclarations] fields[appInfoLocalizations] fields[appCategories] limit include limit[appInfoLocalizations]"),
            .init("observe", "GET", "v1/appInfos/{app-info-id}/ageRatingDeclaration", query: "fields[ageRatingDeclarations]"),
            .init("observe-ids", "GET", "v1/appInfos/{app-info-id}/relationships/ageRatingDeclaration"),
            .init("territories", "GET", "v1/appInfos/{app-info-id}/territoryAgeRatings", query: "fields[territoryAgeRatings] fields[territories] limit include"),
            .init("territories-ids", "GET", "v1/appInfos/{app-info-id}/relationships/territoryAgeRatings", query: "limit"),
            .init("set", "PATCH", "v1/ageRatingDeclarations/{declaration-id}", body: .ageRating),
        ],
        "accessibility": [
            .init("list", "GET", "v1/apps/{app-id}/accessibilityDeclarations", query: "filter[deviceFamily] filter[state] fields[accessibilityDeclarations] limit"),
            .init("list-ids", "GET", "v1/apps/{app-id}/relationships/accessibilityDeclarations", query: "limit"),
            .init("get", "GET", "v1/accessibilityDeclarations/{declaration-id}", query: "fields[accessibilityDeclarations]"),
            .init("create", "POST", "v1/accessibilityDeclarations", body: .document("accessibilityDeclarations", required: "attributes relationships")),
            .init("set", "PATCH", "v1/accessibilityDeclarations/{declaration-id}", body: .document("accessibilityDeclarations", matchingID: true)),
            .init("delete", "DELETE", "v1/accessibilityDeclarations/{declaration-id}"),
        ],
        "app-performance": [
            .init("overview", "GET", "v1/apps/{app-id}/performanceOverviews", query: "filter[deviceType]", accept: "application/vnd.apple.xcode-overview+json"),
            .init("app-metrics", "GET", "v1/apps/{app-id}/perfPowerMetrics", query: "filter[platform] filter[metricType] filter[deviceType]", accept: "application/vnd.apple.xcode-metrics+json"),
            .init("build-metrics", "GET", "v1/builds/{build-id}/perfPowerMetrics", query: "filter[platform] filter[metricType] filter[deviceType]", accept: "application/vnd.apple.xcode-metrics+json"),
        ],
        "game-center-moderation": [
            .init("scores", "GET", "v2/gameCenterLeaderboards/{leaderboard-id}/gameCenterScoreModerations", query: "exists[blocked] fields[gameCenterScoreModerations] fields[gameCenterDetailPlayers] limit include"),
            .init("scores-ids", "GET", "v2/gameCenterLeaderboards/{leaderboard-id}/relationships/gameCenterScoreModerations", query: "limit"),
            .init("blocked-players", "GET", "v1/gameCenterDetails/{detail-id}/blockedPlayers", query: "fields[gameCenterDetailPlayers] limit"),
            .init("blocked-players-ids", "GET", "v1/gameCenterDetails/{detail-id}/relationships/blockedPlayers", query: "limit"),
            .init("detail", "GET", "v1/apps/{app-id}/gameCenterDetail", query: "fields[gameCenterDetails] fields[apps] fields[gameCenterAppVersions] fields[gameCenterGroups] fields[gameCenterLeaderboards] fields[gameCenterLeaderboardSets] fields[gameCenterAchievements] fields[gameCenterActivities] fields[gameCenterChallenges] fields[gameCenterAchievementReleases] fields[gameCenterActivityVersionReleases] fields[gameCenterChallengeVersionReleases] fields[gameCenterLeaderboardReleases] fields[gameCenterLeaderboardSetReleases] fields[appStoreVersions] include limit[gameCenterAppVersions] limit[gameCenterLeaderboards] limit[gameCenterLeaderboardsV2] limit[gameCenterLeaderboardSets] limit[gameCenterLeaderboardSetsV2] limit[gameCenterAchievements] limit[gameCenterAchievementsV2] limit[gameCenterActivities] limit[gameCenterChallenges] limit[achievementReleases] limit[activityReleases] limit[challengeReleases] limit[leaderboardReleases] limit[leaderboardSetReleases] limit[challengesMinimumPlatformVersions]"),
            .init("score-set", "PATCH", "v1/gameCenterScoreModerations/{score-id}", body: .blocked),
            .init("player-set", "PATCH", "v1/gameCenterDetailPlayers/{player-id}", body: .blocked),
        ],
        "asset-library": [
            .init("observe", "GET", "v1/apps/{app-id}/assetLibrary", query: "fields[appAssetLibraries]"),
            .init("observe-ids", "GET", "v1/apps/{app-id}/relationships/assetLibrary"),
            .init("get", "GET", "v1/appAssetLibraries/{library-id}", query: "fields[appAssetLibraries]"),
            .init("ref-data", "GET", "v1/appAssetLibraryRefData", query: "filter[placementTypes] filter[placementProfileGroups] filter[features] filter[specs] fields[appAssetLibraryRefData]"),
            .init("ref-data-get", "GET", "v1/appAssetLibraryRefData/{ref-data-id}", query: "fields[appAssetLibraryRefData]"),
            .init("images", "GET", "v1/appAssetLibraries/{library-id}/images", query: "filter[category] filter[state] filter[referenceName] filter[specId] filter[id] sort fields[appAssetLibraryImages] fields[appAssetLibraryPlacements] limit include limit[placements]"),
            .init("images-ids", "GET", "v1/appAssetLibraries/{library-id}/relationships/images", query: "limit"),
            .init("image-create", "POST", "v1/appAssetLibraryImages", body: .document("appAssetLibraryImages", required: "attributes relationships")),
            .init("image-get", "GET", "v1/appAssetLibraryImages/{image-id}", query: "fields[appAssetLibraryImages] fields[appAssetLibraryPlacements] include limit[placements]"),
            .init("image-update", "PATCH", "v1/appAssetLibraryImages/{image-id}", body: .document("appAssetLibraryImages", matchingID: true)),
            .init("image-delete", "DELETE", "v1/appAssetLibraryImages/{image-id}"),
            .init("image-placements", "GET", "v1/appAssetLibraryImages/{image-id}/placements", query: "filter[placementType] filter[placementGroup] filter[state] filter[video] filter[appEventLocalization] filter[appStoreVersionLocalization] filter[appCustomProductPageLocalization] filter[appStoreVersionExperimentTreatmentLocalization] filter[id] sort fields[appAssetLibraryPlacements] fields[appAssetLibraryImages] fields[appAssetLibraryVideos] fields[appEventLocalizations] fields[appStoreVersionLocalizations] fields[appCustomProductPageLocalizations] fields[appStoreVersionExperimentTreatmentLocalizations] fields[retentionMessageVersions] limit include"),
            .init("image-placements-ids", "GET", "v1/appAssetLibraryImages/{image-id}/relationships/placements", query: "limit"),
            .init("image-upload", "POST", "v1/appAssetLibraryImages", body: .upload),
            .init("image-upload-resume", "GET", "v1/appAssetLibraryImages/{image-id}", body: .upload),
            .init("videos", "GET", "v1/appAssetLibraries/{library-id}/videos", query: "filter[category] filter[state] filter[referenceName] filter[specId] filter[id] sort fields[appAssetLibraryVideos] fields[appAssetLibraryPlacements] limit include limit[placements]"),
            .init("videos-ids", "GET", "v1/appAssetLibraries/{library-id}/relationships/videos", query: "limit"),
            .init("video-create", "POST", "v1/appAssetLibraryVideos", body: .document("appAssetLibraryVideos", required: "attributes relationships")),
            .init("video-get", "GET", "v1/appAssetLibraryVideos/{video-id}", query: "fields[appAssetLibraryVideos] fields[appAssetLibraryPlacements] include limit[placements]"),
            .init("video-update", "PATCH", "v1/appAssetLibraryVideos/{video-id}", body: .document("appAssetLibraryVideos", matchingID: true)),
            .init("video-delete", "DELETE", "v1/appAssetLibraryVideos/{video-id}"),
            .init("video-placements", "GET", "v1/appAssetLibraryVideos/{video-id}/placements", query: "filter[placementType] filter[placementGroup] filter[state] filter[image] filter[appEventLocalization] filter[appStoreVersionLocalization] filter[appCustomProductPageLocalization] filter[appStoreVersionExperimentTreatmentLocalization] filter[id] sort fields[appAssetLibraryPlacements] fields[appAssetLibraryImages] fields[appAssetLibraryVideos] fields[appEventLocalizations] fields[appStoreVersionLocalizations] fields[appCustomProductPageLocalizations] fields[appStoreVersionExperimentTreatmentLocalizations] fields[retentionMessageVersions] limit include"),
            .init("video-placements-ids", "GET", "v1/appAssetLibraryVideos/{video-id}/relationships/placements", query: "limit"),
            .init("video-upload", "POST", "v1/appAssetLibraryVideos", body: .upload),
            .init("video-upload-resume", "GET", "v1/appAssetLibraryVideos/{video-id}", body: .upload),
            .init("version-placements", "GET", "v1/appStoreVersionLocalizations/{localization-id}/placements", query: "filter[placementType] filter[placementGroup] filter[state] filter[image] filter[video] filter[appEventLocalization] filter[appCustomProductPageLocalization] filter[appStoreVersionExperimentTreatmentLocalization] filter[id] sort fields[appAssetLibraryPlacements] fields[appAssetLibraryImages] fields[appAssetLibraryVideos] fields[appEventLocalizations] fields[appStoreVersionLocalizations] fields[appCustomProductPageLocalizations] fields[appStoreVersionExperimentTreatmentLocalizations] fields[retentionMessageVersions] limit include"),
            .init("version-placements-ids", "GET", "v1/appStoreVersionLocalizations/{localization-id}/relationships/placements", query: "limit"),
            .init("custom-page-placements", "GET", "v1/appCustomProductPageLocalizations/{localization-id}/placements", query: "filter[placementType] filter[placementGroup] filter[state] filter[image] filter[video] filter[appEventLocalization] filter[appStoreVersionLocalization] filter[appStoreVersionExperimentTreatmentLocalization] filter[id] sort fields[appAssetLibraryPlacements] fields[appAssetLibraryImages] fields[appAssetLibraryVideos] fields[appEventLocalizations] fields[appStoreVersionLocalizations] fields[appCustomProductPageLocalizations] fields[appStoreVersionExperimentTreatmentLocalizations] fields[retentionMessageVersions] limit include"),
            .init("custom-page-placements-ids", "GET", "v1/appCustomProductPageLocalizations/{localization-id}/relationships/placements", query: "limit"),
            .init("event-placements", "GET", "v1/appEventLocalizations/{localization-id}/placements", query: "filter[placementType] filter[placementGroup] filter[state] filter[image] filter[video] filter[appStoreVersionLocalization] filter[appCustomProductPageLocalization] filter[appStoreVersionExperimentTreatmentLocalization] filter[id] sort fields[appAssetLibraryPlacements] fields[appAssetLibraryImages] fields[appAssetLibraryVideos] fields[appEventLocalizations] fields[appStoreVersionLocalizations] fields[appCustomProductPageLocalizations] fields[appStoreVersionExperimentTreatmentLocalizations] fields[retentionMessageVersions] limit include"),
            .init("event-placements-ids", "GET", "v1/appEventLocalizations/{localization-id}/relationships/placements", query: "limit"),
            .init("treatment-placements", "GET", "v1/appStoreVersionExperimentTreatmentLocalizations/{localization-id}/placements", query: "filter[placementType] filter[placementGroup] filter[state] filter[image] filter[video] filter[appEventLocalization] filter[appStoreVersionLocalization] filter[appCustomProductPageLocalization] filter[id] sort fields[appAssetLibraryPlacements] fields[appAssetLibraryImages] fields[appAssetLibraryVideos] fields[appEventLocalizations] fields[appStoreVersionLocalizations] fields[appCustomProductPageLocalizations] fields[appStoreVersionExperimentTreatmentLocalizations] fields[retentionMessageVersions] limit include"),
            .init("treatment-placements-ids", "GET", "v1/appStoreVersionExperimentTreatmentLocalizations/{localization-id}/relationships/placements", query: "limit"),
            .init("placement-get", "GET", "v1/appAssetLibraryPlacements/{placement-id}", query: "fields[appAssetLibraryPlacements] fields[appAssetLibraryImages] fields[appAssetLibraryVideos] fields[appEventLocalizations] fields[appStoreVersionLocalizations] fields[appCustomProductPageLocalizations] fields[appStoreVersionExperimentTreatmentLocalizations] fields[retentionMessageVersions] include"),
            .init("placement-create", "POST", "v1/appAssetLibraryPlacements", body: .document("appAssetLibraryPlacements")),
            .init("placement-delete", "DELETE", "v1/appAssetLibraryPlacements/{placement-id}"),
            .init("placement-order", "POST", "v1/appAssetLibraryPlacementOrderingRequests", query: "fields[appAssetLibraryPlacements] include limit[orderedPlacements] fields[appAssetLibraryPlacementOrderingRequests]", body: .document("appAssetLibraryPlacementOrderingRequests")),
            .init("review-list", "GET", "v1/apps/{app-id}/reviewSubmissions", query: "filter[platform] filter[state] fields[reviewSubmissions] fields[apps] fields[reviewSubmissionItems] fields[appStoreVersions] fields[actors] limit include limit[items]"),
            .init("review-get", "GET", "v1/reviewSubmissions/{review-submission-id}", query: "fields[reviewSubmissions] fields[apps] fields[reviewSubmissionItems] fields[appStoreVersions] fields[actors] include limit[items]"),
            .init("review-items", "GET", "v1/reviewSubmissions/{review-submission-id}/items", query: "fields[reviewSubmissionItems] fields[appStoreVersions] fields[appCustomProductPageVersions] fields[appStoreVersionExperiments] fields[appEvents] fields[appAssetLibraryImages] fields[appAssetLibraryVideos] fields[backgroundAssetVersions] fields[gameCenterAchievementVersions] fields[gameCenterActivityVersions] fields[gameCenterChallengeVersions] fields[gameCenterLeaderboardSetVersions] fields[gameCenterLeaderboardVersions] fields[inAppPurchaseVersions] fields[subscriptionVersions] fields[subscriptionGroupVersions] fields[retentionMessageVersions] limit include"),
            .init("review-create", "POST", "v1/reviewSubmissions", body: .reviewCreate),
            .init("review-add", "POST", "v1/reviewSubmissionItems", body: .assetReviewAdd),
            .init("review-submit", "PATCH", "v1/reviewSubmissions/{review-submission-id}", body: .reviewSubmit),
        ],
        "retention": [
            .init("list", "GET", "v1/apps/{app-id}/retentionMessages", query: "fields[retentionMessages] fields[retentionMessageVersions] fields[subscriptions] limit include limit[versions] limit[subscriptions]"),
            .init("list-ids", "GET", "v1/apps/{app-id}/relationships/retentionMessages", query: "limit"),
            .init("message-get", "GET", "v1/retentionMessages/{message-id}", query: "fields[retentionMessages] fields[retentionMessageVersions] fields[subscriptions] include limit[subscriptions] limit[versions]"),
            .init("message-create", "POST", "v1/retentionMessages", body: .document("retentionMessages", required: "attributes relationships")),
            .init("message-delete", "DELETE", "v1/retentionMessages/{message-id}"),
            .init("message-subscriptions", "GET", "v1/retentionMessages/{message-id}/subscriptions", query: "filter[productId] filter[name] filter[state] sort fields[subscriptions] fields[subscriptionLocalizations] fields[subscriptionAppStoreReviewScreenshots] fields[subscriptionGroups] fields[subscriptionIntroductoryOffers] fields[subscriptionPromotionalOffers] fields[subscriptionOfferCodes] fields[subscriptionPrices] fields[promotedPurchases] fields[subscriptionAvailabilities] fields[winBackOffers] fields[subscriptionImages] fields[subscriptionPlanAvailabilities] fields[subscriptionVersions] fields[retentionOffers] fields[retentionMessages] limit include limit[subscriptionLocalizations] limit[introductoryOffers] limit[promotionalOffers] limit[offerCodes] limit[prices] limit[winBackOffers] limit[images] limit[planAvailabilities] limit[versions] limit[retentionOffers] limit[retentionMessageOffers]"),
            .init("message-subscriptions-ids", "GET", "v1/retentionMessages/{message-id}/relationships/subscriptions", query: "limit"),
            .init("versions", "GET", "v1/retentionMessages/{message-id}/versions", query: "fields[retentionMessageVersions] fields[retentionMessages] fields[retentionMessageLocalizations] fields[appAssetLibraryPlacements] limit include limit[localizations]"),
            .init("versions-ids", "GET", "v1/retentionMessages/{message-id}/relationships/versions", query: "limit"),
            .init("version-get", "GET", "v1/retentionMessageVersions/{version-id}", query: "fields[retentionMessageVersions] fields[retentionMessages] fields[retentionMessageLocalizations] fields[appAssetLibraryPlacements] include limit[localizations]"),
            .init("version-create", "POST", "v1/retentionMessageVersions", body: .document("retentionMessageVersions", required: "relationships")),
            .init("localizations", "GET", "v1/retentionMessageVersions/{version-id}/localizations", query: "fields[retentionMessageLocalizations] fields[retentionMessageVersions] limit include"),
            .init("localizations-ids", "GET", "v1/retentionMessageVersions/{version-id}/relationships/localizations", query: "limit"),
            .init("version-placement", "GET", "v1/retentionMessageVersions/{version-id}/placement", query: "fields[appAssetLibraryPlacements] fields[appAssetLibraryImages] fields[appAssetLibraryVideos] fields[appEventLocalizations] fields[appStoreVersionLocalizations] fields[appCustomProductPageLocalizations] fields[appStoreVersionExperimentTreatmentLocalizations] fields[retentionMessageVersions] include"),
            .init("version-placement-ids", "GET", "v1/retentionMessageVersions/{version-id}/relationships/placement"),
            .init("localization-get", "GET", "v1/retentionMessageLocalizations/{localization-id}", query: "fields[retentionMessageLocalizations] fields[retentionMessageVersions] include"),
            .init("localization-create", "POST", "v1/retentionMessageLocalizations", body: .document("retentionMessageLocalizations", required: "attributes relationships")),
            .init("localization-update", "PATCH", "v1/retentionMessageLocalizations/{localization-id}", body: .document("retentionMessageLocalizations", matchingID: true)),
            .init("localization-delete", "DELETE", "v1/retentionMessageLocalizations/{localization-id}"),
            .init("offer-get", "GET", "v1/retentionOffers/{offer-id}", query: "fields[retentionOffers] fields[subscriptions] fields[retentionOfferPrices] include limit[prices]"),
            .init("offer-create", "POST", "v1/retentionOffers", body: .document("retentionOffers", required: "attributes relationships")),
            .init("offer-update", "PATCH", "v1/retentionOffers/{offer-id}", body: .document("retentionOffers", matchingID: true)),
            .init("offer-delete", "DELETE", "v1/retentionOffers/{offer-id}"),
            .init("offer-prices", "GET", "v1/retentionOffers/{offer-id}/prices", query: "filter[territory] fields[retentionOfferPrices] fields[territories] fields[subscriptionPricePoints] limit include"),
            .init("offer-prices-ids", "GET", "v1/retentionOffers/{offer-id}/relationships/prices", query: "limit"),
            .init("subscription-message", "GET", "v1/subscriptions/{subscription-id}/retentionMessage", query: "fields[retentionMessages] fields[retentionMessageVersions] fields[subscriptions] include limit[versions] limit[subscriptions]"),
            .init("subscription-message-ids", "GET", "v1/subscriptions/{subscription-id}/relationships/retentionMessage"),
            .init("subscription-message-offers", "GET", "v1/subscriptions/{subscription-id}/retentionMessageOffers", query: "fields[retentionOffers] fields[subscriptions] fields[retentionOfferPrices] limit include limit[prices]"),
            .init("subscription-message-offers-ids", "GET", "v1/subscriptions/{subscription-id}/relationships/retentionMessageOffers", query: "limit"),
            .init("subscription-offers", "GET", "v1/subscriptions/{subscription-id}/retentionOffers", query: "fields[retentionOffers] fields[subscriptions] fields[retentionOfferPrices] limit include limit[prices]"),
            .init("subscription-offers-ids", "GET", "v1/subscriptions/{subscription-id}/relationships/retentionOffers", query: "limit"),
            .init("subscription-message-set", "PATCH", "v1/subscriptions/{subscription-id}/relationships/retentionMessage", body: .messageLink),
            .init("subscription-offers-add", "POST", "v1/subscriptions/{subscription-id}/relationships/retentionMessageOffers", body: .offerLinks),
            .init("subscription-offers-remove", "DELETE", "v1/subscriptions/{subscription-id}/relationships/retentionMessageOffers", body: .offerLinks),
            .init("review-list", "GET", "v1/apps/{app-id}/reviewSubmissions", query: "filter[platform] filter[state] fields[reviewSubmissions] fields[apps] fields[reviewSubmissionItems] fields[appStoreVersions] fields[actors] limit include limit[items]"),
            .init("review-get", "GET", "v1/reviewSubmissions/{review-submission-id}", query: "fields[reviewSubmissions] fields[apps] fields[reviewSubmissionItems] fields[appStoreVersions] fields[actors] include limit[items]"),
            .init("review-items", "GET", "v1/reviewSubmissions/{review-submission-id}/items", query: "fields[reviewSubmissionItems] fields[appStoreVersions] fields[appCustomProductPageVersions] fields[appStoreVersionExperiments] fields[appEvents] fields[appAssetLibraryImages] fields[appAssetLibraryVideos] fields[backgroundAssetVersions] fields[gameCenterAchievementVersions] fields[gameCenterActivityVersions] fields[gameCenterChallengeVersions] fields[gameCenterLeaderboardSetVersions] fields[gameCenterLeaderboardVersions] fields[inAppPurchaseVersions] fields[subscriptionVersions] fields[subscriptionGroupVersions] fields[retentionMessageVersions] limit include"),
            .init("review-create", "POST", "v1/reviewSubmissions", body: .reviewCreate),
            .init("review-add", "POST", "v1/reviewSubmissionItems", body: .retentionReviewAdd),
            .init("review-submit", "PATCH", "v1/reviewSubmissions/{review-submission-id}", body: .reviewSubmit),
        ],
        "subscriptions": [
            .init("groups", "GET", "v1/apps/{app-id}/subscriptionGroups", query: "filter[referenceName] filter[subscriptions.state] sort fields[subscriptionGroups] fields[subscriptions] fields[subscriptionGroupLocalizations] fields[subscriptionGroupVersions] limit include limit[subscriptions] limit[subscriptionGroupLocalizations] limit[versions]"),
            .init("list", "GET", "v1/subscriptionGroups/{group-id}/subscriptions", query: "filter[productId] filter[name] filter[state] sort fields[subscriptions] fields[subscriptionLocalizations] fields[subscriptionAppStoreReviewScreenshots] fields[subscriptionGroups] fields[subscriptionIntroductoryOffers] fields[subscriptionPromotionalOffers] fields[subscriptionOfferCodes] fields[subscriptionPrices] fields[promotedPurchases] fields[subscriptionAvailabilities] fields[winBackOffers] fields[subscriptionImages] fields[subscriptionPlanAvailabilities] fields[subscriptionVersions] fields[retentionOffers] fields[retentionMessages] limit include limit[subscriptionLocalizations] limit[introductoryOffers] limit[promotionalOffers] limit[offerCodes] limit[prices] limit[winBackOffers] limit[images] limit[planAvailabilities] limit[versions] limit[retentionOffers] limit[retentionMessageOffers]"),
            .init("get", "GET", "v1/subscriptions/{subscription-id}", query: "fields[subscriptions] fields[subscriptionLocalizations] fields[subscriptionAppStoreReviewScreenshots] fields[subscriptionGroups] fields[subscriptionIntroductoryOffers] fields[subscriptionPromotionalOffers] fields[subscriptionOfferCodes] fields[subscriptionPrices] fields[promotedPurchases] fields[subscriptionAvailabilities] fields[winBackOffers] fields[subscriptionImages] fields[subscriptionPlanAvailabilities] fields[subscriptionVersions] fields[retentionOffers] fields[retentionMessages] include limit[images] limit[introductoryOffers] limit[offerCodes] limit[planAvailabilities] limit[prices] limit[promotionalOffers] limit[retentionMessageOffers] limit[retentionOffers] limit[subscriptionLocalizations] limit[versions] limit[winBackOffers]"),
            .init("set-multiseat", "PATCH", "v1/subscriptions/{subscription-id}", body: .multiSeat),
            .init("invitation-mode", "GET", "v1/apps/{app-id}", query: "fields[apps] fields[appEncryptionDeclarations] fields[buildIcons] fields[ciProducts] fields[betaGroups] fields[appStoreVersions] fields[preReleaseVersions] fields[betaAppLocalizations] fields[builds] fields[betaLicenseAgreements] fields[betaAppReviewDetails] fields[appInfos] fields[appClips] fields[endUserLicenseAgreements] fields[inAppPurchases] fields[subscriptionGroups] fields[retentionMessages] fields[gameCenterEnabledVersions] fields[appCustomProductPages] fields[promotedPurchases] fields[appEvents] fields[reviewSubmissions] fields[subscriptionGracePeriods] fields[gameCenterDetails] fields[appStoreVersionExperiments] fields[androidToIosAppMappingDetails] include limit[androidToIosAppMappingDetails] limit[appClips] limit[appCustomProductPages] limit[appEncryptionDeclarations] limit[appEvents] limit[appInfos] limit[appStoreVersionExperimentsV2] limit[appStoreVersions] limit[betaAppLocalizations] limit[betaGroups] limit[builds] limit[gameCenterEnabledVersions] limit[inAppPurchases] limit[inAppPurchasesV2] limit[preReleaseVersions] limit[promotedPurchases] limit[retentionMessages] limit[reviewSubmissions] limit[subscriptionGroups]"),
            .init("invitation-mode-set", "PATCH", "v1/apps/{app-id}", body: .invitationMode),
            .init("price-points", "GET", "v1/subscriptions/{subscription-id}/pricePoints", query: "filter[territory] filter[upfrontPricePointId] filter[planType] fields[subscriptionPricePoints] fields[territories] limit include"),
            .init("prices", "GET", "v1/subscriptions/{subscription-id}/prices", query: "filter[planType] filter[subscriptionPricePoint] filter[territory] fields[subscriptionPrices] fields[territories] fields[subscriptionPricePoints] fields[subscriptionPriceTiers] limit include limit[additionalPriceTiers]"),
            .init("price-tiers", "GET", "v1/subscriptionPriceTiers", query: "filter[subscription] filter[territory] fields[subscriptionPriceTiers] fields[subscriptionPricePoints] limit include", requiredQuery: "filter[subscription]"),
            .init("price-additional-tiers", "GET", "v1/subscriptionPrices/{price-id}/additionalPriceTiers", query: "filter[subscription] filter[territory] fields[subscriptionPriceTiers] fields[subscriptionPricePoints] limit include"),
            .init("price-additional-tiers-ids", "GET", "v1/subscriptionPrices/{price-id}/relationships/additionalPriceTiers", query: "limit"),
            .init("price-tier-equalize", "POST", "v1/subscriptionPriceTierEqualizations", query: "fields[subscriptionPricePoints] include limit[priceTierPricePoints] fields[subscriptionPriceTierEqualizations]", body: .document("subscriptionPriceTierEqualizations", required: "relationships")),
            .init("price-change-preview", "POST", "v1/subscriptionPriceChangePreviews", body: .document("subscriptionPriceChangePreviews", required: "relationships")),
            .init("price-create", "POST", "v1/subscriptionPrices", body: .document("subscriptionPrices", required: "relationships")),
            .init("price-delete", "DELETE", "v1/subscriptionPrices/{price-id}"),
            .init("price-point-adjusted-equalizations", "GET", "v1/subscriptionPricePoints/{price-point-id}/adjustedEqualizations", query: "filter[territory] filter[subscription] filter[upfrontPricePointId] filter[planType] fields[subscriptionPricePoints] fields[territories] limit include", requiredQuery: "filter[planType]"),
            .init("plan-availabilities", "GET", "v1/subscriptions/{subscription-id}/planAvailabilities", query: "fields[subscriptionPlanAvailabilities] fields[territories] limit include limit[availableTerritories]"),
            .init("plan-availabilities-ids", "GET", "v1/subscriptions/{subscription-id}/relationships/planAvailabilities", query: "limit"),
            .init("plan-availability-create", "POST", "v1/subscriptionPlanAvailabilities", body: .document("subscriptionPlanAvailabilities", required: "attributes relationships")),
            .init("plan-availability-get", "GET", "v1/subscriptionPlanAvailabilities/{availability-id}", query: "fields[subscriptionPlanAvailabilities] fields[territories] include limit[availableTerritories]"),
            .init("plan-availability-update", "PATCH", "v1/subscriptionPlanAvailabilities/{availability-id}", body: .document("subscriptionPlanAvailabilities", matchingID: true)),
            .init("plan-availability-territories", "GET", "v1/subscriptionPlanAvailabilities/{availability-id}/availableTerritories", query: "fields[territories] limit"),
            .init("plan-availability-territories-ids", "GET", "v1/subscriptionPlanAvailabilities/{availability-id}/relationships/availableTerritories", query: "limit"),
            .init("plan-availability-territories-set", "PATCH", "v1/subscriptionPlanAvailabilities/{availability-id}/relationships/availableTerritories", body: .document("territories", list: true)),
        ],
        "background-assets": [
            .init("list", "GET", "v1/apps/{app-id}/backgroundAssets", query: "filter[archived] filter[assetPackIdentifier] filter[versions.locale] filter[versions.platforms] sort fields[backgroundAssets] fields[apps] fields[backgroundAssetVersions] limit include"),
            .init("list-ids", "GET", "v1/apps/{app-id}/relationships/backgroundAssets", query: "limit"),
        ],
        "purchase-versions": [
            .init("iap-list", "GET", "v1/apps/{app-id}/inAppPurchasesV2", query: "filter[productId] filter[name] filter[state] filter[inAppPurchaseType] sort fields[inAppPurchases] fields[inAppPurchaseLocalizations] fields[inAppPurchaseContents] fields[inAppPurchaseAppStoreReviewScreenshots] fields[promotedPurchases] fields[inAppPurchasePriceSchedules] fields[inAppPurchaseAvailabilities] fields[inAppPurchaseImages] fields[inAppPurchaseOfferCodes] fields[inAppPurchaseVersions] limit include limit[inAppPurchaseLocalizations] limit[images] limit[offerCodes] limit[versions]"),
            .init("iap-versions", "GET", "v2/inAppPurchases/{iap-id}/versions", query: "filter[state] fields[inAppPurchaseVersions] fields[inAppPurchases] fields[inAppPurchaseImages] fields[inAppPurchaseLocalizations] limit include limit[images] limit[localizations]"),
            .init("iap-versions-ids", "GET", "v2/inAppPurchases/{iap-id}/relationships/versions", query: "limit"),
            .init("iap-version-get", "GET", "v1/inAppPurchaseVersions/{version-id}", query: "fields[inAppPurchaseVersions] fields[inAppPurchases] fields[inAppPurchaseImages] fields[inAppPurchaseLocalizations] include limit[images] limit[localizations]"),
            .init("iap-version-create", "POST", "v1/inAppPurchaseVersions", body: .document("inAppPurchaseVersions", required: "relationships")),
            .init("iap-localizations", "GET", "v1/inAppPurchaseVersions/{version-id}/localizations", query: "fields[inAppPurchaseLocalizations] fields[inAppPurchaseVersions] limit include"),
            .init("iap-localizations-ids", "GET", "v1/inAppPurchaseVersions/{version-id}/relationships/localizations", query: "limit"),
            .init("iap-localization-create", "POST", "v2/inAppPurchaseLocalizations", body: .document("inAppPurchaseLocalizations", required: "attributes relationships")),
            .init("iap-localization-get", "GET", "v2/inAppPurchaseLocalizations/{localization-id}", query: "fields[inAppPurchaseLocalizations] fields[inAppPurchaseVersions] include"),
            .init("iap-localization-update", "PATCH", "v2/inAppPurchaseLocalizations/{localization-id}", body: .document("inAppPurchaseLocalizations", matchingID: true)),
            .init("iap-localization-delete", "DELETE", "v2/inAppPurchaseLocalizations/{localization-id}"),
            .init("iap-image", "GET", "v1/inAppPurchaseVersions/{version-id}/image", query: "fields[inAppPurchaseImages]"),
            .init("iap-image-ids", "GET", "v1/inAppPurchaseVersions/{version-id}/relationships/image"),
            .init("iap-images", "GET", "v1/inAppPurchaseVersions/{version-id}/images", query: "fields[inAppPurchaseImages] limit"),
            .init("iap-images-ids", "GET", "v1/inAppPurchaseVersions/{version-id}/relationships/images", query: "limit"),
            .init("iap-image-create", "POST", "v2/inAppPurchaseImages", body: .document("inAppPurchaseImages", required: "attributes relationships")),
            .init("iap-image-get", "GET", "v2/inAppPurchaseImages/{image-id}", query: "fields[inAppPurchaseImages]"),
            .init("iap-image-update", "PATCH", "v2/inAppPurchaseImages/{image-id}", body: .document("inAppPurchaseImages", matchingID: true)),
            .init("iap-image-delete", "DELETE", "v2/inAppPurchaseImages/{image-id}"),
            .init("iap-image-upload", "POST", "v2/inAppPurchaseImages", body: .upload),
            .init("iap-image-upload-resume", "GET", "v2/inAppPurchaseImages/{image-id}", body: .upload),
            .init("subscription-versions", "GET", "v1/subscriptions/{subscription-id}/versions", query: "filter[state] fields[subscriptionVersions] fields[subscriptions] fields[subscriptionImages] fields[subscriptionLocalizations] limit include limit[images] limit[localizations]"),
            .init("subscription-versions-ids", "GET", "v1/subscriptions/{subscription-id}/relationships/versions", query: "limit"),
            .init("subscription-version-get", "GET", "v1/subscriptionVersions/{version-id}", query: "fields[subscriptionVersions] fields[subscriptions] fields[subscriptionImages] fields[subscriptionLocalizations] include limit[images] limit[localizations]"),
            .init("subscription-version-create", "POST", "v1/subscriptionVersions", body: .document("subscriptionVersions", required: "relationships")),
            .init("subscription-localizations", "GET", "v1/subscriptionVersions/{version-id}/localizations", query: "fields[subscriptionLocalizations] fields[subscriptionVersions] limit include"),
            .init("subscription-localizations-ids", "GET", "v1/subscriptionVersions/{version-id}/relationships/localizations", query: "limit"),
            .init("subscription-localization-create", "POST", "v2/subscriptionLocalizations", body: .document("subscriptionLocalizations", required: "attributes relationships")),
            .init("subscription-localization-get", "GET", "v2/subscriptionLocalizations/{localization-id}", query: "fields[subscriptionLocalizations] fields[subscriptionVersions] include"),
            .init("subscription-localization-update", "PATCH", "v2/subscriptionLocalizations/{localization-id}", body: .document("subscriptionLocalizations", matchingID: true)),
            .init("subscription-localization-delete", "DELETE", "v2/subscriptionLocalizations/{localization-id}"),
            .init("subscription-image", "GET", "v1/subscriptionVersions/{version-id}/image", query: "fields[subscriptionImages]"),
            .init("subscription-image-ids", "GET", "v1/subscriptionVersions/{version-id}/relationships/image"),
            .init("subscription-images", "GET", "v1/subscriptionVersions/{version-id}/images", query: "fields[subscriptionImages] limit"),
            .init("subscription-images-ids", "GET", "v1/subscriptionVersions/{version-id}/relationships/images", query: "limit"),
            .init("subscription-image-create", "POST", "v2/subscriptionImages", body: .document("subscriptionImages", required: "attributes relationships")),
            .init("subscription-image-get", "GET", "v2/subscriptionImages/{image-id}", query: "fields[subscriptionImages]"),
            .init("subscription-image-update", "PATCH", "v2/subscriptionImages/{image-id}", body: .document("subscriptionImages", matchingID: true)),
            .init("subscription-image-delete", "DELETE", "v2/subscriptionImages/{image-id}"),
            .init("subscription-image-upload", "POST", "v2/subscriptionImages", body: .upload),
            .init("subscription-image-upload-resume", "GET", "v2/subscriptionImages/{image-id}", body: .upload),
            .init("group-versions", "GET", "v1/subscriptionGroups/{group-id}/versions", query: "filter[state] fields[subscriptionGroupVersions] fields[subscriptionGroups] fields[subscriptionGroupLocalizations] limit include limit[localizations]"),
            .init("group-versions-ids", "GET", "v1/subscriptionGroups/{group-id}/relationships/versions", query: "limit"),
            .init("group-version-get", "GET", "v1/subscriptionGroupVersions/{version-id}", query: "fields[subscriptionGroupVersions] fields[subscriptionGroups] fields[subscriptionGroupLocalizations] include limit[localizations]"),
            .init("group-version-create", "POST", "v1/subscriptionGroupVersions", body: .document("subscriptionGroupVersions", required: "relationships")),
            .init("group-localizations", "GET", "v1/subscriptionGroupVersions/{version-id}/localizations", query: "fields[subscriptionGroupLocalizations] fields[subscriptionGroupVersions] limit include"),
            .init("group-localizations-ids", "GET", "v1/subscriptionGroupVersions/{version-id}/relationships/localizations", query: "limit"),
            .init("group-localization-create", "POST", "v2/subscriptionGroupLocalizations", body: .document("subscriptionGroupLocalizations", required: "attributes relationships")),
            .init("group-localization-get", "GET", "v2/subscriptionGroupLocalizations/{localization-id}", query: "fields[subscriptionGroupLocalizations] fields[subscriptionGroupVersions] include"),
            .init("group-localization-update", "PATCH", "v2/subscriptionGroupLocalizations/{localization-id}", body: .document("subscriptionGroupLocalizations", matchingID: true)),
            .init("group-localization-delete", "DELETE", "v2/subscriptionGroupLocalizations/{localization-id}"),
            .init("review-list", "GET", "v1/apps/{app-id}/reviewSubmissions", query: "filter[platform] filter[state] fields[reviewSubmissions] fields[apps] fields[reviewSubmissionItems] fields[appStoreVersions] fields[actors] limit include limit[items]"),
            .init("review-get", "GET", "v1/reviewSubmissions/{review-submission-id}", query: "fields[reviewSubmissions] fields[apps] fields[reviewSubmissionItems] fields[appStoreVersions] fields[actors] include limit[items]"),
            .init("review-items", "GET", "v1/reviewSubmissions/{review-submission-id}/items", query: "fields[reviewSubmissionItems] fields[appStoreVersions] fields[appCustomProductPageVersions] fields[appStoreVersionExperiments] fields[appEvents] fields[appAssetLibraryImages] fields[appAssetLibraryVideos] fields[backgroundAssetVersions] fields[gameCenterAchievementVersions] fields[gameCenterActivityVersions] fields[gameCenterChallengeVersions] fields[gameCenterLeaderboardSetVersions] fields[gameCenterLeaderboardVersions] fields[inAppPurchaseVersions] fields[subscriptionVersions] fields[subscriptionGroupVersions] fields[retentionMessageVersions] limit include"),
            .init("review-create", "POST", "v1/reviewSubmissions", body: .reviewCreate),
            .init("review-add", "POST", "v1/reviewSubmissionItems", body: .purchaseReviewAdd),
            .init("review-submit", "PATCH", "v1/reviewSubmissions/{review-submission-id}", body: .reviewSubmit),
        ],
    ]
}
