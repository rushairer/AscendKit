import Foundation

public struct AppMetadata: Codable, Equatable, Sendable {
    public var locale: String
    public var name: String
    public var subtitle: String?
    public var promotionalText: String?
    public var description: String
    public var releaseNotes: String?
    public var keywords: [String]
    public var supportURL: String?
    public var marketingURL: String?
    public var privacyPolicyURL: String?

    public init(
        locale: String = "en-US",
        name: String,
        subtitle: String? = nil,
        promotionalText: String? = nil,
        description: String,
        releaseNotes: String? = nil,
        keywords: [String] = [],
        supportURL: String? = nil,
        marketingURL: String? = nil,
        privacyPolicyURL: String? = nil
    ) {
        self.locale = locale
        self.name = name
        self.subtitle = subtitle
        self.promotionalText = promotionalText
        self.description = description
        self.releaseNotes = releaseNotes
        self.keywords = keywords
        self.supportURL = supportURL
        self.marketingURL = marketingURL
        self.privacyPolicyURL = privacyPolicyURL
    }

    public static let template = AppMetadata(
        name: "App Name",
        subtitle: "Short value proposition",
        promotionalText: nil,
        description: "Describe the app's core value, primary audience, and most important features.",
        releaseNotes: "Describe what changed in this release.",
        keywords: [],
        supportURL: nil,
        marketingURL: nil,
        privacyPolicyURL: nil
    )
}

public enum MetadataLintSeverity: String, Codable, Equatable, Sendable {
    case warning
    case error
}

public struct MetadataLintFinding: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var severity: MetadataLintSeverity
    public var field: String
    public var message: String

    public init(id: String, severity: MetadataLintSeverity, field: String, message: String) {
        self.id = id
        self.severity = severity
        self.field = field
        self.message = message
    }

    public var doctorFinding: DoctorFinding {
        DoctorFinding(
            id: "metadata.\(id)",
            severity: severity == .error ? .error : .warning,
            category: .metadata,
            title: "Metadata \(field) issue",
            detail: message,
            fixability: .suggested
        )
    }
}

public struct MetadataLintReport: Codable, Equatable, Sendable {
    public var locale: String
    public var generatedAt: Date
    public var findings: [MetadataLintFinding]

    public init(locale: String, generatedAt: Date = Date(), findings: [MetadataLintFinding]) {
        self.locale = locale
        self.generatedAt = generatedAt
        self.findings = findings
    }
}

public struct MetadataLinter {
    public init() {}

    public func lint(metadata: AppMetadata) -> MetadataLintReport {
        var findings: [MetadataLintFinding] = []
        checkRequired(metadata.name, field: "name", id: "name.required", findings: &findings)
        checkMax(metadata.name, max: 30, field: "name", id: "name.too-long", findings: &findings)
        checkMax(metadata.subtitle, max: 30, field: "subtitle", id: "subtitle.too-long", findings: &findings)
        checkMax(metadata.promotionalText, max: 170, field: "promotionalText", id: "promotional-text.too-long", findings: &findings)
        checkRequired(metadata.description, field: "description", id: "description.required", findings: &findings)
        checkMax(metadata.description, max: 4_000, field: "description", id: "description.too-long", findings: &findings)
        checkOptionalRequired(metadata.releaseNotes, field: "releaseNotes", id: "release-notes.required", findings: &findings)
        checkMax(metadata.releaseNotes, max: 4_000, field: "releaseNotes", id: "release-notes.too-long", findings: &findings)

        let keywordString = metadata.keywords.joined(separator: ",")
        checkMax(keywordString, max: 100, field: "keywords", id: "keywords.too-long", findings: &findings)
        checkPlaceholderSignals(in: metadata, findings: &findings)

        for (field, value) in [
            ("supportURL", metadata.supportURL),
            ("marketingURL", metadata.marketingURL),
            ("privacyPolicyURL", metadata.privacyPolicyURL)
        ] {
            if let value, !value.isEmpty, URL(string: value)?.scheme == nil {
                findings.append(.init(
                    id: "\(field).invalid-url",
                    severity: .warning,
                    field: field,
                    message: "\(field) should be an absolute URL."
                ))
            }
        }

        return MetadataLintReport(locale: metadata.locale, findings: findings)
    }

    private func checkRequired(_ value: String, field: String, id: String, findings: inout [MetadataLintFinding]) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            findings.append(.init(id: id, severity: .error, field: field, message: "\(field) is required."))
        }
    }

    private func checkOptionalRequired(_ value: String?, field: String, id: String, findings: inout [MetadataLintFinding]) {
        if value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            findings.append(.init(id: id, severity: .warning, field: field, message: "\(field) should be prepared for release review."))
        }
    }

    private func checkMax(_ value: String?, max: Int, field: String, id: String, findings: inout [MetadataLintFinding]) {
        guard let value, value.count > max else { return }
        findings.append(.init(
            id: id,
            severity: .error,
            field: field,
            message: "\(field) is \(value.count) characters; maximum is \(max)."
        ))
    }

    private func checkPlaceholderSignals(in metadata: AppMetadata, findings: inout [MetadataLintFinding]) {
        let fields: [(String, String?)] = [
            ("name", metadata.name),
            ("subtitle", metadata.subtitle),
            ("promotionalText", metadata.promotionalText),
            ("description", metadata.description),
            ("releaseNotes", metadata.releaseNotes),
            ("keywords", metadata.keywords.joined(separator: ","))
        ]
        let suspiciousTerms = ["todo", "tbd", "lorem ipsum", "placeholder", "test app", "staging"]
        for (field, value) in fields {
            let lowercased = value?.lowercased() ?? ""
            if suspiciousTerms.contains(where: { lowercased.contains($0) }) {
                findings.append(.init(
                    id: "\(field).placeholder",
                    severity: .warning,
                    field: field,
                    message: "\(field) contains placeholder or staging-like wording."
                ))
            }
        }
    }
}

public struct FastlaneMetadataImporter {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadAll(from root: URL) throws -> [AppMetadata] {
        guard let localeDirectories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AscendKitError.fileNotFound(root.path)
        }

        return try localeDirectories.compactMap { localeDirectory in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: localeDirectory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }
            return try load(locale: localeDirectory.lastPathComponent, from: localeDirectory)
        }
        .sorted { $0.locale < $1.locale }
    }

    public func load(locale: String, from directory: URL) throws -> AppMetadata {
        AppMetadata(
            locale: locale,
            name: readTrimmed("name.txt", in: directory) ?? "",
            subtitle: readTrimmed("subtitle.txt", in: directory),
            promotionalText: readTrimmed("promotional_text.txt", in: directory),
            description: readTrimmed("description.txt", in: directory) ?? "",
            releaseNotes: readTrimmed("release_notes.txt", in: directory),
            keywords: (readTrimmed("keywords.txt", in: directory) ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            supportURL: readTrimmed("support_url.txt", in: directory),
            marketingURL: readTrimmed("marketing_url.txt", in: directory),
            privacyPolicyURL: readTrimmed("privacy_url.txt", in: directory)
        )
    }

    private func readTrimmed(_ fileName: String, in directory: URL) -> String? {
        let url = directory.appendingPathComponent(fileName)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
