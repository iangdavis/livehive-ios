import Foundation

/// Converts ActivityKit push token `Data` to the lowercase hex string Live Hive expects.
public enum PushToken {
    public static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

public struct LiveHiveConfiguration: Equatable, Sendable {
    public var publicKey: String
    public var baseURL: URL

    public init(publicKey: String, baseURL: URL = LiveHive.defaultBaseURL) throws {
        let trimmed = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("lh_live_") {
            throw LiveHiveError.secretKeyRejected
        }
        guard trimmed.hasPrefix("lh_pub_"), trimmed.count >= 24 else {
            throw LiveHiveError.invalidPublicKey
        }
        self.publicKey = trimmed
        self.baseURL = Self.normalizeBaseURL(baseURL)
    }

    public static func normalizeBaseURL(_ url: URL) -> URL {
        var value = url.absoluteString
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if value.hasSuffix("/api/v1") {
            value = String(value.dropLast("/api/v1".count))
        } else if value.hasSuffix("/v1") {
            value = String(value.dropLast("/v1".count))
        }
        return URL(string: value) ?? url
    }

    public var registerURL: URL {
        baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("activities")
            .appendingPathComponent("register")
    }
}

public enum LiveHiveError: Error, Equatable, Sendable {
    case notConfigured
    case invalidPublicKey
    case secretKeyRejected
    case invalidResponse
    case httpStatus(Int)
    case retryLimitExceeded(Int)
}

extension LiveHiveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Call LiveHive.configure(publicKey:) before register(_:)."
        case .invalidPublicKey:
            return "LiveHive.configure requires a public key starting with lh_pub_."
        case .secretKeyRejected:
            return "Do not pass a server API key (lh_live_...) to the iOS SDK."
        case .invalidResponse:
            return "Live Hive returned an invalid registration response."
        case .httpStatus(let status):
            return "Live Hive registration failed (\(status))."
        case .retryLimitExceeded(let status):
            return "Live Hive registration failed after retries (\(status))."
        }
    }
}

protocol LiveHiveTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: LiveHiveTransport {}

struct RegisterBody: Encodable {
    var activity_id: String
    var push_token: String
    var type: String?
}

final class LiveHiveRuntime: @unchecked Sendable {
    static let shared = LiveHiveRuntime()

    private let lock = NSLock()
    private var configuration: LiveHiveConfiguration?
    private var observers: [String: Task<Void, Never>] = [:]
    var transport: LiveHiveTransport
    var retrySchedule: [TimeInterval]
    var sleep: @Sendable (TimeInterval) async throws -> Void

    init(
        transport: LiveHiveTransport = URLSession.shared,
        retrySchedule: [TimeInterval] = [0.5, 1.0, 2.0, 4.0]
    ) {
        self.transport = transport
        self.retrySchedule = retrySchedule
        self.sleep = { nanoseconds in
            try await Task.sleep(nanoseconds: UInt64(nanoseconds * 1_000_000_000))
        }
    }

    func configure(_ configuration: LiveHiveConfiguration) {
        lock.lock()
        self.configuration = configuration
        lock.unlock()
    }

    func reset() {
        lock.lock()
        configuration = nil
        let running = observers
        observers = [:]
        lock.unlock()
        for task in running.values {
            task.cancel()
        }
    }

    func currentConfiguration() -> LiveHiveConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return configuration
    }

    func observeTokens(
        activityId: String,
        type: String?,
        tokens: AsyncStream<Data>
    ) -> Task<Void, Never> {
        let task = Task { [weak self] in
            for await token in tokens {
                if Task.isCancelled { break }
                do {
                    try await self?.register(
                        activityId: activityId,
                        pushToken: PushToken.hexString(from: token),
                        type: type
                    )
                } catch {
                    // Failures are retried inside register; unrecoverable errors are ignored
                    // so token rotation can continue.
                }
            }
        }
        lock.lock()
        observers[activityId]?.cancel()
        observers[activityId] = task
        lock.unlock()
        return task
    }

    func register(activityId: String, pushToken: String, type: String?) async throws {
        guard let configuration = currentConfiguration() else {
            throw LiveHiveError.notConfigured
        }

        var lastStatus = 0
        for attempt in 0...retrySchedule.count {
            if Task.isCancelled { return }
            do {
                try await send(
                    configuration: configuration,
                    activityId: activityId,
                    pushToken: pushToken,
                    type: type
                )
                return
            } catch LiveHiveError.httpStatus(let status) {
                lastStatus = status
                let canRetry = Self.shouldRetry(status: status) && attempt < retrySchedule.count
                if !canRetry {
                    if attempt >= retrySchedule.count && Self.shouldRetry(status: status) {
                        throw LiveHiveError.retryLimitExceeded(status)
                    }
                    throw LiveHiveError.httpStatus(status)
                }
                try await sleep(retrySchedule[attempt])
            } catch is CancellationError {
                return
            } catch {
                if attempt >= retrySchedule.count {
                    throw error
                }
                try await sleep(retrySchedule[attempt])
            }
        }
        throw LiveHiveError.retryLimitExceeded(lastStatus)
    }

    private func send(
        configuration: LiveHiveConfiguration,
        activityId: String,
        pushToken: String,
        type: String?
    ) async throws {
        var request = URLRequest(url: configuration.registerURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.publicKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("LiveHive-iOS/0.1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(
            RegisterBody(activity_id: activityId, push_token: pushToken, type: type)
        )

        let (_, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LiveHiveError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LiveHiveError.httpStatus(http.statusCode)
        }
    }

    static func shouldRetry(status: Int) -> Bool {
        status == 429 || (500..<600).contains(status)
    }
}

/// Minimal iOS SDK for registering ActivityKit push tokens with Live Hive.
///
/// The SDK does not create Live Activities, define attributes, or send updates.
/// Your backend updates and ends activities over HTTP with a secret `lh_live_` key.
/// There is no server SDK.
public enum LiveHive {
    public static let defaultBaseURL = URL(string: "https://api.livehive.dev")!

    /// Configures the SDK with a public project key (`lh_pub_...`).
    ///
    /// Call this once at launch, before `register`.
    /// Default `baseURL` is `https://api.livehive.dev`. Override only for local development.
    /// Never pass a server API key (`lh_live_...`).
    public static func configure(publicKey: String, baseURL: URL = defaultBaseURL) {
        do {
            LiveHiveRuntime.shared.configure(
                try LiveHiveConfiguration(publicKey: publicKey, baseURL: baseURL)
            )
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    /// Registers token updates for an activity ID. Prefer `register(_:)` on iOS.
    @discardableResult
    public static func register(
        activityId: String,
        type: String? = nil,
        tokenUpdates: AsyncStream<Data>
    ) -> Task<Void, Never> {
        LiveHiveRuntime.shared.observeTokens(
            activityId: activityId,
            type: type,
            tokens: tokenUpdates
        )
    }
}

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
public extension LiveHive {
    /// Observes `activity.pushTokenUpdates` and POSTs each token to
    /// `POST /v1/activities/register`.
    ///
    /// Does not create, update, or end the Live Activity. Call `Activity.request(..., pushType: .token)` first.
    @discardableResult
    static func register<Attributes: ActivityAttributes>(
        _ activity: Activity<Attributes>,
        activityId: String? = nil,
        type: String? = nil
    ) -> Task<Void, Never> {
        let id = activityId ?? activity.id
        let stream = AsyncStream<Data> { continuation in
            let updates = Task {
                for await token in activity.pushTokenUpdates {
                    continuation.yield(token)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                updates.cancel()
            }
        }
        return register(activityId: id, type: type, tokenUpdates: stream)
    }
}
#endif
