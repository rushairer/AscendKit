import Foundation

public enum ASCCapabilityImplementationStatus: String, Codable, Equatable, Sendable {
    case planned
    case observationOnly
    case partial
    case implemented
    case verified
}

public struct ASCCapabilityNote: Codable, Equatable, Sendable {
    public var domain: String
    public var operation: String
    public var officialDocsURL: String?
    public var apiResource: String?
    public var status: ASCCapabilityImplementationStatus
    public var caveats: [String]
    public var fallbackStrategy: String
    public var lastVerified: String?

    public init(
        domain: String,
        operation: String,
        officialDocsURL: String? = nil,
        apiResource: String? = nil,
        status: ASCCapabilityImplementationStatus,
        caveats: [String] = [],
        fallbackStrategy: String,
        lastVerified: String? = nil
    ) {
        self.domain = domain
        self.operation = operation
        self.officialDocsURL = officialDocsURL
        self.apiResource = apiResource
        self.status = status
        self.caveats = caveats
        self.fallbackStrategy = fallbackStrategy
        self.lastVerified = lastVerified
    }
}

public struct BuildCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var version: String
    public var buildNumber: String
    public var processingState: String
    public var platform: String?

    public init(id: String, version: String, buildNumber: String, processingState: String, platform: String? = nil) {
        self.id = id
        self.version = version
        self.buildNumber = buildNumber
        self.processingState = processingState
        self.platform = platform
    }
}

public struct BuildCandidatesReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var source: String
    public var candidates: [BuildCandidate]

    public init(generatedAt: Date = Date(), source: String, candidates: [BuildCandidate]) {
        self.generatedAt = generatedAt
        self.source = source
        self.candidates = candidates
    }

    public var processableCandidates: [BuildCandidate] {
        candidates.filter { $0.processingState.lowercased() == "processed" || $0.processingState.lowercased() == "valid" }
    }

    public func preferredCandidate(version: String?, buildNumber: String?, platform: ApplePlatform? = nil) -> BuildCandidate? {
        let targetPlatform = platform.map(Self.ascPlatformValue)
        let candidates = processableCandidates.filter { candidate in
            guard let targetPlatform else { return true }
            return candidate.platform == nil || candidate.platform == targetPlatform
        }
        let exact = candidates.first {
            $0.version == version && $0.buildNumber == buildNumber
        }
        if let exact {
            return exact
        }
        let sameVersion = candidates.filter { candidate in
            guard let version, !version.isEmpty else { return true }
            return candidate.version == version
        }
        return sameVersion.max { lhs, rhs in
            (Int(lhs.buildNumber) ?? -1, lhs.buildNumber) < (Int(rhs.buildNumber) ?? -1, rhs.buildNumber)
        }
    }

    private static func ascPlatformValue(for platform: ApplePlatform) -> String {
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
}

public struct ASCAuthConfig: Codable, Equatable, Sendable {
    public var issuerID: String
    public var keyID: String
    public var privateKey: SecretRef

    public init(issuerID: String, keyID: String, privateKey: SecretRef) {
        self.issuerID = issuerID
        self.keyID = keyID
        self.privateKey = privateKey
    }
}

public struct ASCAuthStatus: Codable, Equatable, Sendable {
    public var configured: Bool
    public var issuerIDRedacted: String?
    public var keyIDRedacted: String?
    public var privateKeyRefRedacted: String?
    public var findings: [String]

    public init(config: ASCAuthConfig?) {
        guard let config else {
            self.configured = false
            self.issuerIDRedacted = nil
            self.keyIDRedacted = nil
            self.privateKeyRefRedacted = nil
            self.findings = ["ASC auth config is missing."]
            return
        }

        var findings: [String] = []
        if config.issuerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            findings.append("issuerID is empty.")
        }
        if config.keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            findings.append("keyID is empty.")
        }
        if config.privateKey.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            findings.append("privateKey secret reference is empty.")
        }

        self.configured = findings.isEmpty
        self.issuerIDRedacted = Redactor.redact(config.issuerID)
        self.keyIDRedacted = Redactor.redact(config.keyID)
        self.privateKeyRefRedacted = config.privateKey.redactedDescription
        self.findings = findings
    }
}

