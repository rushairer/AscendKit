import Foundation

public enum PPOJSONValue: Codable, Equatable, Sendable {
    case object([String: PPOJSONValue])
    case array([PPOJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([PPOJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: PPOJSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public subscript(key: String) -> PPOJSONValue? {
        guard case .object(let values) = self else { return nil }
        return values[key]
    }
}

public enum PPOAction: String, Codable, CaseIterable, Sendable {
    case list, get, create, update, start, stop, delete, treatments, localizations, screenshots, promote
    case treatmentCreate = "treatment-create"
    case treatmentUpdate = "treatment-update"
    case treatmentDelete = "treatment-delete"
    case localizationCreate = "localization-create"
    case localizationDelete = "localization-delete"
    case screenshotSets = "screenshot-sets"
    case screenshotSetCreate = "screenshot-set-create"
    case screenshotUpload = "screenshot-upload"
    case screenshotDelete = "screenshot-delete"
    case screenshotOrder = "screenshot-order"
    case screenshotOrderByPrefix = "screenshot-order-by-prefix"
    case reviewCreate = "review-create"
    case reviewGet = "review-get"
    case reviewItems = "review-items"
    case reviewAdd = "review-add"
    case reviewSubmit = "review-submit"
}

public struct PPOPlan: Encodable, Equatable, Sendable {
    public let action: PPOAction
    public let method: String
    public let path: String
    public let payload: PPOJSONValue?
    public let sourcePath: String?
    public let screenshotSetID: String?
    public let requiresSubmissionConfirmation: Bool

    public var mutatesRemote: Bool { method != "GET" }
}

public struct PPOResult: Encodable, Sendable {
    public let plan: PPOPlan
    public let executed: Bool
    public let responses: [PPOJSONValue]
    public let upload: ScreenshotUploadExecutionItem?
    public let findings: [String]

    public init(plan: PPOPlan, executed: Bool, responses: [PPOJSONValue] = [], upload: ScreenshotUploadExecutionItem? = nil, findings: [String] = []) {
        self.plan = plan
        self.executed = executed
        self.responses = responses
        self.upload = upload
        self.findings = findings
    }
}

public struct PPOPlanner: Sendable {
    public init() {}

    public func plan(action: PPOAction, options: [String: String]) throws -> PPOPlan {
        func required(_ key: String) throws -> String {
            guard let value = options[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AscendKitError.invalidArguments("PPO \(action.rawValue) requires --\(key).")
            }
            return value
        }
        func identifier(_ key: String) throws -> String {
            let value = try required(key)
            guard value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0) }) else {
                throw AscendKitError.invalidArguments("Invalid PPO --\(key): expected an ASC resource ID.")
            }
            return value
        }
        func relationship(_ key: String, _ type: String, _ id: String) -> [String: PPOJSONValue] {
            [key: .object(["data": .object(["type": .string(type), "id": .string(id)])])]
        }
        func traffic() throws -> PPOJSONValue {
            guard let value = Int(try required("traffic-proportion")), (1...100).contains(value) else {
                throw AscendKitError.invalidArguments("PPO --traffic-proportion must be an integer from 1 to 100.")
            }
            return .number(Double(value))
        }
        func platform() throws -> PPOJSONValue {
            let value = options["platform"] ?? "IOS"
            guard value == "IOS" else {
                throw AscendKitError.invalidArguments("Product page optimization supports IOS; use --platform IOS.")
            }
            return .string(value)
        }

        var method = "GET"
        var path: String
        var type: String?
        var resourceID: String?
        var attributes: [String: PPOJSONValue] = [:]
        var relationships: [String: PPOJSONValue] = [:]
        var sourcePath: String?
        var screenshotSetID: String?
        var customPayload: PPOJSONValue?
        var allowed = Set<String>()

        switch action {
        case .list:
            allowed = ["app-id"]
            path = "v1/apps/\(try identifier("app-id"))/appStoreVersionExperimentsV2"
        case .get, .update, .start, .stop, .delete:
            allowed = ["experiment-id"]
            resourceID = try identifier("experiment-id")
            path = "v2/appStoreVersionExperiments/\(resourceID!)"
            type = "appStoreVersionExperiments"
            if action == .delete { method = "DELETE" }
            if action == .start || action == .stop {
                method = "PATCH"
                attributes["started"] = .bool(action == .start)
            }
            if action == .update {
                allowed.formUnion(["name", "traffic-proportion"])
                method = "PATCH"
                if options["name"] != nil { attributes["name"] = .string(try required("name")) }
                if options["traffic-proportion"] != nil { attributes["trafficProportion"] = try traffic() }
                guard !attributes.isEmpty else { throw AscendKitError.invalidArguments("PPO update requires --name or --traffic-proportion.") }
            }
        case .create:
            allowed = ["app-id", "name", "platform", "traffic-proportion"]
            method = "POST"
            path = "v2/appStoreVersionExperiments"
            type = "appStoreVersionExperiments"
            attributes = ["name": .string(try required("name")), "platform": try platform(), "trafficProportion": try traffic()]
            relationships = relationship("app", "apps", try identifier("app-id"))
        case .treatments:
            allowed = ["experiment-id"]
            path = "v2/appStoreVersionExperiments/\(try identifier("experiment-id"))/appStoreVersionExperimentTreatments"
        case .treatmentCreate, .treatmentUpdate, .treatmentDelete:
            allowed = action == .treatmentCreate ? ["experiment-id", "name", "icon-name"] : ["treatment-id"]
            type = "appStoreVersionExperimentTreatments"
            if action == .treatmentCreate {
                method = "POST"
                path = "v1/appStoreVersionExperimentTreatments"
                relationships = relationship("appStoreVersionExperimentV2", "appStoreVersionExperiments", try identifier("experiment-id"))
                attributes["name"] = .string(try required("name"))
            } else {
                resourceID = try identifier("treatment-id")
                path = "v1/appStoreVersionExperimentTreatments/\(resourceID!)"
                method = action == .treatmentDelete ? "DELETE" : "PATCH"
            }
            if action != .treatmentDelete {
                allowed.formUnion(["name", "icon-name"])
                if options["name"] != nil { attributes["name"] = .string(try required("name")) }
                if options["icon-name"] != nil { attributes["appIconName"] = .string(try required("icon-name")) }
                guard !attributes.isEmpty else { throw AscendKitError.invalidArguments("PPO treatment-update requires --name or --icon-name.") }
            }
        case .localizations:
            allowed = ["treatment-id"]
            path = "v1/appStoreVersionExperimentTreatments/\(try identifier("treatment-id"))/appStoreVersionExperimentTreatmentLocalizations"
        case .localizationCreate:
            allowed = ["treatment-id", "locale"]
            method = "POST"
            path = "v1/appStoreVersionExperimentTreatmentLocalizations"
            type = "appStoreVersionExperimentTreatmentLocalizations"
            attributes = ["locale": .string(try required("locale"))]
            relationships = relationship("appStoreVersionExperimentTreatment", "appStoreVersionExperimentTreatments", try identifier("treatment-id"))
        case .localizationDelete:
            allowed = ["localization-id"]
            method = "DELETE"
            path = "v1/appStoreVersionExperimentTreatmentLocalizations/\(try identifier("localization-id"))"
        case .screenshotSets:
            allowed = ["localization-id"]
            path = "v1/appStoreVersionExperimentTreatmentLocalizations/\(try identifier("localization-id"))/appScreenshotSets"
        case .screenshotSetCreate:
            allowed = ["localization-id", "display-type"]
            method = "POST"
            path = "v1/appScreenshotSets"
            type = "appScreenshotSets"
            attributes = ["screenshotDisplayType": .string(try required("display-type"))]
            relationships = relationship("appStoreVersionExperimentTreatmentLocalization", "appStoreVersionExperimentTreatmentLocalizations", try identifier("localization-id"))
        case .screenshots:
            allowed = ["set-id"]
            path = "v1/appScreenshotSets/\(try identifier("set-id"))/appScreenshots"
        case .screenshotUpload:
            allowed = ["set-id", "file"]
            method = "POST"
            path = "v1/appScreenshots"
            screenshotSetID = try identifier("set-id")
            sourcePath = URL(fileURLWithPath: try required("file")).standardizedFileURL.path
            _ = try ScreenshotImageSanitizer.opaquePNGData(from: URL(fileURLWithPath: sourcePath!))
            relationships = relationship("appScreenshotSet", "appScreenshotSets", screenshotSetID!)
        case .screenshotDelete:
            allowed = ["screenshot-id"]
            method = "DELETE"
            path = "v1/appScreenshots/\(try identifier("screenshot-id"))"
        case .screenshotOrder:
            allowed = ["set-id", "screenshot-ids"]
            method = "PATCH"
            path = "v1/appScreenshotSets/\(try identifier("set-id"))/relationships/appScreenshots"
            let ids = try required("screenshot-ids").split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard !ids.isEmpty, Set(ids).count == ids.count else {
                throw AscendKitError.invalidArguments("PPO --screenshot-ids requires a nonempty list of unique screenshot IDs in the desired order.")
            }
            for id in ids {
                guard !id.isEmpty, id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0) }) else {
                    throw AscendKitError.invalidArguments("Invalid PPO screenshot ID: \(id)")
                }
            }
            customPayload = .object(["data": .array(ids.map { .object(["type": .string("appScreenshots"), "id": .string($0)]) })])
        case .screenshotOrderByPrefix:
            allowed = ["set-id", "localization-id", "prefixes"]
            method = "PATCH"
            screenshotSetID = try identifier("set-id")
            _ = try identifier("localization-id")
            path = "v1/appScreenshotSets/\(screenshotSetID!)/relationships/appScreenshots"
            let prefixes = try required("prefixes").split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard !prefixes.isEmpty, Set(prefixes).count == prefixes.count,
                  prefixes.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
                throw AscendKitError.invalidArguments("PPO --prefixes requires unique numeric filename prefixes, comma-separated in the desired order.")
            }
            customPayload = .object([
                "localizationID": .string(options["localization-id"]!),
                "prefixes": .array(prefixes.map(PPOJSONValue.string))
            ])
        case .reviewCreate:
            allowed = ["app-id", "platform"]
            method = "POST"
            path = "v1/reviewSubmissions"
            type = "reviewSubmissions"
            attributes = ["platform": try platform()]
            relationships = relationship("app", "apps", try identifier("app-id"))
        case .reviewGet, .reviewItems, .reviewSubmit:
            allowed = ["review-submission-id"]
            resourceID = try identifier("review-submission-id")
            path = "v1/reviewSubmissions/\(resourceID!)"
            if action == .reviewItems { path += "/items" }
            if action == .reviewSubmit {
                method = "PATCH"
                type = "reviewSubmissions"
                attributes = ["submitted": .bool(true)]
            }
        case .reviewAdd:
            allowed = ["review-submission-id", "experiment-id"]
            method = "POST"
            path = "v1/reviewSubmissionItems"
            type = "reviewSubmissionItems"
            relationships = relationship("reviewSubmission", "reviewSubmissions", try identifier("review-submission-id"))
            relationships.merge(relationship("appStoreVersionExperimentV2", "appStoreVersionExperiments", try identifier("experiment-id"))) { _, value in value }
        case .promote:
            allowed = ["version-id", "treatment-id"]
            method = "POST"
            path = "v1/appStoreVersionPromotions"
            type = "appStoreVersionPromotions"
            relationships = relationship("appStoreVersion", "appStoreVersions", try identifier("version-id"))
            relationships.merge(relationship("appStoreVersionExperimentTreatment", "appStoreVersionExperimentTreatments", try identifier("treatment-id"))) { _, value in value }
        }

        let unexpected = Set(options.keys).subtracting(allowed)
        guard unexpected.isEmpty else {
            throw AscendKitError.invalidArguments("Unsupported PPO \(action.rawValue) options: \(unexpected.sorted().map { "--\($0)" }.joined(separator: ", ")).")
        }
        var payload = customPayload
        if method == "POST" || method == "PATCH", let type {
            var data: [String: PPOJSONValue] = ["type": .string(type)]
            if let resourceID { data["id"] = .string(resourceID) }
            if !attributes.isEmpty { data["attributes"] = .object(attributes) }
            if !relationships.isEmpty { data["relationships"] = .object(relationships) }
            payload = .object(["data": .object(data)])
        }
        return PPOPlan(action: action, method: method, path: path, payload: payload, sourcePath: sourcePath, screenshotSetID: screenshotSetID, requiresSubmissionConfirmation: action == .reviewSubmit)
    }
}
