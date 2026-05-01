import Foundation

public struct AssetCatalogInspector {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inspect(target: BundleTarget, projectReferences: [ProjectReference]) -> [DoctorFinding] {
        guard target.isReleaseApplication else { return [] }

        guard let appIconName = target.appIconName, !appIconName.isEmpty else {
            return [
                DoctorFinding(
                    id: "assets.\(target.name).app-icon-setting-missing",
                    severity: .warning,
                    category: .assets,
                    title: "App icon build setting is missing for \(target.name)",
                    detail: "ASSETCATALOG_COMPILER_APPICON_NAME was not detected for this release target.",
                    fixability: .suggested,
                    nextAction: "Set the app icon asset name in the target's asset catalog build settings."
                )
            ]
        }

        let projectRoot = projectReferences
            .first(where: { $0.kind == .xcodeproj })
            .map { URL(fileURLWithPath: $0.path).deletingLastPathComponent() }
            ?? URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let appIconSetName = appIconName.hasSuffix(".appiconset") ? appIconName : "\(appIconName).appiconset"
        let appIconBundleName = appIconName.hasSuffix(".icon") ? appIconName : "\(appIconName).icon"
        let appIconSets = findDirectories(named: appIconSetName, under: projectRoot)
        let appIconBundles = findDirectories(named: appIconBundleName, under: projectRoot)

        guard let appIconDirectory = appIconSets.first ?? appIconBundles.first else {
            return [
                DoctorFinding(
                    id: "assets.\(target.name).app-icon-missing",
                    severity: .blocker,
                    category: .assets,
                    title: "App icon asset set was not found for \(target.name)",
                    detail: "Expected to find \(appIconSetName) or \(appIconBundleName) under the project directory.",
                    fixability: .suggested,
                    nextAction: "Create the app icon set in an asset catalog or update ASSETCATALOG_COMPILER_APPICON_NAME."
                )
            ]
        }

        let legacyContents = appIconDirectory.appendingPathComponent("Contents.json")
        let iconContents = appIconDirectory.appendingPathComponent("icon.json")
        if !fileManager.fileExists(atPath: legacyContents.path) && !fileManager.fileExists(atPath: iconContents.path) {
            return [
                DoctorFinding(
                    id: "assets.\(target.name).app-icon-contents-missing",
                    severity: .error,
                    category: .assets,
                    title: "App icon Contents.json is missing for \(target.name)",
                    detail: "Found \(appIconDirectory.path), but neither Contents.json nor icon.json was present.",
                    fixability: .suggested,
                    nextAction: "Repair the app icon asset set in Xcode."
                )
            ]
        }

        return []
    }

    private func findDirectories(named directoryName: String, under root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var matches: [URL] = []
        for case let url as URL in enumerator {
            if shouldSkip(url: url) {
                enumerator.skipDescendants()
                continue
            }
            if url.lastPathComponent == directoryName {
                matches.append(url)
                enumerator.skipDescendants()
            }
        }
        return matches
    }

    private func shouldSkip(url: URL) -> Bool {
        let ignored = Set([".build", "DerivedData", "Pods", "Carthage", "vendor", "node_modules"])
        return url.pathComponents.contains { ignored.contains($0) }
    }
}
