import Foundation

/// Every outbound request in the app goes through this actor.
///
/// These are free, unauthenticated, publicly funded services. Being impolite to them
/// is both rude and the fastest way to get the app rate-limited for everyone, so the
/// throttle is not optional and there is no bypass.
public actor APIClient {
    public static let shared = APIClient()

    /// Contact address included so EBI, NCBI and RCSB can identify the traffic.
    public static let userAgent =
        "HAWKER/1.0 (macOS; +https://github.com/bellcheddar/HAWKER; marc@marcdeller.com)"

    private let session: URLSession
    private let maxConcurrent = 5
    /// Minimum spacing between two requests to the same host.
    private let hostSpacing: Duration = .milliseconds(200)

    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var lastRequestByHost: [String: ContinuousClock.Instant] = [:]
    private let clock = ContinuousClock()

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            // 256 MB on disk: coordinates dominate, and a warm cache is what makes
            // a second launch instant.
            config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20)
            config.requestCachePolicy = .useProtocolCachePolicy
            config.httpAdditionalHeaders = ["User-Agent": APIClient.userAgent]
            config.timeoutIntervalForRequest = 60
            config.waitsForConnectivity = true
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: Public surface

    public func get(_ url: URL, accept: String = "application/json") async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    public func getJSON<T: Decodable & Sendable>(_ type: T.Type, from url: URL) async throws -> T {
        let data = try await get(url)
        return try HawkerJSON.decoder.decode(T.self, from: data)
    }

    public func postJSON<Body: Encodable & Sendable, T: Decodable & Sendable>(
        _ type: T.Type,
        to url: URL,
        body: Body
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try HawkerJSON.encoder.encode(body)
        let data = try await perform(request)
        return try HawkerJSON.decoder.decode(T.self, from: data)
    }

    /// POST returning the raw body. RCSB's search service answers 204 with an empty
    /// body when nothing matches, so callers need the bytes rather than a decode.
    public func postRaw(_ url: URL, body: Data, contentType: String = "application/json") async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        return try await perform(request)
    }

    // MARK: Throttle and retry

    private func perform(_ request: URLRequest) async throws -> Data {
        await acquireSlot()
        defer { releaseSlot() }

        let host = request.url?.host() ?? "-"
        try await spaceRequests(to: host)

        var lastError: Error?
        // Four attempts: 0.5 s, 1 s, 2 s. Beyond that the service is genuinely down
        // and hammering it will not help.
        for attempt in 0..<4 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return data }

                switch http.statusCode {
                case 200..<300:
                    return data
                case 404:
                    // A miss is a normal outcome for these joins, not a failure.
                    throw APIError.notFound(request.url)
                case 429, 500, 502, 503, 504:
                    lastError = APIError.transient(http.statusCode, request.url)
                    let delay = Self.backoff(attempt: attempt, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
                    try await Task.sleep(for: delay)
                    continue
                default:
                    throw APIError.http(http.statusCode, request.url, String(data: data.prefix(400), encoding: .utf8))
                }
            } catch let error as APIError {
                throw error
            } catch {
                // URLSession-level failure (DNS, connection reset). Worth retrying.
                lastError = error
                try await Task.sleep(for: Self.backoff(attempt: attempt, retryAfter: nil))
            }
        }
        throw lastError ?? APIError.transient(0, request.url)
    }

    private static func backoff(attempt: Int, retryAfter: String?) -> Duration {
        if let retryAfter, let seconds = Double(retryAfter) {
            return .seconds(min(seconds, 30))
        }
        return .milliseconds(Int(500 * pow(2, Double(attempt))))
    }

    private func acquireSlot() async {
        if inFlight < maxConcurrent {
            inFlight += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        inFlight += 1
    }

    private func releaseSlot() {
        inFlight -= 1
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }

    private func spaceRequests(to host: String) async throws {
        let now = clock.now
        if let last = lastRequestByHost[host] {
            let elapsed = last.duration(to: now)
            if elapsed < hostSpacing {
                try await Task.sleep(for: hostSpacing - elapsed)
            }
        }
        lastRequestByHost[host] = clock.now
    }
}

public enum APIError: Error, LocalizedError, Sendable {
    case notFound(URL?)
    case transient(Int, URL?)
    case http(Int, URL?, String?)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let url):
            "Not found: \(url?.absoluteString ?? "-")"
        case .transient(let code, let url):
            "Service unavailable (\(code)): \(url?.host() ?? "-")"
        case .http(let code, let url, let body):
            "HTTP \(code) from \(url?.host() ?? "-")\(body.map { ": \($0)" } ?? "")"
        case .malformed(let what):
            "Malformed response: \(what)"
        }
    }

    /// A miss is expected in these joins: most molecules have no co-crystal.
    public var isMiss: Bool { if case .notFound = self { true } else { false } }
}

public enum HawkerJSON {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()
}
