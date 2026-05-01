import Foundation

public enum AscendKitJSON {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func encodeString<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

public enum AscendKitError: Error, Equatable, CustomStringConvertible {
    case invalidArguments(String)
    case fileNotFound(String)
    case unsupported(String)
    case decodingFailed(String)
    case invalidState(String)
    case workspaceNotFound(String)

    public var description: String {
        switch self {
        case .invalidArguments(let message):
            return message
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .unsupported(let message):
            return message
        case .decodingFailed(let message):
            return message
        case .invalidState(let message):
            return message
        case .workspaceNotFound(let path):
            return "Release workspace not found: \(path)"
        }
    }
}
