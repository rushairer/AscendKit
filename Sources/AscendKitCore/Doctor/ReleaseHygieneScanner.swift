import Foundation

public struct ReleaseHygieneScanner {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(projectReferences: [ProjectReference]) -> [DoctorFinding] {
        let roots = Set(projectReferences.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent() })
        return roots.flatMap(scanRoot(_:))
    }

    private func scanRoot(_ root: URL) -> [DoctorFinding] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var findings: [DoctorFinding] = []
        for case let url as URL in enumerator {
            if shouldSkip(url: url) {
                enumerator.skipDescendants()
                continue
            }
            guard isScannableTextFile(url),
                  let data = try? Data(contentsOf: url),
                  data.count <= 512_000,
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }
            findings.append(contentsOf: findingsForContent(content, fileURL: url, root: root))
        }
        return Array(findings.prefix(25))
    }

    private func findingsForContent(_ content: String, fileURL: URL, root: URL) -> [DoctorFinding] {
        let lowercased = content.lowercased()
        let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
        var findings: [DoctorFinding] = []

        let stagingSignals = ["localhost", "127.0.0.1", "staging.", "dev.", "debug banner", "qa-only"]
        if stagingSignals.contains(where: { lowercased.contains($0) }) {
            findings.append(DoctorFinding(
                id: "hygiene.\(stableID(relativePath)).staging-residue",
                severity: .warning,
                category: .submission,
                title: "Possible staging or debug residue",
                detail: "Release-facing source contains staging/debug-like text in \(relativePath).",
                fixability: .detectOnly,
                nextAction: "Review the file and confirm no staging endpoint, debug overlay, or QA-only text can reach release builds."
            ))
        }

        let placeholderSignals = ["todo:", "fixme:", "lorem ipsum", "placeholder"]
        if placeholderSignals.contains(where: { lowercased.contains($0) }) {
            findings.append(DoctorFinding(
                id: "hygiene.\(stableID(relativePath)).placeholder-text",
                severity: .info,
                category: .submission,
                title: "Possible placeholder text",
                detail: "Source contains placeholder-like text in \(relativePath).",
                fixability: .detectOnly,
                nextAction: "Confirm placeholder text is not visible in release metadata, screenshots, or review-facing flows."
            ))
        }

        return findings
    }

    private func isScannableTextFile(_ url: URL) -> Bool {
        let allowedExtensions = Set(["swift", "plist", "json", "strings", "md", "txt", "xcconfig", "entitlements"])
        return allowedExtensions.contains(url.pathExtension.lowercased())
    }

    private func shouldSkip(url: URL) -> Bool {
        let ignored = Set([".build", "DerivedData", "Pods", "Carthage", "vendor", "node_modules", ".git"])
        return url.pathComponents.contains { ignored.contains($0) }
    }

    private func stableID(_ value: String) -> String {
        value
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(6)
            .joined(separator: "-")
    }
}