public struct ASCAuthProfile: Codable, Equatable, Sendable {
    public var name: String
    public var config: ASCAuthConfig
    public var createdAt: Date

    public init(name: String, config: ASCAuthConfig, createdAt: Date = Date()) {
        self.name = name
        self.config = config
        self.createdAt = createdAt
    }
}

public struct ASCAuthProfileStore {
    public let fileManager: FileManager
    public let root: URL

    public init(
        fileManager: FileManager = .default,
        root: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ascendkit/profiles/asc")
    ) {
        self.fileManager = fileManager
        self.root = root
    }

    public func save(_ profile: ASCAuthProfile) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try secureProfileDirectories()
        let url = profileURL(name: profile.name)
        let data = try AscendKitJSON.encoder.encode(profile)
        try data.write(to: url, options: [.atomic])
        try setOwnerReadWritePermissions(url)
        return url
    }

    public func load(name: String) throws -> ASCAuthProfile {
        let url = profileURL(name: name)
        guard fileManager.fileExists(atPath: url.path) else {
            throw AscendKitError.fileNotFound(url.path)
        }
        return try AscendKitJSON.decoder.decode(ASCAuthProfile.self, from: Data(contentsOf: url))
    }

    public func list() -> [ASCAuthProfile] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .filter { $0.pathExtension == "json" }
            .compactMap { try? AscendKitJSON.decoder.decode(ASCAuthProfile.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
    }

    private func profileURL(name: String) -> URL {
        root.appendingPathComponent("\(safeName(name)).json")
    }

    private func safeName(_ name: String) -> String {
        let safe = name
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" }
            .joined(separator: "-")
        return safe.isEmpty ? "default" : safe
    }

    private func setOwnerOnlyPermissions(_ url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func setOwnerReadWritePermissions(_ url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func secureProfileDirectories() throws {
        let components = root.standardizedFileURL.pathComponents
        guard let ascendKitIndex = components.firstIndex(of: ".ascendkit") else {
            try setOwnerOnlyPermissions(root)
            return
        }

        var directories: [URL] = []
        var currentPath = NSString.path(withComponents: Array(components.prefix(through: ascendKitIndex)))
        directories.append(URL(fileURLWithPath: currentPath))

        for component in components.dropFirst(ascendKitIndex + 1) {
            currentPath = (currentPath as NSString).appendingPathComponent(component)
            directories.append(URL(fileURLWithPath: currentPath))
        }

        for directory in directories.reversed() {
            if fileManager.fileExists(atPath: directory.path) {
                try setOwnerOnlyPermissions(directory)
            }
        }
    }
}

public enum ASCLookupStepKind: String, Codable, Equatable, Sendable {
    case listApps
    case listAppBuilds
}

public struct ASCLookupStep: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: ASCLookupStepKind
    public var method: String
    public var pathTemplate: String
    public var query: [String: String]
    public var purpose: String

    public init(
        id: String,
        kind: ASCLookupStepKind,
        method: String = "GET",
        pathTemplate: String,
        query: [String: String] = [:],
        purpose: String
    ) {
        self.id = id
        self.kind = kind
        self.method = method
        self.pathTemplate = pathTemplate
        self.query = query
        self.purpose = purpose
    }
}

public struct ASCLookupPlan: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var releaseID: String
    public var bundleIDs: [String]
    public var version: String?
    public var buildNumber: String?
    public var requiresAuth: Bool
    public var authConfigured: Bool
    public var dryRunOnly: Bool
    public var steps: [ASCLookupStep]
    public var capabilityNotes: [ASCCapabilityNote]
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        releaseID: String,
        bundleIDs: [String],
        version: String?,
        buildNumber: String?,
        requiresAuth: Bool = true,
        authConfigured: Bool,
        dryRunOnly: Bool = true,
        steps: [ASCLookupStep],
        capabilityNotes: [ASCCapabilityNote],
        findings: [String]
    ) {
        self.generatedAt = generatedAt
        self.releaseID = releaseID
        self.bundleIDs = bundleIDs
        self.version = version
        self.buildNumber = buildNumber
        self.requiresAuth = requiresAuth
        self.authConfigured = authConfigured
        self.dryRunOnly = dryRunOnly
        self.steps = steps
        self.capabilityNotes = capabilityNotes
        self.findings = findings
    }
}

