import Foundation

public struct MetadataObservedState: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var source: String
    public var appInfoID: String?
    public var appStoreVersionID: String?
    public var appStoreVersionPlatform: String?
    public var metadataByLocale: [String: AppMetadata]
    public var resourceIDsByLocale: [String: MetadataLocalizationResourceIDs]?
    public var screenshotSetsByLocale: [String: [ObservedScreenshotSet]]?

    public init(
        generatedAt: Date = Date(),
        source: String = "local-observation",
        appInfoID: String? = nil,
        appStoreVersionID: String? = nil,
        appStoreVersionPlatform: String? = nil,
        metadataByLocale: [String: AppMetadata],
        resourceIDsByLocale: [String: MetadataLocalizationResourceIDs]? = nil,
        screenshotSetsByLocale: [String: [ObservedScreenshotSet]]? = nil
    ) {
        self.generatedAt = generatedAt
        self.source = source
        self.appInfoID = appInfoID
        self.appStoreVersionID = appStoreVersionID
        self.appStoreVersionPlatform = appStoreVersionPlatform
        self.metadataByLocale = metadataByLocale
        self.resourceIDsByLocale = resourceIDsByLocale
        self.screenshotSetsByLocale = screenshotSetsByLocale
    }
}

public struct ObservedScreenshotSet: Codable, Equatable, Sendable {
    public var id: String
    public var displayType: String
    public var screenshots: [ObservedScreenshot]

    public init(id: String, displayType: String, screenshots: [ObservedScreenshot] = []) {
        self.id = id
        self.displayType = displayType
        self.screenshots = screenshots
    }
}

public struct ObservedScreenshot: Codable, Equatable, Sendable {
    public var id: String
    public var fileName: String?
    public var assetDeliveryState: String?

    public init(id: String, fileName: String? = nil, assetDeliveryState: String? = nil) {
        self.id = id
        self.fileName = fileName
        self.assetDeliveryState = assetDeliveryState
    }
}

public struct MetadataLocalizationResourceIDs: Codable, Equatable, Sendable {
    public var appInfoLocalizationID: String?
    public var appStoreVersionLocalizationID: String?

    public init(appInfoLocalizationID: String? = nil, appStoreVersionLocalizationID: String? = nil) {
        self.appInfoLocalizationID = appInfoLocalizationID
        self.appStoreVersionLocalizationID = appStoreVersionLocalizationID
    }
}

public enum MetadataDiffStatus: String, Codable, Equatable, Sendable {
    case missingRemote
    case missingLocal
    case changed
    case unchanged
}

public struct MetadataFieldDiff: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(locale).\(field)" }
    public var locale: String
    public var field: String
    public var status: MetadataDiffStatus
    public var localValue: String?
    public var remoteValue: String?

    public init(locale: String, field: String, status: MetadataDiffStatus, localValue: String?, remoteValue: String?) {
        self.locale = locale
        self.field = field
        self.status = status
        self.localValue = localValue
        self.remoteValue = remoteValue
    }
}

public struct MetadataDiffReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var diffs: [MetadataFieldDiff]

    public init(generatedAt: Date = Date(), diffs: [MetadataFieldDiff]) {
        self.generatedAt = generatedAt
        self.diffs = diffs
    }

    public var changedCount: Int {
        diffs.filter { $0.status != .unchanged }.count
    }
}

public enum ASCMetadataResourceKind: String, Codable, Equatable, Hashable, Sendable {
    case appInfoLocalization
    case appStoreVersionLocalization
}

public enum ASCMetadataPlanAction: String, Codable, Equatable, Hashable, Sendable {
    case createLocalization
    case updateField
}

public struct ASCMetadataPlanOperation: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(locale).\(resourceKind.rawValue).\(field)" }
    public var locale: String
    public var field: String
    public var resourceKind: ASCMetadataResourceKind
    public var action: ASCMetadataPlanAction
    public var resourceID: String?
    public var parentResourceID: String?
    public var localValue: String
    public var remoteValue: String?

    public init(
        locale: String,
        field: String,
        resourceKind: ASCMetadataResourceKind,
        action: ASCMetadataPlanAction,
        resourceID: String? = nil,
        parentResourceID: String? = nil,
        localValue: String,
        remoteValue: String? = nil
    ) {
        self.locale = locale
        self.field = field
        self.resourceKind = resourceKind
        self.action = action
        self.resourceID = resourceID
        self.parentResourceID = parentResourceID
        self.localValue = localValue
        self.remoteValue = remoteValue
    }
}

public struct ASCMetadataMutationPlan: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var dryRunOnly: Bool
    public var operations: [ASCMetadataPlanOperation]
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        dryRunOnly: Bool = true,
        operations: [ASCMetadataPlanOperation],
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.dryRunOnly = dryRunOnly
        self.operations = operations
        self.findings = findings
    }
}

