import Foundation

struct ASCStubResponse {
    var status: Int = 200
    var body: String
}

final class ASCStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [ASCStubResponse] = []
    private var recorded: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { recorded } }

    func reset(responses: [ASCStubResponse]) {
        lock.withLock { pending = responses; recorded = [] }
    }

    func respond(to request: URLRequest) throws -> ASCStubResponse {
        try lock.withLock {
            recorded.append(request)
            guard !pending.isEmpty else { throw URLError(.badServerResponse) }
            return pending.removeFirst()
        }
    }
}

class ASCStubURLProtocol: URLProtocol, @unchecked Sendable {
    class var state: ASCStubState { fatalError("Provide a test suite's stub state.") }

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
