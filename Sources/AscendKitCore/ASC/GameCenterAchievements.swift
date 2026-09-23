import Foundation

public enum GameCenterAchievementTargetKind: String, Codable, Equatable, Sendable {
    case group
    case detail
}

public struct GameCenterAchievementTarget: Codable, Equatable, Sendable {
    public var kind: GameCenterAchievementTargetKind
    public var id: String

    public init(kind: GameCenterAchievementTargetKind, id: String) {
        self.kind = kind
        self.id = id
    }
}

public struct GameCenterAchievementCatalog: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var achievements: [GameCenterAchievementDefinition]

    public init(schemaVersion: Int = 1, achievements: [GameCenterAchievementDefinition]) {
        self.schemaVersion = schemaVersion
        self.achievements = achievements
    }

    public func validate() throws {
        guard schemaVersion == 1 else {
            throw AscendKitError.invalidArguments("Unsupported Game Center achievement catalog schemaVersion \(schemaVersion); expected 1.")
        }

        var vendorIdentifiers = Set<String>()
        for achievement in achievements {
            let vendorIdentifier = achievement.vendorIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let referenceName = achievement.referenceName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !vendorIdentifier.isEmpty else {
                throw AscendKitError.invalidArguments("Game Center achievement vendorIdentifier must not be empty.")
            }
            guard vendorIdentifiers.insert(vendorIdentifier).inserted else {
                throw AscendKitError.invalidArguments("Duplicate Game Center achievement vendorIdentifier: \(vendorIdentifier)")
            }
            guard !referenceName.isEmpty else {
                throw AscendKitError.invalidArguments("Game Center achievement \(vendorIdentifier) has an empty referenceName.")
            }
            guard achievement.points >= 0 else {
                throw AscendKitError.invalidArguments("Game Center achievement \(vendorIdentifier) has negative points.")
            }

            var locales = Set<String>()
            for localization in achievement.localizations {
                let locale = localization.locale.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !locale.isEmpty else {
                    throw AscendKitError.invalidArguments("Game Center achievement \(vendorIdentifier) has a localization with an empty locale.")
                }
                guard locales.insert(locale).inserted else {
                    throw AscendKitError.invalidArguments("Game Center achievement \(vendorIdentifier) has duplicate localization locale \(locale).")
                }
                guard !localization.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AscendKitError.invalidArguments("Game Center achievement \(vendorIdentifier) localization \(locale) has an empty name.")
                }
            }
        }
    }
}

public struct GameCenterAchievementDefinition: Codable, Equatable, Sendable {
    public var referenceName: String
    public var vendorIdentifier: String
    public var points: Int
    public var showBeforeEarned: Bool
    public var repeatable: Bool
    public var localizations: [GameCenterAchievementLocalizationDefinition]

    public init(
        referenceName: String,
        vendorIdentifier: String,
        points: Int,
        showBeforeEarned: Bool = true,
        repeatable: Bool = false,
        localizations: [GameCenterAchievementLocalizationDefinition] = []
    ) {
        self.referenceName = referenceName
        self.vendorIdentifier = vendorIdentifier
        self.points = points
        self.showBeforeEarned = showBeforeEarned
        self.repeatable = repeatable
        self.localizations = localizations
    }
}

public struct GameCenterAchievementLocalizationDefinition: Codable, Equatable, Sendable {
    public var locale: String
    public var name: String
    public var beforeEarnedDescription: String
    public var afterEarnedDescription: String

    public init(
        locale: String,
        name: String,
        beforeEarnedDescription: String,
        afterEarnedDescription: String
    ) {
        self.locale = locale
        self.name = name
        self.beforeEarnedDescription = beforeEarnedDescription
        self.afterEarnedDescription = afterEarnedDescription
    }
}

public struct GameCenterAchievementObserved: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var referenceName: String?
    public var vendorIdentifier: String?
    public var points: Int?
    public var showBeforeEarned: Bool?
    public var repeatable: Bool?
    public var archived: Bool?

    public init(
        id: String,
        referenceName: String? = nil,
        vendorIdentifier: String? = nil,
        points: Int? = nil,
        showBeforeEarned: Bool? = nil,
        repeatable: Bool? = nil,
        archived: Bool? = nil
    ) {
        self.id = id
        self.referenceName = referenceName
        self.vendorIdentifier = vendorIdentifier
        self.points = points
        self.showBeforeEarned = showBeforeEarned
        self.repeatable = repeatable
        self.archived = archived
    }
}

