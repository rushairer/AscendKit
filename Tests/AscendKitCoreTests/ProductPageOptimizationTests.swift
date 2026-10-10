import AppKit
import Foundation
import Testing
@testable import AscendKitCore

@Suite("Product page optimization", .serialized)
struct ProductPageOptimizationTests {
    @Test("plans every supported operation", arguments: PPOAction.allCases.filter { $0 != .screenshotUpload })
    func plansAllActions(action: PPOAction) throws {
        let options: [String: String]
        switch action {
        case .list: options = ["app-id": "app-1"]
        case .create: options = ["app-id": "app-1", "name": "Benefits first", "traffic-proportion": "50"]
        case .get, .start, .stop, .delete, .treatments: options = ["experiment-id": "experiment-1"]
        case .update: options = ["experiment-id": "experiment-1", "name": "New name"]
        case .treatmentCreate: options = ["experiment-id": "experiment-1", "name": "Variant A", "icon-name": "AlternateIcon"]
        case .treatmentUpdate: options = ["treatment-id": "treatment-1", "name": "Updated"]
        case .treatmentDelete, .localizations: options = ["treatment-id": "treatment-1"]
        case .localizationCreate: options = ["treatment-id": "treatment-1", "locale": "en-US"]
        case .localizationDelete, .screenshotSets: options = ["localization-id": "localization-1"]
        case .screenshotSetCreate: options = ["localization-id": "localization-1", "display-type": "APP_IPHONE_67"]
        case .screenshots: options = ["set-id": "set-1"]
        case .screenshotOrder: options = ["set-id": "set-1", "screenshot-ids": "shot-2,shot-1"]
        case .screenshotOrderByPrefix: options = ["set-id": "set-1", "localization-id": "loc-1", "prefixes": "02,01"]
        case .screenshotDelete: options = ["screenshot-id": "shot-1"]
        case .reviewCreate: options = ["app-id": "app-1"]
        case .reviewGet, .reviewItems, .reviewSubmit: options = ["review-submission-id": "review-1"]
        case .reviewAdd: options = ["review-submission-id": "review-1", "experiment-id": "experiment-1"]
        case .promote: options = ["version-id": "version-1", "treatment-id": "treatment-1"]
        case .screenshotUpload: return
        }
        let plan = try PPOPlanner().plan(action: action, options: options)
        #expect(plan.action == action)
        #expect(plan.path.hasPrefix("v1/") || plan.path.hasPrefix("v2/"))
        #expect(plan.requiresSubmissionConfirmation == (action == .reviewSubmit))
        #expect(plan.mutatesRemote == ![.list, .get, .treatments, .localizations, .screenshotSets, .screenshots, .reviewGet, .reviewItems].contains(action))
        if plan.method == "POST" || plan.method == "PATCH" { #expect(plan.payload != nil) }
    }

    @Test("uses v2 experiment and treatment relationships")
    func usesV2Relationships() throws {
        let planner = PPOPlanner()
        let create = try planner.plan(action: .create, options: ["app-id": "app-1", "name": "Test", "traffic-proportion": "50"])
        #expect(create.path == "v2/appStoreVersionExperiments")
        #expect(create.payload?["data"]?["attributes"]?["platform"] == .string("IOS"))
        #expect(create.payload?["data"]?["attributes"]?["trafficProportion"] == .number(50))
        let treatment = try planner.plan(action: .treatmentCreate, options: ["experiment-id": "exp-1", "name": "A"])
        #expect(treatment.payload?["data"]?["relationships"]?["appStoreVersionExperimentV2"]?["data"]?["id"] == .string("exp-1"))
        let set = try planner.plan(action: .screenshotSetCreate, options: ["localization-id": "loc-1", "display-type": "APP_IPHONE_67"])
        #expect(set.payload?["data"]?["relationships"]?["appStoreVersionExperimentTreatmentLocalization"]?["data"]?["id"] == .string("loc-1"))
        #expect(set.payload?["data"]?["relationships"]?["appStoreVersionLocalization"] == nil)
    }

    @Test("validates traffic proportion", arguments: ["0", "101", "-1", "50.5", "fifty"])
    func rejectsTraffic(value: String) {
        #expect(throws: AscendKitError.self) {
            try PPOPlanner().plan(action: .create, options: ["app-id": "app-1", "name": "Test", "traffic-proportion": value])
        }
    }

