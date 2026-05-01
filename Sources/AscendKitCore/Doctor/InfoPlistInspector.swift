import Foundation

public struct InfoPlistInspectionResult: Codable, Equatable, Sendable {
    public var targetName: String
    public var path: String
    public var findings: [DoctorFinding]

    public init(targetName: String, path: String, findings: [DoctorFinding]) {
        self.targetName = targetName
        self.path = path
        self.findings = findings
    }
}

public struct InfoPlistInspector {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inspect(target: BundleTarget, projectReferences: [ProjectReference]) -> InfoPlistInspectionResult? {
        guard let infoPlistPath = target.infoPlistPath, !infoPlistPath.isEmpty else {
            return InfoPlistInspectionResult(
                targetName: target.name,
                path: "",
                findings: [
                    DoctorFinding(
                        id: "plist.\(target.name).missing-path",
                        severity: .warning,
                        category: .privacy,
                        title: "Info.plist path was not detected for \(target.name)",
                        detail: "Release-sensitive plist checks were skipped for this target.",
                        nextAction: "Set INFOPLIST_FILE or provide a manifest with the Info.plist path."
                    )
                ]
            )
        }

        let resolvedURL = resolve(infoPlistPath, projectReferences: projectReferences)
        guard fileManager.fileExists(atPath: resolvedURL.path) else {
            return InfoPlistInspectionResult(
                targetName: target.name,
                path: resolvedURL.path,
                findings: [
                    DoctorFinding(
                        id: "plist.\(target.name).not-found",
                        severity: .warning,
                        category: .privacy,
                        title: "Info.plist not found for \(target.name)",
                        detail: "Expected Info.plist at \(resolvedURL.path).",
                        nextAction: "Verify INFOPLIST_FILE or regenerate intake with the correct project root."
                    )
                ]
            )
        }