public struct GameCenterAchievementVersionObserved: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var state: String?
    public var version: Int?

    public init(id: String, state: String? = nil, version: Int? = nil) {
        self.id = id
        self.state = state
        self.version = version
    }

    public var isEditable: Bool {
        guard let state = state?.uppercased() else {
            return true
        }
        return ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED"].contains(state)
    }
}

public struct GameCenterAchievementLocalizationObserved: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var locale: String?
    public var name: String?
    public var beforeEarnedDescription: String?
    public var afterEarnedDescription: String?

    public init(
        id: String,
        locale: String? = nil,
        name: String? = nil,
        beforeEarnedDescription: String? = nil,
        afterEarnedDescription: String? = nil
    ) {
        self.id = id
        self.locale = locale
        self.name = name
        self.beforeEarnedDescription = beforeEarnedDescription
        self.afterEarnedDescription = afterEarnedDescription
    }
}

public struct GameCenterAchievementListReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var ascendKitVersion: String?
    public var source: String
    public var target: GameCenterAchievementTarget
    public var achievements: [GameCenterAchievementObserved]

    public init(
        generatedAt: Date = Date(),
        ascendKitVersion: String? = AscendKitVersion.current,
        source: String = "app-store-connect-api",
        target: GameCenterAchievementTarget,
        achievements: [GameCenterAchievementObserved]
    ) {
        self.generatedAt = generatedAt
        self.ascendKitVersion = ascendKitVersion
        self.source = source
        self.target = target
        self.achievements = achievements
    }
}

public enum GameCenterAchievementSyncAction: String, Codable, Equatable, Sendable {
    case create
    case update
    case skip
}

public struct GameCenterAchievementLocalizationSyncItem: Codable, Equatable, Sendable {
    public var locale: String
    public var action: GameCenterAchievementSyncAction
    public var localizationID: String?

    public init(locale: String, action: GameCenterAchievementSyncAction, localizationID: String? = nil) {
        self.locale = locale
        self.action = action
        self.localizationID = localizationID
    }
}

public struct GameCenterAchievementSyncItem: Codable, Equatable, Sendable {
    public var vendorIdentifier: String
    public var action: GameCenterAchievementSyncAction
    public var achievementID: String?
    public var versionID: String?
    public var localizations: [GameCenterAchievementLocalizationSyncItem]

    public init(
        vendorIdentifier: String,
        action: GameCenterAchievementSyncAction,
        achievementID: String? = nil,
        versionID: String? = nil,
        localizations: [GameCenterAchievementLocalizationSyncItem] = []
    ) {
        self.vendorIdentifier = vendorIdentifier
        self.action = action
        self.achievementID = achievementID
        self.versionID = versionID
        self.localizations = localizations
    }
}

public struct GameCenterAchievementSyncResult: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var ascendKitVersion: String?
    public var executed: Bool
    public var target: GameCenterAchievementTarget
    public var items: [GameCenterAchievementSyncItem]
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        ascendKitVersion: String? = AscendKitVersion.current,
        executed: Bool,
        target: GameCenterAchievementTarget,
        items: [GameCenterAchievementSyncItem],
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.ascendKitVersion = ascendKitVersion
        self.executed = executed
        self.target = target
        self.items = items
        self.findings = findings
    }
}

public extension ASCAPIClient {
    func listGameCenterAchievements(
        target: GameCenterAchievementTarget,
        token: String
    ) async throws -> GameCenterAchievementListReport {
        let resources: [GameCenterAchievementResource]
        switch target.kind {
        case .group:
            resources = try await gameCenterGetList(
                path: "v1/gameCenterGroups/\(target.id)/gameCenterAchievementsV2",
                query: ["limit": "200"],
                token: token
            )
        case .detail:
            resources = try await gameCenterGetList(
                path: "v1/gameCenterDetails/\(target.id)/gameCenterAchievementsV2",
                query: ["limit": "200"],
                token: token
            )
        }

        return GameCenterAchievementListReport(
            target: target,
            achievements: resources.map {
                GameCenterAchievementObserved(
                    id: $0.id,
                    referenceName: $0.attributes.referenceName,
                    vendorIdentifier: $0.attributes.vendorIdentifier,
                    points: $0.attributes.points,
                    showBeforeEarned: $0.attributes.showBeforeEarned,
                    repeatable: $0.attributes.repeatable,
                    archived: $0.attributes.archived
                )
            }
        )
    }