    @Test("rejects invalid IDs, unused flags, empty updates and unsupported platforms")
    func validatesArguments() {
        #expect(throws: AscendKitError.self) { try PPOPlanner().plan(action: .get, options: ["experiment-id": "../apps?x=1"]) }
        #expect(throws: AscendKitError.self) { try PPOPlanner().plan(action: .update, options: ["experiment-id": "exp-1"]) }
        #expect(throws: AscendKitError.self) { try PPOPlanner().plan(action: .start, options: ["experiment-id": "exp-1", "name": "ignored"]) }
        #expect(throws: AscendKitError.self) { try PPOPlanner().plan(action: .create, options: ["app-id": "app-1", "name": "Test", "traffic-proportion": "50", "platform": "MAC_OS"]) }
        #expect(throws: AscendKitError.self) { try PPOPlanner().plan(action: .screenshotOrder, options: ["set-id": "set-1", "screenshot-ids": "shot-1,shot-1"]) }
        #expect(throws: AscendKitError.self) { try PPOPlanner().plan(action: .screenshotOrder, options: ["set-id": "set-1", "screenshot-ids": "shot-1,"]) }
    }

    @Test("unconfirmed mutations never contact ASC")
    func requiresConfirmation() async throws {
        let client = makeClient(responses: [])
        let plan = try PPOPlanner().plan(action: .create, options: ["app-id": "app-1", "name": "Test", "traffic-proportion": "50"])
        let result = try await client.executePPO(plan: plan, token: "secret-token")
        #expect(!result.executed)
        #expect(PPOURLProtocol.state.requests.isEmpty)
        let submit = try PPOPlanner().plan(action: .reviewSubmit, options: ["review-submission-id": "review-1"])
        let missingSubmission = try await client.executePPO(plan: submit, confirmRemoteMutation: true, token: "secret-token")
        let missingMutation = try await client.executePPO(plan: submit, confirmRemoteSubmission: true, token: "secret-token")
        #expect(!missingSubmission.executed && !missingMutation.executed)
        #expect(PPOURLProtocol.state.requests.isEmpty)
    }

