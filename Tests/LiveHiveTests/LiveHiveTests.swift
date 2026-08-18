import Foundation
import XCTest
@testable import LiveHive

final class MockTransport: LiveHiveTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var responses: [(Int, Data)] = []
    var error: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if let error {
            throw error
        }
        let next = responses.isEmpty ? (200, Data("{}".utf8)) : responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.0,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (next.1, response)
    }
}

final class LiveHiveTests: XCTestCase {
    var runtime: LiveHiveRuntime!
    var transport: MockTransport!

    override func setUp() {
        transport = MockTransport()
        runtime = LiveHiveRuntime(transport: transport, retrySchedule: [0.0, 0.0])
        runtime.sleep = { _ in }
        LiveHiveRuntime.shared.reset()
    }

    override func tearDown() {
        LiveHiveRuntime.shared.reset()
    }

    func testPushTokenHexConversion() {
        let data = Data([0x0A, 0xFF, 0x00, 0x1B])
        XCTAssertEqual(PushToken.hexString(from: data), "0aff001b")
    }

    func testConfigurationRejectsSecretKey() {
        XCTAssertThrowsError(
            try LiveHiveConfiguration(publicKey: "lh_live_thisisaserverkeyvalue12")
        ) { error in
            XCTAssertEqual(error as? LiveHiveError, .secretKeyRejected)
        }
    }

    func testConfigurationRequiresPublicPrefix() {
        XCTAssertThrowsError(try LiveHiveConfiguration(publicKey: "nope")) { error in
            XCTAssertEqual(error as? LiveHiveError, .invalidPublicKey)
        }
    }

    func testConfigurationAcceptsPublicKeyAndNormalizesBaseURL() throws {
        let config = try LiveHiveConfiguration(
            publicKey: "lh_pub_abcdefghijklmnopqrstuv",
            baseURL: URL(string: "https://www.livehive.dev/v1")!
        )
        XCTAssertEqual(config.publicKey, "lh_pub_abcdefghijklmnopqrstuv")
        XCTAssertEqual(config.registerURL.absoluteString, "https://www.livehive.dev/v1/activities/register")
        XCTAssertEqual(LiveHive.defaultBaseURL.absoluteString, "https://www.livehive.dev")
    }

    func testConfigureStoresPublicKey() throws {
        LiveHive.configure(publicKey: "lh_pub_abcdefghijklmnopqrstuv")
        let stored = LiveHiveRuntime.shared.currentConfiguration()
        XCTAssertEqual(stored?.publicKey, "lh_pub_abcdefghijklmnopqrstuv")
        XCTAssertFalse(stored?.publicKey.contains("lh_live_") ?? true)
    }

    func testRegisterPostsHexTokenAndOmitsSecretsFromBody() async throws {
        let config = try LiveHiveConfiguration(publicKey: "lh_pub_abcdefghijklmnopqrstuv")
        runtime.configure(config)
        try await runtime.register(
            activityId: "order-1",
            pushToken: PushToken.hexString(from: Data([0xDE, 0xAD])),
            type: "delivery"
        )
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/activities/register")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer lh_pub_abcdefghijklmnopqrstuv")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
        XCTAssertEqual(body?["activity_id"] as? String, "order-1")
        XCTAssertEqual(body?["push_token"] as? String, "dead")
        XCTAssertEqual(body?["type"] as? String, "delivery")
        XCTAssertNil(body?["api_key"])
        XCTAssertNil(body?["secret"])
        XCTAssertFalse(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("lh_live_") ?? true)
    }

    func testTokenRotationSendsEachNewToken() async throws {
        let config = try LiveHiveConfiguration(publicKey: "lh_pub_abcdefghijklmnopqrstuv")
        runtime.configure(config)
        let stream = AsyncStream<Data> { continuation in
            continuation.yield(Data([0x01]))
            continuation.yield(Data([0x02]))
            continuation.finish()
        }
        await runtime.observeTokens(activityId: "rot-1", type: nil, tokens: stream).value
        XCTAssertEqual(transport.requests.count, 2)
        let first = try JSONSerialization.jsonObject(with: try XCTUnwrap(transport.requests[0].httpBody)) as? [String: Any]
        let second = try JSONSerialization.jsonObject(with: try XCTUnwrap(transport.requests[1].httpBody)) as? [String: Any]
        XCTAssertEqual(first?["push_token"] as? String, "01")
        XCTAssertEqual(second?["push_token"] as? String, "02")
    }

    func testRetriesTransientHTTPFailures() async throws {
        transport.responses = [
            (503, Data()),
            (200, Data("{}".utf8)),
        ]
        let config = try LiveHiveConfiguration(publicKey: "lh_pub_abcdefghijklmnopqrstuv")
        runtime.configure(config)
        try await runtime.register(activityId: "retry-1", pushToken: "aa".padding(toLength: 16, withPad: "a", startingAt: 0), type: nil)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testDoesNotRetryClientErrors() async {
        transport.responses = [(403, Data())]
        let config = try? LiveHiveConfiguration(publicKey: "lh_pub_abcdefghijklmnopqrstuv")
        runtime.configure(config!)
        do {
            try await runtime.register(activityId: "nope", pushToken: "bbbbbbbbbbbbbbbb", type: nil)
            XCTFail("expected failure")
        } catch LiveHiveError.httpStatus(let status) {
            XCTAssertEqual(status, 403)
            XCTAssertEqual(transport.requests.count, 1)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testUnconfiguredRegisterFails() async {
        do {
            try await runtime.register(activityId: "x", pushToken: "cccccccccccccccc", type: nil)
            XCTFail("expected failure")
        } catch LiveHiveError.notConfigured {
            XCTAssertEqual(transport.requests.count, 0)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testShouldRetryTransientStatusesOnly() {
        XCTAssertTrue(LiveHiveRuntime.shouldRetry(status: 429))
        XCTAssertTrue(LiveHiveRuntime.shouldRetry(status: 500))
        XCTAssertFalse(LiveHiveRuntime.shouldRetry(status: 400))
        XCTAssertFalse(LiveHiveRuntime.shouldRetry(status: 401))
        XCTAssertFalse(LiveHiveRuntime.shouldRetry(status: 403))
    }
}