public struct ASCLookupPlanBuilder {
    public init() {}

    public func build(manifest: ReleaseManifest, authStatus: ASCAuthStatus) -> ASCLookupPlan {
        let releaseTargets = manifest.targets.filter(\.isAppStoreApplication)
        let bundleIDs = Array(Set(releaseTargets.compactMap(\.bundleIdentifier))).sorted()
        let version = releaseTargets.compactMap(\.version.marketingVersion).first
        let buildNumber = releaseTargets.compactMap(\.version.buildNumber).first
        var findings: [String] = []

        if bundleIDs.isEmpty {
            findings.append("No release bundle identifier is available for ASC app lookup.")
        }
        if version == nil {
            findings.append("No marketing version is available for build filtering.")
        }
        if buildNumber == nil {
            findings.append("No build number is available for build filtering.")
        }
        if !authStatus.configured {
            findings.append(contentsOf: authStatus.findings)
        }

        let appFilter = bundleIDs.isEmpty ? "" : bundleIDs.joined(separator: ",")
        let steps: [ASCLookupStep] = [
            ASCLookupStep(
                id: "apps.lookup-by-bundle-id",
                kind: .listApps,
                pathTemplate: "/v1/apps",
                query: appFilter.isEmpty ? [:] : ["filter[bundleId]": appFilter],
                purpose: "Find the App Store Connect app resource matching the release bundle identifier."
            ),
            ASCLookupStep(
                id: "builds.lookup-for-app",
                kind: .listAppBuilds,
                pathTemplate: "/v1/apps/{id}/builds",
                query: buildQuery(version: version, buildNumber: buildNumber),
                purpose: "Observe Xcode Cloud or Transporter-produced build resources for the intended release version/build."
            )
        ]

        return ASCLookupPlan(
            releaseID: manifest.releaseID,
            bundleIDs: bundleIDs,
            version: version,
            buildNumber: buildNumber,
            authConfigured: authStatus.configured,
            steps: steps,
            capabilityNotes: [
                ASCCapabilityNote(
                    domain: "app lookup",
                    operation: "List Apps",
                    officialDocsURL: "https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps",
                    apiResource: "GET /v1/apps",
                    status: .observationOnly,
                    caveats: ["Plan only; no network request is executed by this command."],
                    fallbackStrategy: "Record the App Store Connect app/build state manually with local import commands."
                ),
                ASCCapabilityNote(
                    domain: "build lookup",
                    operation: "List All Builds of an App",
                    officialDocsURL: "https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-builds",
                    apiResource: "GET /v1/apps/{id}/builds",
                    status: .observationOnly,
                    caveats: ["Build upload, signing, and submission execution remain outside this dry-run planning command."],
                    fallbackStrategy: "Use Xcode Cloud/App Store Connect for binary delivery, then import selected build candidates locally."
                )
            ],
            findings: findings
        )
    }

    private func buildQuery(version: String?, buildNumber: String?) -> [String: String] {
        var query: [String: String] = [:]
        if let version {
            query["filter[preReleaseVersion.version]"] = version
        }
        if let buildNumber {
            query["filter[version]"] = buildNumber
        }
        return query
    }
}

public struct ASCObservedApp: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String?
    public var bundleID: String?
    public var sku: String?
    public var primaryLocale: String?

    public init(id: String, name: String? = nil, bundleID: String? = nil, sku: String? = nil, primaryLocale: String? = nil) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.sku = sku
        self.primaryLocale = primaryLocale
    }
}

public struct ASCAppsLookupReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var source: String
    public var bundleIDs: [String]
    public var apps: [ASCObservedApp]
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        source: String = "app-store-connect-api",
        bundleIDs: [String],
        apps: [ASCObservedApp],
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.source = source
        self.bundleIDs = bundleIDs
        self.apps = apps
        self.findings = findings
    }
}
