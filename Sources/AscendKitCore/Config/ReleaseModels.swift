import Foundation

public enum ApplePlatform: String, Codable, CaseIterable, Equatable, Sendable {
    case iOS
    case iPadOS
    case macOS
    case watchOS
    case tvOS
    case visionOS
    case unknown
}

public struct VersionInfo: Codable, Equatable, Sendable {
    public var marketingVersion: String?
    public var buildNumber: String?

    public init(marketingVersion: String? = nil, buildNumber: String? = nil) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
    }
}

public struct BundleTarget: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(name)|\(bundleIdentifier ?? "unknown")" }
    public var name: String
    public var platform: ApplePlatform
    public var bundleIdentifier: String?
    public var version: VersionInfo
    public var infoPlistPath: String?
    public var appIconName: String?
    public var entitlementsPath: String?
    public var productType: String?
    public var isExtension: Bool
    public var isTestBundle: Bool {
        productType?.contains("unit-test") == true || productType?.contains("ui-testing") == true
    }
    public var isReleaseApplication: Bool {
        if isTestBundle { return false }
        guard let productType else { return !isExtension }
        return productType == "com.apple.product-type.application" || productType.contains("app-extension")
    }
    public var isAppStoreApplication: Bool {
        if isTestBundle || isExtension { return false }
        guard let productType else { return true }
        return productType == "com.apple.product-type.application"
    }

    public init(
        name: String,
        platform: ApplePlatform = .unknown,
        bundleIdentifier: String? = nil,
        version: VersionInfo = VersionInfo(),
        infoPlistPath: String? = nil,
        appIconName: String? = nil,
        entitlementsPath: String? = nil,
        productType: String? = nil,
        isExtension: Bool = false
    ) {
        self.name = name
        self.platform = platform
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.infoPlistPath = infoPlistPath
        self.appIconName = appIconName
        self.entitlementsPath = entitlementsPath
        self.productType = productType
        self.isExtension = isExtension
    }
}

public struct ProjectReference: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case xcodeproj
        case xcworkspace
    }

    public var kind: Kind
    public var path: String

    public init(kind: Kind, path: String) {
        self.kind = kind
        self.path = path
    }
}

public struct ReleaseManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var releaseID: String
    public var createdAt: Date
    public var appSlug: String
    public var projects: [ProjectReference]
    public var targets: [BundleTarget]
    public var notes: [String]

    public init(
        schemaVersion: Int = 1,
        releaseID: String,
        createdAt: Date = Date(),
        appSlug: String,
        projects: [ProjectReference],
        targets: [BundleTarget],
        notes: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.releaseID = releaseID
        self.createdAt = createdAt
        self.appSlug = appSlug
        self.projects = projects
        self.targets = targets
        self.notes = notes
    }
}
