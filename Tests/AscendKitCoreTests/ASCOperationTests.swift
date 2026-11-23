import Foundation
import Testing
@testable import AscendKitCore

@Suite("Public ASC operations", .serialized)
struct ASCOperationTests {
    private let planner = ASCOperationPlanner()

    @Test("ages use the app info relationship and patch only explicit answers")
    func ageRating() throws {
        let observation = try planner.plan(domain: "age-rating", action: "observe", options: ["app-info-id": "app-info-1"])
        #expect(observation.path == "v1/appInfos/app-info-1/ageRatingDeclaration")
        #expect(!observation.mutatesRemote)

        let plan = try planner.plan(domain: "age-rating", action: "set", options: [
            "declaration-id": "age-1", "shared-location": "false", "dating-and-relationships": "true",
            "korea-age-rating-override": "TWELVE_PLUS", "social-media": "true"
        ])
        #expect(plan.method == "PATCH")
        #expect(plan.path == "v1/ageRatingDeclarations/age-1")
        #expect(plan.payload?["data"]?["attributes"] == .object([
            "sharedLocation": .bool(false), "datingAndRelationships": .bool(true),
            "koreaAgeRatingOverride": .string("TWELVE_PLUS"), "socialMedia": .bool(true)
        ]))
        #expect(throws: AscendKitError.self) {
            try planner.plan(domain: "age-rating", action: "set", options: ["declaration-id": "age-1", "shared-location": "maybe"])
        }
    }

    @Test("unconfirmed paths, including resume, never contact ASC")
    func planOnly() async throws {
        let source = try fixture("demo.mov", contents: "demo")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let client = makeClient()
        let plan = try planner.plan(domain: "asset-library", action: "video-upload-resume", options: [
            "video-id": "video-1", "file": source.path
        ])
        #expect(plan.method == "GET")
        #expect(plan.mutatesRemote)
        let result = try await client.executeASCOperation(plan: plan, token: "unused")
        #expect(!result.executed)
        #expect(OperationURLProtocol.state.requests.isEmpty)

        let reviewPlan = try planner.plan(domain: "retention", action: "review-submit", options: ["review-submission-id": "review-1"])
        let review = try await client.executeASCOperation(plan: reviewPlan, confirmRemoteMutation: true, token: "unused")
        #expect(!review.executed)
        #expect(OperationURLProtocol.state.requests.isEmpty)
    }

    @Test("multiseat pricing uses subscription filter and follows all pages")
    func subscriptionPriceTiers() async throws {
        let client = makeClient([
            .init(body: #"{"data":[{"id":"tier-1"}],"links":{"next":"?cursor=next"}}"#),
            .init(body: #"{"data":[{"id":"tier-2"}]}"#)
        ])
        let plan = try planner.plan(domain: "subscriptions", action: "price-tiers",
                                    options: ["subscription-id": "sub-1"], query: ["filter[territory]": "USA"])
        #expect(plan.query == ["filter[subscription]": "sub-1", "filter[territory]": "USA"])
        let result = try await client.executeASCOperation(plan: plan, token: "token")
        #expect(result.responses.count == 2)
        let request = try #require(OperationURLProtocol.state.requests.first)
        #expect(request.url?.path == "/v1/subscriptionPriceTiers")
        let values = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
        #expect(values?.contains(URLQueryItem(name: "filter[subscription]", value: "sub-1")) == true)
    }

    @Test("performance overview requests Apple's JSON media type")
    func performanceOverview() async throws {
        let client = makeClient([.init(body: #"{"version":"1","categories":[]}"#)])
        let plan = try planner.plan(domain: "app-performance", action: "overview", options: ["app-id": "app-1"])
        let result = try await client.executeASCOperation(plan: plan, token: "token")
        #expect(result.responses.first?["version"] == .string("1"))
        #expect(OperationURLProtocol.state.requests.first?.value(forHTTPHeaderField: "Accept") == "application/vnd.apple.xcode-overview+json")
    }

    @Test("retention attachments support a DELETE with linkage body")
    func removeRetentionOffers() async throws {
        let client = makeClient([.init(status: 204, body: "")])
        let plan = try planner.plan(domain: "retention", action: "subscription-offers-remove", options: [
            "subscription-id": "sub-1", "offer-ids": "offer-1,offer-2"
        ])
        #expect(plan.payload?["data"] == .array([
            .object(["type": .string("retentionOffers"), "id": .string("offer-1")]),
            .object(["type": .string("retentionOffers"), "id": .string("offer-2")])
        ]))
        let result = try await client.executeASCOperation(plan: plan, confirmRemoteMutation: true, token: "token")
        #expect(result.executed)
        #expect(result.responses.isEmpty)
        #expect(OperationURLProtocol.state.requests.first?.httpMethod == "DELETE")
        #expect(OperationURLProtocol.state.requests.first?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("validates every review item before submitting", arguments: [true, false])
    func reviewSubmit(dedicated: Bool) async throws {
        let submission = #"{"data":{"type":"reviewSubmissions","id":"review-1","attributes":{"state":"READY_FOR_REVIEW"}}}"#
        let item = dedicated
            ? #"{"data":[{"relationships":{"retentionMessageVersion":{"data":{"type":"retentionMessageVersions","id":"version-1"}}}}]}"#
            : #"{"data":[{"relationships":{"appStoreVersion":{"data":{"type":"appStoreVersions","id":"other"}}}}]}"#
        let client = makeClient([.init(body: submission), .init(body: item), .init(body: #"{"data":{"id":"review-1"}}"#)])
        let plan = try planner.plan(domain: "retention", action: "review-submit", options: ["review-submission-id": "review-1"])
        if dedicated {
            let result = try await client.executeASCOperation(plan: plan, confirmRemoteMutation: true, confirmRemoteSubmission: true, token: "token")
            #expect(result.executed)
            #expect(OperationURLProtocol.state.requests.map(\.httpMethod) == ["GET", "GET", "PATCH"])
        } else {
            await #expect(throws: AscendKitError.self) {
                try await client.executeASCOperation(plan: plan, confirmRemoteMutation: true, confirmRemoteSubmission: true, token: "token")
            }
            #expect(OperationURLProtocol.state.requests.map(\.httpMethod) == ["GET", "GET"])
        }
    }

    @Test("uploads legacy-independent asset library and versioned purchase images", arguments: [true, false])
    func assetUpload(library: Bool) async throws {
        let source = try fixture("demo.png", contents: "test")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let collection = library ? "appAssetLibraryImages" : "inAppPurchaseImages"
        let state = library ? #""state":"AWAITING_UPLOAD""# : #""assetDeliveryState":{"state":"AWAITING_UPLOAD"}"#
        let client = makeClient([
            .init(status: 201, body: """
                {"data":{"type":"\(collection)","id":"image-1","attributes":{
                  \(state),"fileName":"demo.png","fileSize":4,
                  "uploadOperations":[{"url":"https://uploads.example.test/part?signature=secret","method":"PUT","length":4,"offset":0}]
                }}}
                """),
            .init(body: ""),
            .init(body: #"{"data":{"id":"image-1"}}"#)
        ])
        let plan = try planner.plan(
            domain: library ? "asset-library" : "purchase-versions",
            action: library ? "image-upload" : "iap-image-upload",
            options: library
                ? ["library-id": "library-1", "category": "APP_SCREENSHOTS_AND_PREVIEWS", "file": source.path]
                : ["version-id": "version-1", "file": source.path]
        )
        let result = try await client.executeASCOperation(plan: plan, confirmRemoteMutation: true, token: "secret-token")
        #expect(result.executed)
        #expect(!(try AscendKitJSON.encodeString(result)).contains("signature=secret"))
        let requests = OperationURLProtocol.state.requests
        #expect(requests.map(\.httpMethod) == ["POST", "PUT", "PATCH"])
        #expect(requests.map { $0.url?.path } == ["/\(library ? "v1" : "v2")/\(collection)", "/part", "/\(library ? "v1" : "v2")/\(collection)/image-1"])
        #expect(requests.first { $0.httpMethod == "PUT" }?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("rejects mismatched document IDs and obsolete query fields")
    func rejectsMismatchedInputs() throws {
        let file = try fixture("request.json", contents: #"{"data":{"type":"retentionOffers","id":"offer-other","attributes":{"customerEligibilityPaidSubscriptionDurationInMonths":4}}}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(throws: AscendKitError.self) {
            try planner.plan(domain: "retention", action: "offer-update", options: ["offer-id": "offer-1", "file": file.path])
        }
        #expect(throws: AscendKitError.self) {
            try planner.plan(domain: "asset-library", action: "images", options: ["library-id": "library-1"],
                             query: ["filter[obsolete]": "true"])
        }
        #expect(throws: AscendKitError.self) {
            try planner.plan(domain: "game-center-moderation", action: "scores", options: ["leaderboard-id": "id/../other"])
        }
    }

    private func fixture(_ name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("asc-operation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: file)
        return file
    }

    private func makeClient(_ responses: [ASCStubResponse] = []) -> ASCAPIClient {
        OperationURLProtocol.state.reset(responses: responses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OperationURLProtocol.self]
        return ASCAPIClient(baseURL: URL(string: "https://api.example.test")!, session: URLSession(configuration: configuration))
    }
}

private final class OperationURLProtocol: ASCStubURLProtocol, @unchecked Sendable {
    private static let stubState = ASCStubState()
    override class var state: ASCStubState { stubState }
}