    func syncGameCenterAchievements(
        catalog: GameCenterAchievementCatalog,
        target: GameCenterAchievementTarget,
        confirmRemoteMutation: Bool,
        token: String
    ) async throws -> GameCenterAchievementSyncResult {
        try catalog.validate()

        let observed = try await listGameCenterAchievements(target: target, token: token)
        let byVendorIdentifier = Dictionary(
            observed.achievements.compactMap { achievement -> (String, GameCenterAchievementObserved)? in
                guard let vendorIdentifier = achievement.vendorIdentifier, !vendorIdentifier.isEmpty else {
                    return nil
                }
                return (vendorIdentifier, achievement)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var items: [GameCenterAchievementSyncItem] = []
        var didMutate = false

        for definition in catalog.achievements {
            if let existing = byVendorIdentifier[definition.vendorIdentifier] {
                let item = try await syncExistingGameCenterAchievement(
                    definition: definition,
                    existing: existing,
                    confirmRemoteMutation: confirmRemoteMutation,
                    token: token
                )
                if item.action != .skip || item.localizations.contains(where: { $0.action != .skip }) {
                    didMutate = didMutate || confirmRemoteMutation
                }
                items.append(item)
            } else {
                if confirmRemoteMutation {
                    let created = try await createGameCenterAchievement(
                        definition: definition,
                        target: target,
                        token: token
                    )
                    let version = try await ensureEditableGameCenterAchievementVersion(
                        achievementID: created.id,
                        createIfMissing: true,
                        token: token
                    )
                    let localizationItems = try await syncGameCenterAchievementLocalizations(
                        definitions: definition.localizations,
                        versionID: version.id,
                        confirmRemoteMutation: true,
                        token: token
                    )
                    items.append(
                        GameCenterAchievementSyncItem(
                            vendorIdentifier: definition.vendorIdentifier,
                            action: .create,
                            achievementID: created.id,
                            versionID: version.id,
                            localizations: localizationItems
                        )
                    )
                    didMutate = true
                } else {
                    items.append(
                        GameCenterAchievementSyncItem(
                            vendorIdentifier: definition.vendorIdentifier,
                            action: .create,
                            localizations: definition.localizations.map {
                                GameCenterAchievementLocalizationSyncItem(locale: $0.locale, action: .create)
                            }
                        )
                    )
                }
            }
        }

        let findings: [String]
        if !confirmRemoteMutation {
            findings = ["Dry run only. Re-run with --confirm-remote-mutation to apply CREATE/UPDATE actions."]
        } else if didMutate {
            findings = ["Confirmed Game Center achievement mutations were applied through the App Store Connect API."]
        } else {
            findings = ["Game Center achievements are already in sync; no remote mutation was required."]
        }

        return GameCenterAchievementSyncResult(
            executed: didMutate,
            target: target,
            items: items,
            findings: findings
        )
    }

    private func syncExistingGameCenterAchievement(
        definition: GameCenterAchievementDefinition,
        existing: GameCenterAchievementObserved,
        confirmRemoteMutation: Bool,
        token: String
    ) async throws -> GameCenterAchievementSyncItem {
        let achievementNeedsUpdate =
            existing.referenceName != definition.referenceName ||
            existing.points != definition.points ||
            existing.showBeforeEarned != definition.showBeforeEarned ||
            existing.repeatable != definition.repeatable

        if achievementNeedsUpdate && confirmRemoteMutation {
            _ = try await updateGameCenterAchievement(
                id: existing.id,
                definition: definition,
                token: token
            )
        }

        let versions = try await listGameCenterAchievementVersions(achievementID: existing.id, token: token)
        var selectedVersion = versions.first(where: \.isEditable) ?? versions.first
        var localizationItems: [GameCenterAchievementLocalizationSyncItem] = []

        if let version = selectedVersion {
            localizationItems = try await syncGameCenterAchievementLocalizations(
                definitions: definition.localizations,
                versionID: version.id,
                confirmRemoteMutation: false,
                token: token
            )

            let localizationNeedsMutation = localizationItems.contains { $0.action != .skip }
            if localizationNeedsMutation && !version.isEditable {
                if confirmRemoteMutation {
                    selectedVersion = try await createGameCenterAchievementVersion(achievementID: existing.id, token: token)
                } else {
                    selectedVersion = nil
                }
            }

            if localizationNeedsMutation && confirmRemoteMutation, let editableVersion = selectedVersion {
                localizationItems = try await syncGameCenterAchievementLocalizations(
                    definitions: definition.localizations,
                    versionID: editableVersion.id,
                    confirmRemoteMutation: true,
                    token: token
                )
            }
        } else if !definition.localizations.isEmpty {
            if confirmRemoteMutation {
                let version = try await createGameCenterAchievementVersion(achievementID: existing.id, token: token)
                selectedVersion = version
                localizationItems = try await syncGameCenterAchievementLocalizations(
                    definitions: definition.localizations,
                    versionID: version.id,
                    confirmRemoteMutation: true,
                    token: token
                )
            } else {
                localizationItems = definition.localizations.map {
                    GameCenterAchievementLocalizationSyncItem(locale: $0.locale, action: .create)
                }
            }
        }

        let localizationNeedsUpdate = localizationItems.contains { $0.action != .skip }
        let action: GameCenterAchievementSyncAction = (achievementNeedsUpdate || localizationNeedsUpdate) ? .update : .skip

        return GameCenterAchievementSyncItem(
            vendorIdentifier: definition.vendorIdentifier,
            action: action,
            achievementID: existing.id,
            versionID: selectedVersion?.id,
            localizations: localizationItems
        )
    }

    private func createGameCenterAchievement(
        definition: GameCenterAchievementDefinition,
        target: GameCenterAchievementTarget,
        token: String
    ) async throws -> GameCenterAchievementResource {
        let localVersionID = "ascendkit-\(UUID().uuidString)"
        let targetRelationshipName = target.kind == .group ? "gameCenterGroup" : "gameCenterDetail"
        let targetType = target.kind == .group ? "gameCenterGroups" : "gameCenterDetails"

        let payload: [String: Any] = [
            "data": [
                "type": "gameCenterAchievements",
                "attributes": [
                    "referenceName": definition.referenceName,
                    "vendorIdentifier": definition.vendorIdentifier,
                    "points": definition.points,
                    "showBeforeEarned": definition.showBeforeEarned,
                    "repeatable": definition.repeatable
                ],
                "relationships": [
                    targetRelationshipName: [
                        "data": [
                            "type": targetType,
                            "id": target.id
                        ]
                    ],
                    "versions": [
                        "data": [
                            [
                                "type": "gameCenterAchievementVersions",
                                "id": localVersionID
                            ]
                        ]
                    ]
                ]
            ],
            "included": [
                [
                    "type": "gameCenterAchievementVersions",
                    "id": localVersionID
                ]
            ]
        ]

        return try await gameCenterSendResource(
            method: "POST",
            path: "v2/gameCenterAchievements",
            payload: payload,
            token: token
        )
    }

    private func updateGameCenterAchievement(
        id: String,
        definition: GameCenterAchievementDefinition,
        token: String
    ) async throws -> GameCenterAchievementResource {
        let payload: [String: Any] = [
            "data": [
                "type": "gameCenterAchievements",
                "id": id,
                "attributes": [
                    "referenceName": definition.referenceName,
                    "points": definition.points,
                    "showBeforeEarned": definition.showBeforeEarned,
                    "repeatable": definition.repeatable
                ]
            ]
        ]

        return try await gameCenterSendResource(
            method: "PATCH",
            path: "v2/gameCenterAchievements/\(id)",
            payload: payload,
            token: token
        )
    }

    private func listGameCenterAchievementVersions(
        achievementID: String,
        token: String
    ) async throws -> [GameCenterAchievementVersionObserved] {
        let resources: [GameCenterAchievementVersionResource] = try await gameCenterGetList(
            path: "v2/gameCenterAchievements/\(achievementID)/versions",
            query: ["limit": "200"],
            token: token
        )
        return resources.map {
            GameCenterAchievementVersionObserved(
                id: $0.id,
                state: $0.attributes.state,
                version: $0.attributes.version
            )
        }
    }

    private func ensureEditableGameCenterAchievementVersion(
        achievementID: String,
        createIfMissing: Bool,
        token: String
    ) async throws -> GameCenterAchievementVersionObserved {
        let versions = try await listGameCenterAchievementVersions(achievementID: achievementID, token: token)
        if let editable = versions.first(where: \.isEditable) {
            return editable
        }
        if let first = versions.first {
            if createIfMissing {
                return try await createGameCenterAchievementVersion(achievementID: achievementID, token: token)
            }
            return first
        }
        guard createIfMissing else {
            throw AscendKitError.invalidState("Game Center achievement \(achievementID) has no version.")
        }
        return try await createGameCenterAchievementVersion(achievementID: achievementID, token: token)
    }

    private func createGameCenterAchievementVersion(
        achievementID: String,
        token: String
    ) async throws -> GameCenterAchievementVersionObserved {
        let payload: [String: Any] = [
            "data": [
                "type": "gameCenterAchievementVersions",
                "relationships": [
                    "achievement": [
                        "data": [
                            "type": "gameCenterAchievements",
                            "id": achievementID
                        ]
                    ]
                ]
            ]
        ]
        let resource: GameCenterAchievementVersionResource = try await gameCenterSendResource(
            method: "POST",
            path: "v2/gameCenterAchievementVersions",
            payload: payload,
            token: token
        )
        return GameCenterAchievementVersionObserved(
            id: resource.id,
            state: resource.attributes.state,
            version: resource.attributes.version
        )
    }

    private func syncGameCenterAchievementLocalizations(
        definitions: [GameCenterAchievementLocalizationDefinition],
        versionID: String,
        confirmRemoteMutation: Bool,
        token: String
    ) async throws -> [GameCenterAchievementLocalizationSyncItem] {
        guard !definitions.isEmpty else {
            return []
        }
        let resources: [GameCenterAchievementLocalizationResource] = try await gameCenterGetList(
            path: "v2/gameCenterAchievementVersions/\(versionID)/localizations",
            query: ["limit": "200"],
            token: token
        )
        let observed = resources.map {
            GameCenterAchievementLocalizationObserved(
                id: $0.id,
                locale: $0.attributes.locale,
                name: $0.attributes.name,
                beforeEarnedDescription: $0.attributes.beforeEarnedDescription,
                afterEarnedDescription: $0.attributes.afterEarnedDescription
            )
        }
        let byLocale = Dictionary(
            observed.compactMap { item -> (String, GameCenterAchievementLocalizationObserved)? in
                guard let locale = item.locale else { return nil }
                return (locale, item)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var result: [GameCenterAchievementLocalizationSyncItem] = []
        for definition in definitions {
            if let existing = byLocale[definition.locale] {
                let needsUpdate =
                    existing.name != definition.name ||
                    existing.beforeEarnedDescription != definition.beforeEarnedDescription ||
                    existing.afterEarnedDescription != definition.afterEarnedDescription
                if needsUpdate && confirmRemoteMutation {
                    _ = try await updateGameCenterAchievementLocalization(
                        id: existing.id,
                        definition: definition,
                        token: token
                    )
                }
                result.append(
                    GameCenterAchievementLocalizationSyncItem(
                        locale: definition.locale,
                        action: needsUpdate ? .update : .skip,
                        localizationID: existing.id
                    )
                )
            } else {
                if confirmRemoteMutation {
                    let created = try await createGameCenterAchievementLocalization(
                        definition: definition,
                        versionID: versionID,
                        token: token
                    )
                    result.append(
                        GameCenterAchievementLocalizationSyncItem(
                            locale: definition.locale,
                            action: .create,
                            localizationID: created.id
                        )
                    )
                } else {
                    result.append(
                        GameCenterAchievementLocalizationSyncItem(
                            locale: definition.locale,
                            action: .create
                        )
                    )
                }
            }
        }
        return result
    }

    private func createGameCenterAchievementLocalization(
        definition: GameCenterAchievementLocalizationDefinition,
        versionID: String,
        token: String
    ) async throws -> GameCenterAchievementLocalizationResource {
        let payload: [String: Any] = [
            "data": [
                "type": "gameCenterAchievementLocalizations",
                "attributes": [
                    "locale": definition.locale,
                    "name": definition.name,
                    "beforeEarnedDescription": definition.beforeEarnedDescription,
                    "afterEarnedDescription": definition.afterEarnedDescription
                ],
                "relationships": [
                    "version": [
                        "data": [
                            "type": "gameCenterAchievementVersions",
                            "id": versionID
                        ]
                    ]
                ]
            ]
        ]
        return try await gameCenterSendResource(
            method: "POST",
            path: "v2/gameCenterAchievementLocalizations",
            payload: payload,
            token: token
        )
    }

    private func updateGameCenterAchievementLocalization(
        id: String,
        definition: GameCenterAchievementLocalizationDefinition,
        token: String
    ) async throws -> GameCenterAchievementLocalizationResource {
        let payload: [String: Any] = [
            "data": [
                "type": "gameCenterAchievementLocalizations",
                "id": id,
                "attributes": [
                    "name": definition.name,
                    "beforeEarnedDescription": definition.beforeEarnedDescription,
                    "afterEarnedDescription": definition.afterEarnedDescription
                ]
            ]
        ]
        return try await gameCenterSendResource(
            method: "PATCH",
            path: "v2/gameCenterAchievementLocalizations/\(id)",
            payload: payload,
            token: token
        )
    }

    private func gameCenterGetList<Resource: Decodable>(
        path: String,
        query: [String: String],
        token: String
    ) async throws -> [Resource] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            throw AscendKitError.invalidState("Failed to construct App Store Connect Game Center URL for \(path).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, http) = try await gameCenterData(for: request)
        guard (200..<300).contains(http.statusCode) else {
            throw AscendKitError.invalidState(
                "ASC Game Center request failed for \(path) with HTTP \(http.statusCode): \(String(decoding: data.prefix(2048), as: UTF8.self))"
            )
        }
        return try JSONDecoder().decode(GameCenterListResponse<Resource>.self, from: data).data
    }

    private func gameCenterSendResource<Resource: Decodable>(
        method: String,
        path: String,
        payload: [String: Any],
        token: String
    ) async throws -> Resource {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, http) = try await gameCenterData(for: request)
        guard (200..<300).contains(http.statusCode) else {
            throw AscendKitError.invalidState(
                "ASC Game Center \(method) \(path) failed with HTTP \(http.statusCode): \(String(decoding: data.prefix(8192), as: UTF8.self))"
            )
        }
        return try JSONDecoder().decode(GameCenterSingleResponse<Resource>.self, from: data).data
    }

    private func gameCenterData(for request: URLRequest, maxAttempts: Int = 3) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AscendKitError.invalidState("ASC Game Center request did not return an HTTP response.")
                }
                if (http.statusCode == 429 || (500...599).contains(http.statusCode)), attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: UInt64(250_000_000 * attempt))
                    continue
                }
                return (data, http)
            } catch {
                lastError = error
                if attempt >= maxAttempts {
                    throw error
                }
                if let urlError = error as? URLError,
                   [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable].contains(urlError.code) {
                    try await Task.sleep(nanoseconds: UInt64(250_000_000 * attempt))
                    continue
                }
                throw error
            }
        }
        throw lastError ?? AscendKitError.invalidState("ASC Game Center request failed after retry attempts.")
    }
}

private struct GameCenterListResponse<Resource: Decodable>: Decodable {
    var data: [Resource]
}

private struct GameCenterSingleResponse<Resource: Decodable>: Decodable {
    var data: Resource
}

private struct GameCenterAchievementResource: Decodable {
    var id: String
    var attributes: GameCenterAchievementAttributes
}

private struct GameCenterAchievementAttributes: Decodable {
    var referenceName: String?
    var vendorIdentifier: String?
    var points: Int?
    var showBeforeEarned: Bool?
    var repeatable: Bool?
    var archived: Bool?
}

private struct GameCenterAchievementVersionResource: Decodable {
    var id: String
    var attributes: GameCenterAchievementVersionAttributes
}

private struct GameCenterAchievementVersionAttributes: Decodable {
    var state: String?
    var version: Int?
}

private struct GameCenterAchievementLocalizationResource: Decodable {
    var id: String
    var attributes: GameCenterAchievementLocalizationAttributes
}

private struct GameCenterAchievementLocalizationAttributes: Decodable {
    var locale: String?
    var name: String?
    var beforeEarnedDescription: String?
    var afterEarnedDescription: String?
}