public struct ASCMetadataPlannedRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var method: String
    public var path: String
    public var resourceKind: ASCMetadataResourceKind
    public var action: ASCMetadataPlanAction
    public var locale: String
    public var resourceID: String?
    public var parentResourceID: String?
    public var relationshipName: String?
    public var attributes: [String: String]

    public init(
        id: String,
        method: String,
        path: String,
        resourceKind: ASCMetadataResourceKind,
        action: ASCMetadataPlanAction,
        locale: String,
        resourceID: String? = nil,
        parentResourceID: String? = nil,
        relationshipName: String? = nil,
        attributes: [String: String]
    ) {
        self.id = id
        self.method = method
        self.path = path
        self.resourceKind = resourceKind
        self.action = action
        self.locale = locale
        self.resourceID = resourceID
        self.parentResourceID = parentResourceID
        self.relationshipName = relationshipName
        self.attributes = attributes
    }
}

public struct ASCMetadataRequestPlan: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var dryRunOnly: Bool
    public var requests: [ASCMetadataPlannedRequest]
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        dryRunOnly: Bool = true,
        requests: [ASCMetadataPlannedRequest],
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.dryRunOnly = dryRunOnly
        self.requests = requests
        self.findings = findings
    }
}

public struct ASCMetadataApplyResult: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var applied: Bool
    public var responses: [ASCMetadataApplyResponse]
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        applied: Bool,
        responses: [ASCMetadataApplyResponse] = [],
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.applied = applied
        self.responses = responses
        self.findings = findings
    }
}

public struct ASCMetadataApplyResponse: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var method: String
    public var path: String
    public var statusCode: Int
    public var responseResourceID: String?

    public init(
        id: String,
        method: String,
        path: String,
        statusCode: Int,
        responseResourceID: String? = nil
    ) {
        self.id = id
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.responseResourceID = responseResourceID
    }
}

public struct ASCMetadataStatusReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var applied: Bool?
    public var applyResponseCount: Int?
    public var diffFresh: Bool?
    public var remainingDiffCount: Int?
    public var blockingDiffCount: Int?
    public var releaseNotesOnlyDiff: Bool
    public var readyForReviewPlan: Bool
    public var findings: [String]
    public var nextActions: [String]

    public init(
        generatedAt: Date = Date(),
        applied: Bool?,
        applyResponseCount: Int?,
        diffFresh: Bool?,
        remainingDiffCount: Int?,
        blockingDiffCount: Int?,
        releaseNotesOnlyDiff: Bool,
        readyForReviewPlan: Bool,
        findings: [String],
        nextActions: [String]
    ) {
        self.generatedAt = generatedAt
        self.applied = applied
        self.applyResponseCount = applyResponseCount
        self.diffFresh = diffFresh
        self.remainingDiffCount = remainingDiffCount
        self.blockingDiffCount = blockingDiffCount
        self.releaseNotesOnlyDiff = releaseNotesOnlyDiff
        self.readyForReviewPlan = readyForReviewPlan
        self.findings = findings
        self.nextActions = nextActions
    }
}

public struct ASCMetadataStatusBuilder {
    public init() {}

    public func build(
        applyResult: ASCMetadataApplyResult?,
        diffReport: MetadataDiffReport?
    ) -> ASCMetadataStatusReport {
        let remainingDiffs = diffReport?.diffs.filter { $0.status != .unchanged }
        let blockingDiffs = remainingDiffs?.filter { $0.field != "releaseNotes" }
        let releaseNotesOnly = remainingDiffs?.isEmpty == false && blockingDiffs?.isEmpty == true
        let diffFresh = Self.diffIsFresh(applyResult: applyResult, diffReport: diffReport)

        var findings: [String] = []
        var nextActions: [String] = []

        if applyResult?.applied != true {
            findings.append("ASC metadata apply has not completed.")
            nextActions.append("Run asc metadata plan, asc metadata requests, then asc metadata apply --confirm-remote-mutation.")
        }
        if applyResult?.applied == true && diffReport == nil {
            findings.append("ASC metadata diff has not been observed after metadata apply.")
            nextActions.append("Run asc metadata observe, then metadata diff.")
        }
        if diffFresh == false {
            findings.append("ASC metadata diff is older than the latest metadata apply.")
            nextActions.append("Run asc metadata observe, then metadata diff.")
        }
        if let blockingDiffs, !blockingDiffs.isEmpty {
            findings.append("\(blockingDiffs.count) blocking metadata diff(s) remain.")
            nextActions.append("Inspect asc/diff.json, then rerun asc metadata plan/requests/apply or edit local metadata.")
        }
        if releaseNotesOnly {
            findings.append("Only releaseNotes/whatsNew remains different; App Store Connect may reject first-version or non-editable whatsNew edits.")
            nextActions.append("Proceed with review handoff if all other readiness checks are satisfied.")
        }

        return ASCMetadataStatusReport(
            applied: applyResult?.applied,
            applyResponseCount: applyResult?.responses.count,
            diffFresh: diffFresh,
            remainingDiffCount: remainingDiffs?.count,
            blockingDiffCount: blockingDiffs?.count,
            releaseNotesOnlyDiff: releaseNotesOnly,
            readyForReviewPlan: applyResult?.applied == true && diffFresh == true && (blockingDiffs?.isEmpty == true),
            findings: findings + (applyResult?.findings ?? []),
            nextActions: deduplicated(nextActions)
        )
    }

