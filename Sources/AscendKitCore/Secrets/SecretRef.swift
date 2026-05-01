import Foundation

public enum SecretProvider: String, Codable, Equatable, Sendable {
    case environment
    case file
    case keychain
}

public struct SecretRef: Codable, Equatable, Sendable {
    public var provider: SecretProvider
    public var identifier: String

    public init(provider: SecretProvider, identifier: String) {
        self.provider = provider
        self.identifier = identifier
    }

    public var redactedDescription: String {
        "\(provider.rawValue):\(Redactor.redact(identifier))"
    }
}

public enum Redactor {
    public static func redact(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "<redacted>" }
        if value.count <= 4 { return "<redacted>" }
        return "\(value.prefix(2))...\(value.suffix(2))"
    }
}
