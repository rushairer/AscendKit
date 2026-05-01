import Foundation

public struct EntitlementsInspector {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inspect(target: BundleTarget, projectReferences: [ProjectReference]) -> [DoctorFinding] {
        guard let entitlementsPath = target.entitlementsPath,
              !entitlementsPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let resolvedURL = resolve(entitlementsPath, projectReferences: projectReferences)
        guard fileManager.fileExists(atPath: resolvedURL.path) else {
            return [
                DoctorFinding(
                    id: "entitlements.\(target.name).not-found",
                    severity: .warning,
                    category: .capabilities,
                    title: "Entitlements file was not found for \(target.name)",
                    detail: "CODE_SIGN_ENTITLEMENTS points to \(resolvedURL.path), but the file does not exist.",
                    fixability: .suggested,
                    nextAction: "Verify CODE_SIGN_ENTITLEMENTS for the release configuration or restore the entitlements file."
                )
            ]
        }

        do {
            let data = try Data(contentsOf: resolvedURL)
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            let entitlements = object as? [String: Any] ?? [:]
            return findings(for: target, entitlements: entitlements, path: resolvedURL.path)
        } catch {
            return [
                DoctorFinding(
                    id: "entitlements.\(target.name).decode-failed",
                    severity: .error,
                    category: .capabilities,
                    title: "Entitlements file could not be decoded for \(target.name)",
                    detail: "Property list parsing failed for \(resolvedURL.path): \(error.localizedDescription)",
                    fixability: .suggested,
                    nextAction: "Open the entitlements file in Xcode and fix malformed plist content."
                )
            ]
        }
    }

    private func findings(for target: BundleTarget, entitlements: [String: Any], path: String) -> [DoctorFinding] {
        var findings: [DoctorFinding] = []

        if let environment = entitlements["aps-environment"] as? String {
            findings.append(.init(
                id: "entitlements.\(target.name).push-enabled",
                severity: environment == "production" ? .info : .warning,
                category: .capabilities,
                title: "Push notification entitlement is enabled for \(target.name)",
                detail: "aps-environment is \(environment) in \(path).",
                fixability: .detectOnly,
                nextAction: "Confirm App Store Connect capability state, APNs environment, and reviewer notes for push-dependent flows."
            ))
        }

        appendArrayCapabilityFinding(
            key: "com.apple.developer.associated-domains",
            title: "Associated Domains entitlement is enabled for \(target.name)",
            emptyTitle: "Associated Domains entitlement is empty for \(target.name)",
            target: target,
            entitlements: entitlements,
            findings: &findings
        )

        appendArrayCapabilityFinding(
            key: "com.apple.security.application-groups",
            title: "App Groups entitlement is enabled for \(target.name)",
            emptyTitle: "App Groups entitlement is empty for \(target.name)",
            target: target,
            entitlements: entitlements,
            findings: &findings
        )

        appendArrayCapabilityFinding(
            key: "com.apple.developer.icloud-container-identifiers",
            title: "iCloud container entitlement is enabled for \(target.name)",
            emptyTitle: "iCloud container entitlement is empty for \(target.name)",
            target: target,
            entitlements: entitlements,
            findings: &findings
        )

        if entitlements["com.apple.developer.healthkit"] != nil {
            findings.append(.init(
                id: "entitlements.\(target.name).healthkit-enabled",
                severity: .warning,
                category: .capabilities,
                title: "HealthKit entitlement is enabled for \(target.name)",
                detail: "HealthKit often requires careful privacy copy, reviewer context, and visible user value.",
                fixability: .detectOnly,
                nextAction: "Confirm HealthKit usage descriptions, App Privacy answers, and reviewer instructions are release-ready."
            ))
        }

        if entitlements["com.apple.developer.in-app-payments"] != nil {
            findings.append(.init(
                id: "entitlements.\(target.name).apple-pay-enabled",
                severity: .warning,
                category: .capabilities,
                title: "Apple Pay entitlement is enabled for \(target.name)",
                detail: "Apple Pay capability is present in entitlements.",
                fixability: .detectOnly,
                nextAction: "Confirm merchant identifiers, payment flows, and reviewer notes are ready for release review."
            ))
        }

        return findings
    }

    private func appendArrayCapabilityFinding(
        key: String,
        title: String,
        emptyTitle: String,
        target: BundleTarget,
        entitlements: [String: Any],
        findings: inout [DoctorFinding]
    ) {
        guard let values = entitlements[key] as? [String] else { return }
        let stableKey = key
            .replacingOccurrences(of: "com.apple.", with: "")
            .replacingOccurrences(of: "developer.", with: "")
            .replacingOccurrences(of: "security.", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")

        if values.isEmpty {
            findings.append(.init(
                id: "entitlements.\(target.name).\(stableKey).empty",
                severity: .error,
                category: .capabilities,
                title: emptyTitle,
                detail: "\(key) is present but has no configured values.",
                fixability: .suggested,
                nextAction: "Remove the entitlement or configure the release-ready values in Xcode."
            ))
        } else {
            findings.append(.init(
                id: "entitlements.\(target.name).\(stableKey).enabled",
                severity: .info,
                category: .capabilities,
                title: title,
                detail: "\(key) has \(values.count) configured value(s).",
                fixability: .detectOnly,
                nextAction: "Confirm the matching App Store Connect capability and production service configuration are ready."
            ))
        }
    }

    private func resolve(_ path: String, projectReferences: [ProjectReference]) -> URL {
        let expanded = path
            .replacingOccurrences(of: "$(SRCROOT)/", with: "")
            .replacingOccurrences(of: "${SRCROOT}/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if (expanded as NSString).isAbsolutePath {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        let projectRoot = projectReferences
            .first(where: { $0.kind == .xcodeproj })
            .map { URL(fileURLWithPath: $0.path).deletingLastPathComponent() }
            ?? URL(fileURLWithPath: fileManager.currentDirectoryPath)
        return projectRoot.appendingPathComponent(expanded).standardizedFileURL
    }
}