    private static func diffIsFresh(applyResult: ASCMetadataApplyResult?, diffReport: MetadataDiffReport?) -> Bool? {
        guard let applyResult, applyResult.applied else {
            return nil
        }
        guard let diffReport else {
            return nil
        }
        return diffReport.generatedAt >= applyResult.generatedAt
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

public struct ASCMetadataRequestPlanBuilder {
    public init() {}

    public func build(from plan: ASCMetadataMutationPlan) -> ASCMetadataRequestPlan {
        var findings = plan.findings
        let groups = Dictionary(grouping: plan.operations) { operation in
            RequestGroupKey(
                locale: operation.locale,
                resourceKind: operation.resourceKind,
                action: operation.action,
                resourceID: operation.resourceID,
                parentResourceID: operation.parentResourceID
            )
        }
        let requests = groups.compactMap { key, operations -> ASCMetadataPlannedRequest? in
            let attributes = Dictionary(uniqueKeysWithValues: operations.compactMap { operation -> (String, String)? in
                if operation.field == "releaseNotes" {
                    findings.append("releaseNotes for \(operation.locale) is omitted from ASC metadata requests because App Store Connect may reject whatsNew for first-version or non-editable states.")
                    return nil
                }
                guard let apiField = apiFieldName(for: operation.field) else { return nil }
                return (apiField, operation.localValue)
            })
            guard !attributes.isEmpty else { return nil }

            switch key.action {
            case .updateField:
                guard let resourceID = key.resourceID else {
                    findings.append("Cannot plan metadata update for \(key.locale) \(key.resourceKind.rawValue): missing resource id.")
                    return nil
                }
                return ASCMetadataPlannedRequest(
                    id: "\(key.locale).\(key.resourceKind.rawValue).patch",
                    method: "PATCH",
                    path: "/v1/\(resourceType(for: key.resourceKind))/\(resourceID)",
                    resourceKind: key.resourceKind,
                    action: key.action,
                    locale: key.locale,
                    resourceID: resourceID,
                    attributes: attributes
                )
            case .createLocalization:
                guard let parentResourceID = key.parentResourceID else {
                    findings.append("Cannot plan metadata localization creation for \(key.locale) \(key.resourceKind.rawValue): missing parent resource id.")
                    return nil
                }
                var createAttributes = attributes
                createAttributes["locale"] = key.locale
                return ASCMetadataPlannedRequest(
                    id: "\(key.locale).\(key.resourceKind.rawValue).post",
                    method: "POST",
                    path: "/v1/\(resourceType(for: key.resourceKind))",
                    resourceKind: key.resourceKind,
                    action: key.action,
                    locale: key.locale,
                    parentResourceID: parentResourceID,
                    relationshipName: relationshipName(for: key.resourceKind),
                    attributes: createAttributes
                )
            }
        }
        .sorted { $0.id < $1.id }

        return ASCMetadataRequestPlan(requests: requests, findings: findings)
    }

    private func resourceType(for kind: ASCMetadataResourceKind) -> String {
        switch kind {
        case .appInfoLocalization:
            return "appInfoLocalizations"
        case .appStoreVersionLocalization:
            return "appStoreVersionLocalizations"
        }
    }

    private func relationshipName(for kind: ASCMetadataResourceKind) -> String {
        switch kind {
        case .appInfoLocalization:
            return "appInfo"
        case .appStoreVersionLocalization:
            return "appStoreVersion"
        }
    }

    private func apiFieldName(for field: String) -> String? {
        switch field {
        case "name", "subtitle", "description", "keywords", "promotionalText":
            return field
        case "privacyPolicyURL":
            return "privacyPolicyUrl"
        case "marketingURL":
            return "marketingUrl"
        case "supportURL":
            return "supportUrl"
        case "releaseNotes":
            return "whatsNew"
        default:
            return nil
        }
    }

    private struct RequestGroupKey: Hashable {
        var locale: String
        var resourceKind: ASCMetadataResourceKind
        var action: ASCMetadataPlanAction
        var resourceID: String?
        var parentResourceID: String?
    }
}

public struct ASCMetadataMutationPlanner {
    public init() {}

    public func plan(local: [AppMetadata], observed: MetadataObservedState?) -> ASCMetadataMutationPlan {
        let diff = MetadataDiffEngine().diff(local: local, observed: observed)
        let operations = diff.diffs.compactMap { fieldDiff -> ASCMetadataPlanOperation? in
            guard fieldDiff.status == .missingRemote || fieldDiff.status == .changed,
                  let localValue = fieldDiff.localValue,
                  let resourceKind = resourceKind(for: fieldDiff.field) else {
                return nil
            }
            let resourceID = resourceID(locale: fieldDiff.locale, kind: resourceKind, observed: observed)
            return ASCMetadataPlanOperation(
                locale: fieldDiff.locale,
                field: fieldDiff.field,
                resourceKind: resourceKind,
                action: resourceID == nil ? .createLocalization : .updateField,
                resourceID: resourceID,
                parentResourceID: resourceID == nil ? parentResourceID(kind: resourceKind, observed: observed) : nil,
                localValue: localValue,
                remoteValue: fieldDiff.remoteValue
            )
        }
        .sorted {
            ($0.locale, $0.resourceKind.rawValue, $0.field) < ($1.locale, $1.resourceKind.rawValue, $1.field)
        }

        var findings: [String] = []
        if observed == nil {
            findings.append("No ASC observed metadata state was available; plan assumes all local metadata needs remote creation.")
        }

        return ASCMetadataMutationPlan(operations: operations, findings: findings)
    }

    private func resourceKind(for field: String) -> ASCMetadataResourceKind? {
        switch field {
        case "name", "subtitle", "privacyPolicyURL":
            return .appInfoLocalization
        case "description", "keywords", "marketingURL", "promotionalText", "releaseNotes", "supportURL":
            return .appStoreVersionLocalization
        default:
            return nil
        }
    }

    private func resourceID(
        locale: String,
        kind: ASCMetadataResourceKind,
        observed: MetadataObservedState?
    ) -> String? {
        let ids = observed?.resourceIDsByLocale?[locale]
        switch kind {
        case .appInfoLocalization:
            return ids?.appInfoLocalizationID
        case .appStoreVersionLocalization:
            return ids?.appStoreVersionLocalizationID
        }
    }

    private func parentResourceID(kind: ASCMetadataResourceKind, observed: MetadataObservedState?) -> String? {
        switch kind {
        case .appInfoLocalization:
            return observed?.appInfoID
        case .appStoreVersionLocalization:
            return observed?.appStoreVersionID
        }
    }
}

public struct MetadataDiffEngine {
    public init() {}

    public func diff(local: [AppMetadata], observed: MetadataObservedState?) -> MetadataDiffReport {
        let localByLocale = Dictionary(uniqueKeysWithValues: local.map { ($0.locale, $0) })
        let remoteByLocale = observed?.metadataByLocale ?? [:]
        let locales = Set(localByLocale.keys).union(remoteByLocale.keys).sorted()
        var diffs: [MetadataFieldDiff] = []

        for locale in locales {
            let localFields = localByLocale[locale]?.diffFields ?? [:]
            let remoteFields = remoteByLocale[locale]?.diffFields ?? [:]
            let fields = Set(localFields.keys).union(remoteFields.keys).sorted()
            for field in fields {
                let localValue = localFields[field]
                let remoteValue = remoteFields[field]
                let status: MetadataDiffStatus
                if localValue == nil {
                    status = .missingLocal
                } else if remoteValue == nil {
                    status = .missingRemote
                } else if localValue == remoteValue {
                    status = .unchanged
                } else {
                    status = .changed
                }
                diffs.append(MetadataFieldDiff(
                    locale: locale,
                    field: field,
                    status: status,
                    localValue: localValue,
                    remoteValue: remoteValue
                ))
            }
        }

        return MetadataDiffReport(diffs: diffs)
    }
}

private extension AppMetadata {
    var diffFields: [String: String] {
        [
            "name": name,
            "subtitle": subtitle,
            "promotionalText": promotionalText,
            "description": description,
            "releaseNotes": releaseNotes,
            "keywords": keywords.joined(separator: ","),
            "supportURL": supportURL,
            "marketingURL": marketingURL,
            "privacyPolicyURL": privacyPolicyURL
        ].compactMapValues { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == true ? nil : trimmed
        }
    }
}
