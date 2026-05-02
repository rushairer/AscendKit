import Foundation

public struct IntakeOptions: Codable, Equatable, Sendable {
    public var searchRoot: String
    public var explicitProjectPath: String?
    public var explicitWorkspacePath: String?
    public var releaseID: String?

    public init(
        searchRoot: String,
        explicitProjectPath: String? = nil,
        explicitWorkspacePath: String? = nil,
        releaseID: String? = nil
    ) {
        self.searchRoot = searchRoot
        self.explicitProjectPath = explicitProjectPath
        self.explicitWorkspacePath = explicitWorkspacePath
        self.releaseID = releaseID
    }
}

public struct IntakeReport: Codable, Equatable, Sendable {
    public var ascendKitVersion: String?
    public var manifest: ReleaseManifest
    public var warnings: [String]

    public init(
        ascendKitVersion: String? = AscendKitVersion.current,
        manifest: ReleaseManifest,
        warnings: [String] = []
    ) {
        self.ascendKitVersion = ascendKitVersion
        self.manifest = manifest
        self.warnings = warnings
    }
}

public struct ProjectDiscovery {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inspect(options: IntakeOptions) throws -> IntakeReport {
        let root = URL(fileURLWithPath: options.searchRoot).standardizedFileURL
        var warnings: [String] = []
        var projects = try discoverProjectReferences(options: options, root: root)

        if projects.isEmpty {
            warnings.append("No .xcodeproj or .xcworkspace was found under \(root.path).")
        }

        projects.sort { $0.path < $1.path }
        let projectTargets = try discoverTargets(from: projects)
        let appSlug = deriveAppSlug(projects: projects, root: root)
        let releaseID = options.releaseID ?? makeReleaseID(appSlug: appSlug, targets: projectTargets)

        let manifest = ReleaseManifest(
            releaseID: releaseID,
            appSlug: appSlug,
            projects: projects,
            targets: projectTargets,
            notes: warnings
        )
        return IntakeReport(manifest: manifest, warnings: warnings)
    }

    private func discoverProjectReferences(options: IntakeOptions, root: URL) throws -> [ProjectReference] {
        var references: [ProjectReference] = []
        if let explicitProjectPath = options.explicitProjectPath {
            references.append(ProjectReference(kind: .xcodeproj, path: URL(fileURLWithPath: explicitProjectPath).standardizedFileURL.path))
        }
        if let explicitWorkspacePath = options.explicitWorkspacePath {
            references.append(ProjectReference(kind: .xcworkspace, path: URL(fileURLWithPath: explicitWorkspacePath).standardizedFileURL.path))
        }
        guard references.isEmpty else { return references }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        for case let url as URL in enumerator {
            if shouldSkip(url: url, root: root) {
                enumerator.skipDescendants()
                continue
            }
            switch url.pathExtension {
            case "xcodeproj":
                references.append(ProjectReference(kind: .xcodeproj, path: url.standardizedFileURL.path))
                enumerator.skipDescendants()
            case "xcworkspace":
                references.append(ProjectReference(kind: .xcworkspace, path: url.standardizedFileURL.path))
                enumerator.skipDescendants()
            default:
                continue
            }
        }
        return references
    }

    private func shouldSkip(url: URL, root: URL) -> Bool {
        let rootComponents = Set(root.pathComponents)
        let components = url.pathComponents.filter { !rootComponents.contains($0) }
        let ignored = Set([".build", "DerivedData", "Pods", "Carthage", "vendor", "node_modules"])
        return components.contains { ignored.contains($0) }
    }

    private func discoverTargets(from projects: [ProjectReference]) throws -> [BundleTarget] {
        var targets: [BundleTarget] = []
        for project in projects where project.kind == .xcodeproj {
            let pbxproj = URL(fileURLWithPath: project.path)
                .appendingPathComponent("project.pbxproj")
            guard fileManager.fileExists(atPath: pbxproj.path) else { continue }
            let content = try String(contentsOf: pbxproj, encoding: .utf8)
            targets.append(contentsOf: PBXProjectScanner(content: content).scanTargets())
        }
        return uniqueTargets(targets)
    }