        do {
            let data = try Data(contentsOf: resolvedURL)
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            let plist = object as? [String: Any] ?? [:]
            return InfoPlistInspectionResult(
                targetName: target.name,
                path: resolvedURL.path,
                findings: findings(for: target, plist: plist, projectReferences: projectReferences)
            )
        } catch {
            return InfoPlistInspectionResult(
                targetName: target.name,
                path: resolvedURL.path,
                findings: [
                    DoctorFinding(
                        id: "plist.\(target.name).decode-failed",
                        severity: .error,
                        category: .privacy,
                        title: "Info.plist could not be decoded for \(target.name)",
                        detail: "Property list parsing failed: \(error.localizedDescription)",
                        nextAction: "Open the plist in Xcode and fix malformed content."
                    )
                ]
            )
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

    private func findings(for target: BundleTarget, plist: [String: Any], projectReferences: [ProjectReference]) -> [DoctorFinding] {
        var findings: [DoctorFinding] = []

        if plist["ITSAppUsesNonExemptEncryption"] == nil {
            findings.append(DoctorFinding(
                id: "plist.\(target.name).encryption-key-missing",
                severity: .warning,
                category: .exportCompliance,
                title: "Encryption export compliance key is not set for \(target.name)",
                detail: "ITSAppUsesNonExemptEncryption was not present. AscendKit cannot infer compliance truth from source alone.",
                fixability: .requiresConfirmation,
                nextAction: "Confirm the app's encryption posture before adding or changing this key."
            ))
        }

        let privacyKeys = plist.keys.filter { $0.hasPrefix("NS") && $0.hasSuffix("UsageDescription") }
        for key in privacyKeys {
            let value = plist[key] as? String ?? ""
            if isPlaceholder(value) {
                findings.append(DoctorFinding(
                    id: "plist.\(target.name).\(key).placeholder",
                    severity: .error,
                    category: .privacy,
                    title: "Placeholder privacy usage description in \(target.name)",
                    detail: "\(key) is empty or appears generic.",
                    fixability: .suggested,
                    nextAction: "Replace the usage description with a user-facing explanation of why the app needs access."
                ))
            }
        }

        if plist["CFBundleDisplayName"] == nil && plist["CFBundleName"] == nil {
            findings.append(DoctorFinding(
                id: "plist.\(target.name).display-name-missing",
                severity: .info,
                category: .metadata,
                title: "No display name key found for \(target.name)",
                detail: "Neither CFBundleDisplayName nor CFBundleName was present in Info.plist.",
                fixability: .suggested,
                nextAction: "Confirm the final app display name is supplied by build settings or plist."
            ))
        }

        findings.append(contentsOf: missingPrivacyPurposeFindings(
            target: target,
            plist: plist,
            projectReferences: projectReferences
        ))

        return findings
    }

    private func missingPrivacyPurposeFindings(
        target: BundleTarget,
        plist: [String: Any],
        projectReferences: [ProjectReference]
    ) -> [DoctorFinding] {
        let source = privacySignalSource(projectReferences: projectReferences)
        guard !source.isEmpty else { return [] }

        let rules: [PrivacyPurposeRule] = [
            .init(
                requiredAnyKey: ["NSCameraUsageDescription"],
                signalTerms: ["AVCaptureDevice", "AVCaptureSession", "UIImagePickerController.SourceType.camera", ".camera"],
                capabilityName: "camera"
            ),
            .init(
                requiredAnyKey: ["NSMicrophoneUsageDescription"],
                signalTerms: ["AVAudioRecorder", "AVAudioEngine", "requestRecordPermission", "AVCaptureDevice.default(for: .audio)"],
                capabilityName: "microphone"
            ),
            .init(
                requiredAnyKey: ["NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription"],
                signalTerms: ["PHPhotoLibrary", "PhotosPicker", "UIImagePickerController.SourceType.photoLibrary", ".photoLibrary"],
                capabilityName: "photo library"
            ),
            .init(
                requiredAnyKey: ["NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription", "NSLocationAlwaysUsageDescription"],
                signalTerms: ["CLLocationManager", "requestWhenInUseAuthorization", "requestAlwaysAuthorization"],
                capabilityName: "location"
            ),
            .init(
                requiredAnyKey: ["NSContactsUsageDescription"],
                signalTerms: ["CNContactStore", "ContactsUI"],
                capabilityName: "contacts"
            ),
            .init(
                requiredAnyKey: ["NSCalendarsUsageDescription", "NSCalendarsFullAccessUsageDescription", "NSCalendarsWriteOnlyAccessUsageDescription"],
                signalTerms: ["EKEventStore", "requestAccess(to: .event"],
                capabilityName: "calendar"
            ),
            .init(
                requiredAnyKey: ["NSRemindersUsageDescription", "NSRemindersFullAccessUsageDescription"],
                signalTerms: ["requestAccess(to: .reminder"],
                capabilityName: "reminders"
            ),
            .init(
                requiredAnyKey: ["NSBluetoothAlwaysUsageDescription", "NSBluetoothPeripheralUsageDescription"],
                signalTerms: ["CBCentralManager", "CBPeripheralManager", "CoreBluetooth"],
                capabilityName: "Bluetooth"
            )
        ]

        return rules.compactMap { rule in
            guard rule.signalTerms.contains(where: { source.contains($0) }),
                  !rule.requiredAnyKey.contains(where: { plist[$0] != nil }) else {
                return nil
            }
            return DoctorFinding(
                id: "plist.\(target.name).\(rule.stableID).usage-description-missing",
                severity: .error,
                category: .privacy,
                title: "Possible missing \(rule.capabilityName) usage description in \(target.name)",
                detail: "Source contains \(rule.capabilityName)-related API signals, but none of \(rule.requiredAnyKey.joined(separator: ", ")) were found in Info.plist.",
                fixability: .requiresConfirmation,
                nextAction: "Confirm the release build reaches this API path, then add a user-facing purpose string if needed."
            )
        }
    }

    private struct PrivacyPurposeRule {
        var requiredAnyKey: [String]
        var signalTerms: [String]
        var capabilityName: String

        var stableID: String {
            capabilityName
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .joined(separator: "-")
        }
    }

    private func privacySignalSource(projectReferences: [ProjectReference]) -> String {
        let roots = Set(projectReferences.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent() })
        var snippets: [String] = []
        for root in roots {
            snippets.append(contentsOf: sourceSnippets(root: root))
        }
        return snippets.joined(separator: "\n")
    }

    private func sourceSnippets(root: URL) -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var snippets: [String] = []
        for case let url as URL in enumerator {
            if shouldSkip(url: url) {
                enumerator.skipDescendants()
                continue
            }
            guard isPrivacyScannableSource(url),
                  let data = try? Data(contentsOf: url),
                  data.count <= 512_000,
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }
            snippets.append(content)
            if snippets.count >= 200 {
                break
            }
        }
        return snippets
    }

    private func isPrivacyScannableSource(_ url: URL) -> Bool {
        let allowedExtensions = Set(["swift", "m", "mm", "h", "plist", "strings"])
        return allowedExtensions.contains(url.pathExtension.lowercased())
    }

    private func shouldSkip(url: URL) -> Bool {
        let ignored = Set([".build", "DerivedData", "Pods", "Carthage", "vendor", "node_modules", ".git"])
        return url.pathComponents.contains { ignored.contains($0) }
    }

    private func isPlaceholder(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lowercased = trimmed.lowercased()
        return ["todo", "tbd", "placeholder", "privacy reason", "usage description"].contains {
            lowercased.contains($0)
        }
    }
}