    @Test("executes JSON API mutations and returns resource IDs")
    func executesCreate() async throws {
        let client = makeClient(responses: [.init(status: 201, body: #"{"data":{"type":"appStoreVersionExperiments","id":"exp-1","attributes":{"state":"PREPARE_FOR_SUBMISSION"}}}"#)])
        let plan = try PPOPlanner().plan(action: .create, options: ["app-id": "app-1", "name": "Test", "traffic-proportion": "50"])
        let result = try await client.executePPO(plan: plan, confirmRemoteMutation: true, token: "secret-token")
        #expect(result.executed)
        #expect(result.responses.first?["data"]?["id"] == .string("exp-1"))
        let request = try #require(PPOURLProtocol.state.requests.first)
        #expect(request.url?.path == "/v2/appStoreVersionExperiments")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(try requestBody(request) == plan.payload)
        #expect(!(try AscendKitJSON.encodeString(result)).contains("secret-token"))
    }

    @Test("follows all list pages without dropping attributes")
    func followsPagination() async throws {
        let client = makeClient(responses: [
            .init(body: #"{"data":[{"id":"exp-1","attributes":{"reviewRequired":true}}],"links":{"next":"https://api.example.test/v1/apps/app-1/appStoreVersionExperimentsV2?cursor=next"}}"#),
            .init(body: #"{"data":[{"id":"exp-2"}],"links":{"next":null}}"#)
        ])
        let plan = try PPOPlanner().plan(action: .list, options: ["app-id": "app-1"])
        let result = try await client.executePPO(plan: plan, token: "secret-token")
        #expect(!result.executed)
        #expect(result.responses.count == 2)
        #expect(PPOURLProtocol.state.requests.count == 2)
    }

    @Test("refuses hostile or cyclic pagination before sending credentials", arguments: [
        "https://attacker.test/v1/apps/app-1/appStoreVersionExperimentsV2",
        "https://api.example.test/v1/other-resource",
        "https://api.example.test/v1/apps/app-1/appStoreVersionExperimentsV2",
        "http://api.example.test/v1/apps/app-1/appStoreVersionExperimentsV2"
    ])
    func refusesUnsafePagination(link: String) async throws {
        let body = try AscendKitJSON.encodeString(PPOJSONValue.object(["data": .array([]), "links": .object(["next": .string(link)])]))
        let client = makeClient(responses: [.init(body: body)])
        let plan = try PPOPlanner().plan(action: .list, options: ["app-id": "app-1"])
        await #expect(throws: AscendKitError.self) { try await client.executePPO(plan: plan, token: "secret-token") }
        #expect(PPOURLProtocol.state.requests.count == 1)
    }

    @Test("does not retry failed creates")
    func doesNotRetryMutation() async throws {
        let client = makeClient(responses: [.init(status: 500, body: #"{"errors":[{"code":"UNEXPECTED_ERROR"}]}"#)])
        let plan = try PPOPlanner().plan(action: .create, options: ["app-id": "app-1", "name": "Test", "traffic-proportion": "50"])
        await #expect(throws: AscendKitError.self) { try await client.executePPO(plan: plan, confirmRemoteMutation: true, token: "secret-token") }
        #expect(PPOURLProtocol.state.requests.count == 1)
    }

    @Test("accepts empty delete responses")
    func executesDelete() async throws {
        let client = makeClient(responses: [.init(status: 204, body: "")])
        let plan = try PPOPlanner().plan(action: .delete, options: ["experiment-id": "exp-1"])
        let result = try await client.executePPO(plan: plan, confirmRemoteMutation: true, token: "secret-token")
        #expect(result.executed && result.responses.isEmpty)
        #expect(PPOURLProtocol.state.requests.first?.httpMethod == "DELETE")
    }

    @Test("rejects empty or unrelated review submissions", arguments: [
        #"{"data":[]}"#,
        #"{"data":[{"id":"item-1","relationships":{"appStoreVersion":{"data":{"id":"version-1"}}}}]}"#
    ])
    func refusesUnrelatedSubmission(body: String) async throws {
        let client = makeClient(responses: [.init(body: body)])
        let plan = try PPOPlanner().plan(action: .reviewSubmit, options: ["review-submission-id": "review-1"])
        await #expect(throws: AscendKitError.self) {
            try await client.executePPO(plan: plan, confirmRemoteMutation: true, confirmRemoteSubmission: true, token: "secret-token")
        }
        #expect(PPOURLProtocol.state.requests.count == 1)
        #expect(PPOURLProtocol.state.requests.first?.httpMethod == "GET")
    }

    @Test("submits a dedicated PPO review after checking its items")
    func submitsPPOReview() async throws {
        let client = makeClient(responses: [
            .init(body: #"{"data":[{"id":"item-1","relationships":{"appStoreVersionExperimentV2":{"data":{"id":"exp-1"}}}}]}"#),
            .init(body: #"{"data":{"id":"review-1","attributes":{"submitted":true}}}"#)
        ])
        let plan = try PPOPlanner().plan(action: .reviewSubmit, options: ["review-submission-id": "review-1"])
        let result = try await client.executePPO(plan: plan, confirmRemoteMutation: true, confirmRemoteSubmission: true, token: "secret-token")
        #expect(result.executed)
        #expect(PPOURLProtocol.state.requests.map(\.httpMethod) == ["GET", "PATCH"])
    }

    @Test("reorders inherited COMPLETE treatment screenshots and verifies remote order")
    func reordersInheritedScreenshots() async throws {
        let client = makeClient(responses: [
            .init(body: #"{"data":[{"id":"set-1"}]}"#),
            .init(body: screenshotsJSON(["01", "02"])),
            .init(body: ""),
            .init(body: screenshotsJSON(["02", "01"]))
        ])
        let plan = try PPOPlanner().plan(action: .screenshotOrderByPrefix, options: ["set-id": "set-1", "localization-id": "loc-1", "prefixes": "02,01"])
        let pending = try await client.executePPO(plan: plan, token: "token")
        #expect(!pending.executed)
        #expect(PPOURLProtocol.state.requests.isEmpty)
        let result = try await client.executePPO(plan: plan, confirmRemoteMutation: true, token: "token")
        #expect(result.executed)
        #expect(PPOURLProtocol.state.requests.map(\.httpMethod) == ["GET", "GET", "PATCH", "GET"])
        #expect(PPOURLProtocol.state.requests[0].url?.path == "/v1/appStoreVersionExperimentTreatmentLocalizations/loc-1/appScreenshotSets")
        #expect(try requestBody(PPOURLProtocol.state.requests[2])["data"] == .array([
            .object(["type": .string("appScreenshots"), "id": .string("shot-02")]),
            .object(["type": .string("appScreenshots"), "id": .string("shot-01")])
        ]))
    }

    @Test("reports remote order mismatch after PATCH instead of claiming success")
    func refusesMismatchedReadback() async throws {
        let client = makeClient(responses: [
            .init(body: #"{"data":[{"id":"set-1"}]}"#),
            .init(body: screenshotsJSON(["01", "02"])),
            .init(body: ""),
            .init(body: screenshotsJSON(["01", "02"]))
        ])
        let plan = try PPOPlanner().plan(action: .screenshotOrderByPrefix, options: ["set-id": "set-1", "localization-id": "loc-1", "prefixes": "02,01"])
        await #expect(throws: AscendKitError.self) {
            try await client.executePPO(plan: plan, confirmRemoteMutation: true, token: "token")
        }
        #expect(PPOURLProtocol.state.requests.map(\.httpMethod) == ["GET", "GET", "PATCH", "GET"])
    }

    @Test("refuses incomplete, ambiguous or original-page screenshots before mutation", arguments: ["missing", "duplicate", "pending", "original"])
    func refusesUnsafeReorder(scenario: String) async throws {
        let set = scenario == "original" ? #"{"data":[{"id":"original-set"}]}"# : #"{"data":[{"id":"set-1"}]}"#
        let shots = scenario == "duplicate" ? screenshotsJSON(["01", "01"])
            : scenario == "pending" ? screenshotsJSON(["01", "02"], state: "AWAITING_UPLOAD")
            : screenshotsJSON(["01"])
        let client = makeClient(responses: [.init(body: set), .init(body: shots)])
        let plan = try PPOPlanner().plan(action: .screenshotOrderByPrefix, options: ["set-id": "set-1", "localization-id": "loc-1", "prefixes": "02,01"])
        await #expect(throws: AscendKitError.self) {
            try await client.executePPO(plan: plan, confirmRemoteMutation: true, token: "token")
        }
        #expect(!PPOURLProtocol.state.requests.contains { $0.httpMethod == "PATCH" })
    }

    private func screenshotsJSON(_ prefixes: [String], state: String = "COMPLETE") -> String {
        let items = prefixes.map { prefix in
            PPOJSONValue.object(["id": .string("shot-\(prefix)"), "attributes": .object([
                "fileName": .string("\(prefix)-feature.png"),
                "assetDeliveryState": .object(["state": .string(state)])
            ])])
        }
        return (try? AscendKitJSON.encodeString(PPOJSONValue.object(["data": .array(items)]))) ?? ""
    }

    @Test("uploads assets to a treatment screenshot set and verifies delivery", arguments: ["COMPLETE", "FAILED"])
    func uploadsTreatmentScreenshot(deliveryState: String) async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("ppo-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: fileURL)
        let client = makeClient(responses: [
            .init(status: 201, body: #"{"data":{"id":"shot-1","attributes":{"uploadOperations":[{"url":"https://uploads.example.test/asset","method":"PUT"}]}}}"#),
            .init(body: ""),
            .init(body: #"{"data":{"id":"shot-1"}}"#),
            .init(body: "{\"data\":{\"id\":\"shot-1\",\"attributes\":{\"assetDeliveryState\":{\"state\":\"\(deliveryState)\"}}}}")
        ])
        let plan = try PPOPlanner().plan(action: .screenshotUpload, options: ["set-id": "treatment-set-1", "file": fileURL.path])
        let result = try await client.executePPO(plan: plan, confirmRemoteMutation: true, token: "secret-token")
        #expect(result.upload?.appScreenshotSetID == "treatment-set-1")
        #expect(result.upload?.assetDeliveryState == deliveryState)
        if deliveryState == "FAILED" { #expect(result.findings.contains { $0.contains("do not submit") }) }
        let requests = PPOURLProtocol.state.requests
        #expect(requests.map(\.httpMethod) == ["POST", "PUT", "PATCH", "GET"])
        #expect(try requestBody(requests[0])["data"]?["relationships"]?["appScreenshotSet"]?["data"]?["id"] == .string("treatment-set-1"))
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == nil)
    }

    private func makeClient(responses: [PPOStubResponse]) -> ASCAPIClient {
        PPOURLProtocol.state.reset(responses: responses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PPOURLProtocol.self]
        return ASCAPIClient(baseURL: URL(string: "https://api.example.test")!, session: URLSession(configuration: configuration))
    }

    private func requestBody(_ request: URLRequest) throws -> PPOJSONValue {
        if let body = request.httpBody { return try AscendKitJSON.decoder.decode(PPOJSONValue.self, from: body) }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return try AscendKitJSON.decoder.decode(PPOJSONValue.self, from: data)
    }
}

private struct PPOStubResponse {
    var status: Int = 200
    var body: String
}

private final class PPOStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [PPOStubResponse] = []
    private var recorded: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { recorded } }

    func reset(responses: [PPOStubResponse]) {
        lock.withLock { pending = responses; recorded = [] }
    }

    func respond(to request: URLRequest) throws -> PPOStubResponse {
        try lock.withLock {
            recorded.append(request)
            guard !pending.isEmpty else { throw URLError(.badServerResponse) }
            return pending.removeFirst()
        }
    }
}

private final class PPOURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = PPOStubState()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let stub = try Self.state.respond(to: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