    private func uniqueTargets(_ targets: [BundleTarget]) -> [BundleTarget] {
        var seen = Set<String>()
        var result: [BundleTarget] = []
        for target in targets {
            let key = target.id
            if seen.insert(key).inserted {
                result.append(target)
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    private func deriveAppSlug(projects: [ProjectReference], root: URL) -> String {
        let source = projects.first.map { URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent }
            ?? root.lastPathComponent
        let slug = source
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
        return slug.isEmpty ? "release" : slug
    }

    private func makeReleaseID(appSlug: String, targets: [BundleTarget]) -> String {
        let version = targets.compactMap(\.version.marketingVersion).first
        let build = targets.compactMap(\.version.buildNumber).first
        if let version, let build {
            return "\(appSlug)-\(version)-b\(build)"
        }
        if let version {
            return "\(appSlug)-\(version)"
        }
        return appSlug
    }
}

struct PBXProjectScanner {
    var content: String

    func scanTargets() -> [BundleTarget] {
        let targets = scanNativeTargets()
        let configurationLists = scanConfigurationLists()
        let buildConfigurations = scanBuildConfigurations()

        return targets.map { target in
            let configurationIDs = configurationLists[target.configurationListID] ?? []
            let settings = preferredSettings(configurationIDs: configurationIDs, buildConfigurations: buildConfigurations)
            return makeTarget(name: target.name, productType: target.productType, settings: settings)
        }
    }

    private struct NativeTarget {
        var id: String
        var name: String
        var configurationListID: String
        var productType: String?
    }

    private struct BuildConfiguration {
        var id: String
        var name: String
        var settings: [String: String]
    }

    private func scanNativeTargets() -> [NativeTarget] {
        blocks(inSectionNamed: "PBXNativeTarget").compactMap { id, body in
            guard let name = firstValue("name", in: body),
                  let configurationList = firstTokenValue("buildConfigurationList", in: body) else {
                return nil
            }
            return NativeTarget(
                id: id,
                name: name,
                configurationListID: configurationList,
                productType: firstValue("productType", in: body)
            )
        }
    }

    private func scanConfigurationLists() -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: blocks(inSectionNamed: "XCConfigurationList").map { id, body in
            let ids = arrayValues("buildConfigurations", in: body)
            return (id, ids)
        })
    }

    private func scanBuildConfigurations() -> [String: BuildConfiguration] {
        Dictionary(uniqueKeysWithValues: blocks(inSectionNamed: "XCBuildConfiguration").map { id, body in
            let settingsBody = nestedDictionary("buildSettings", in: body) ?? ""
            let settings = [
                "PRODUCT_BUNDLE_IDENTIFIER": firstValue("PRODUCT_BUNDLE_IDENTIFIER", in: settingsBody),
                "MARKETING_VERSION": firstValue("MARKETING_VERSION", in: settingsBody),
                "CURRENT_PROJECT_VERSION": firstValue("CURRENT_PROJECT_VERSION", in: settingsBody),
                "INFOPLIST_FILE": firstValue("INFOPLIST_FILE", in: settingsBody),
                "ASSETCATALOG_COMPILER_APPICON_NAME": firstValue("ASSETCATALOG_COMPILER_APPICON_NAME", in: settingsBody),
                "CODE_SIGN_ENTITLEMENTS": firstValue("CODE_SIGN_ENTITLEMENTS", in: settingsBody),
                "SUPPORTED_PLATFORMS": firstValue("SUPPORTED_PLATFORMS", in: settingsBody)
            ].compactMapValues { $0 }
            return (id, BuildConfiguration(id: id, name: firstValue("name", in: body) ?? "", settings: settings))
        })
    }

    private func preferredSettings(
        configurationIDs: [String],
        buildConfigurations: [String: BuildConfiguration]
    ) -> [String: String] {
        let configurations = configurationIDs.compactMap { buildConfigurations[$0] }
        if let release = configurations.first(where: { $0.name == "Release" }) {
            return release.settings
        }
        if let configured = configurations.first(where: { $0.settings["PRODUCT_BUNDLE_IDENTIFIER"] != nil }) {
            return configured.settings
        }
        return configurations.first?.settings ?? [:]
    }

    private func makeTarget(name: String, productType: String?, settings: [String: String]) -> BundleTarget {
        BundleTarget(
            name: name,
            platform: inferPlatform(from: settings["SUPPORTED_PLATFORMS"]),
            bundleIdentifier: settings["PRODUCT_BUNDLE_IDENTIFIER"],
            version: VersionInfo(
                marketingVersion: settings["MARKETING_VERSION"],
                buildNumber: settings["CURRENT_PROJECT_VERSION"]
            ),
            infoPlistPath: settings["INFOPLIST_FILE"],
            appIconName: settings["ASSETCATALOG_COMPILER_APPICON_NAME"],
            entitlementsPath: settings["CODE_SIGN_ENTITLEMENTS"],
            productType: productType,
            isExtension: productType?.contains("app-extension") == true || settings["PRODUCT_BUNDLE_IDENTIFIER"]?.contains(".extension") == true
        )
    }

    private func inferPlatform(from value: String?) -> ApplePlatform {
        guard let value else { return .unknown }
        if value.contains("iphoneos") { return .iOS }
        if value.contains("macosx") { return .macOS }
        if value.contains("watchos") { return .watchOS }
        if value.contains("appletvos") { return .tvOS }
        if value.contains("xros") { return .visionOS }
        return .unknown
    }

    private func firstValue(_ key: String, in body: String) -> String? {
        let pattern = #"(?m)^\s*\#(key)\s*=\s*([^;]+);"#
        return matches(pattern: pattern, in: body).first.map { clean($0) }
    }

    private func firstTokenValue(_ key: String, in body: String) -> String? {
        firstValue(key, in: body)?.split(separator: " ").first.map(String.init)
    }

    private func arrayValues(_ key: String, in body: String) -> [String] {
        let pattern = #"\#(key)\s*=\s*\(([\s\S]*?)\);"#
        guard let arrayBody = matches(pattern: pattern, in: body).first else { return [] }
        return arrayBody
            .split(separator: "\n")
            .compactMap { line in
                line.split(separator: " ").first.map(String.init)
            }
            .map(clean)
            .filter { !$0.isEmpty && $0 != "(" && $0 != ")" }
    }

    private func nestedDictionary(_ key: String, in body: String) -> String? {
        let pattern = #"(?m)\#(key)\s*=\s*\{([\s\S]*?)^\s*\};"#
        return matches(pattern: pattern, in: body).first
    }

    private func blocks(inSectionNamed sectionName: String) -> [(id: String, body: String)] {
        guard let section = section(named: sectionName) else { return [] }
        var objects: [(id: String, body: String)] = []
        var currentID: String?
        var currentLines: [String] = []
        var depth = 0

        for line in section.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if currentID == nil, let id = objectID(fromStartLine: line) {
                currentID = id
                depth = braceDelta(in: line)
                currentLines = []
                if depth == 0 {
                    objects.append((id, ""))
                    currentID = nil
                }
                continue
            }

            guard let id = currentID else {
                continue
            }

            depth += braceDelta(in: line)
            if depth <= 0 {
                objects.append((id, currentLines.joined(separator: "\n")))
                currentID = nil
                currentLines = []
                depth = 0
            } else {
                currentLines.append(line)
            }
        }
        return objects
    }

    private func objectID(fromStartLine line: String) -> String? {
        let pattern = #"^\s*([A-Za-z0-9]+)(?: /\*.*?\*/)? = \{"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let idRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[idRange])
    }

    private func braceDelta(in line: String) -> Int {
        line.reduce(0) { result, character in
            if character == "{" { return result + 1 }
            if character == "}" { return result - 1 }
            return result
        }
    }

    private func section(named sectionName: String) -> String? {
        let start = "/* Begin \(sectionName) section */"
        let end = "/* End \(sectionName) section */"
        guard let startRange = content.range(of: start),
              let endRange = content.range(of: end, range: startRange.upperBound..<content.endIndex) else {
            return nil
        }
        return String(content[startRange.upperBound..<endRange.lowerBound])
    }

    private func matches(pattern: String, in source: String? = nil) -> [String] {
        let source = source ?? content
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: source) else {
                return nil
            }
            if match.numberOfRanges > 2,
               let valueRange = Range(match.range(at: 2), in: source) {
                return String(source[valueRange])
            }
            return String(source[matchRange])
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}
