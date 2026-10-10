import Foundation

public struct ASCMarketplaceSearchDetail: Codable, Equatable, Sendable {
    public var id: String
    public var appID: String
    public var catalogURL: String

    public init(id: String, appID: String, catalogURL: String) {
        self.id = id
        self.appID = appID
        self.catalogURL = catalogURL
    }
}

public struct ASCMarketplaceSearchDetailMutationResult: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var ascendKitVersion: String?
    public var appID: String
    public var detail: ASCMarketplaceSearchDetail?
    public var executed: Bool
    public var response: ReviewSubmissionExecutionResponse?
    public var findings: [String]

    public init(
        generatedAt: Date = Date(),
        ascendKitVersion: String? = AscendKitVersion.current,
        appID: String,
        detail: ASCMarketplaceSearchDetail? = nil,
        executed: Bool,
        response: ReviewSubmissionExecutionResponse? = nil,
        findings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.ascendKitVersion = ascendKitVersion
        self.appID = appID
        self.detail = detail
        self.executed = executed
        self.response = response
        self.findings = findings
    }
}
