import Foundation

public enum MetadataBundleKind: String, Codable, Equatable, Sendable {
    case source
    case localized
}

public struct MetadataBundleStatus: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(kind.rawValue)-\(locale)" }
    public var kind: MetadataBundleKind
    public var locale: String
    public var path: String
    public var lintFindingCount: Int?

    public init(kind: MetadataBundleKind, locale: String, path: String, lintFindingCount: Int? = nil) {
        self.kind = kind
        self.locale = locale
        self.path = path
        self.lintFindingCount = lintFindingCount
    }
}

public struct MetadataCatalog: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var bundles: [MetadataBundleStatus]

    public init(generatedAt: Date = Date(), bundles: [MetadataBundleStatus]) {
        self.generatedAt = generatedAt
        self.bundles = bundles
    }
}

public struct MetadataCatalogReader {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func read(workspace: ReleaseWorkspace) -> MetadataCatalog {
        let root = URL(fileURLWithPath: workspace.paths.root).appendingPathComponent("metadata")
        let source = bundles(kind: .source, directory: root.appendingPathComponent("source"), workspace: workspace)
        let localized = bundles(kind: .localized, directory: root.appendingPathComponent("localized"), workspace: workspace)
        return MetadataCatalog(bundles: (source + localized).sorted { lhs, rhs in
            if lhs.kind == rhs.kind { return lhs.locale < rhs.locale }
            return lhs.kind.rawValue < rhs.kind.rawValue
        })
    }

    private func bundles(kind: MetadataBundleKind, directory: URL, workspace: ReleaseWorkspace) -> [MetadataBundleStatus] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { $0.pathExtension == "json" }
            .map { url in
                let locale = url.deletingPathExtension().lastPathComponent
                return MetadataBundleStatus(
                    kind: kind,
                    locale: locale,
                    path: url.path,
                    lintFindingCount: lintFindingCount(locale: locale, workspace: workspace)
                )
            }
    }

    private func lintFindingCount(locale: String, workspace: ReleaseWorkspace) -> Int? {
        let lintURL = URL(fileURLWithPath: workspace.paths.root)
            .appendingPathComponent("metadata/lint")
            .appendingPathComponent("\(locale).json")
        guard fileManager.fileExists(atPath: lintURL.path),
              let data = try? Data(contentsOf: lintURL),
              let report = try? AscendKitJSON.decoder.decode(MetadataLintReport.self, from: data) else {
            return nil
        }
        return report.findings.count
    }
}
