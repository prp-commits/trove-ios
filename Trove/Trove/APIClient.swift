import Foundation

enum HTTPMethod: String {
    case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE", put = "PUT"
}

enum APIError: LocalizedError {
    case invalidURL
    case network(Error)
    case decoding(Error)
    case unauthorized
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid request URL."
        case .network: return "Can't reach the server. Check your connection and that the backend is running."
        case .decoding: return "Unexpected response from the server."
        case .unauthorized: return "Your session expired. Please sign in again."
        case .server(_, let message): return message
        }
    }
}

private struct APIErrorBody: Decodable { let error: String? }

/// One networking client: attaches the bearer + `X-Timezone`, decodes JSON, and
/// transparently handles 401 → refresh → retry (single-flight). An `actor` so
/// token reads/refresh are serialized.
actor APIClient {
    private let tokenStore: TokenStore
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var refreshTask: Task<Void, Error>?

    init(tokenStore: TokenStore, session: URLSession = .shared) {
        self.tokenStore = tokenStore
        self.session = session
        decoder = JSONDecoder()
        // Responses are uniformly decodable this way: snake_case keys convert to
        // camelCase, and keys already camelCase (e.g. ingest's `sourceId`) are
        // left unchanged. So one strategy covers every endpoint.
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // NO global encode strategy: request bodies are inconsistent across the
        // API — /auth/* expects snake_case (refresh_token), /api/* expects
        // camelCase (imageBase64, entityId). Each request struct maps its own keys.
        encoder = JSONEncoder()
    }

    /// Request with no body.
    func request<T: Decodable>(_ path: String, _ method: HTTPMethod = .get, authorized: Bool = true) async throws -> T {
        let data = try await send(path: path, method: method, body: nil, authorized: authorized, isRetry: false)
        return try decode(data)
    }

    /// Request with an encodable JSON body.
    func request<T: Decodable, B: Encodable>(_ path: String, _ method: HTTPMethod, body: B, authorized: Bool = true) async throws -> T {
        let bodyData = try encoder.encode(body)
        let data = try await send(path: path, method: method, body: bodyData, authorized: authorized, isRetry: false)
        return try decode(data)
    }

    /// Raw authed GET (e.g. image bytes) — same 401→refresh path, no JSON decode.
    func getData(_ path: String) async throws -> Data {
        try await send(path: path, method: .get, body: nil, authorized: true, isRetry: false)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    /// The build number as a plain integer string, read once. Empty-string fallback rather than a
    /// placeholder like "0" or "unknown": the server ignores junk, and a *missing* header is honest
    /// (it lands in the `unknown` bucket) where a fake number would be a lie the release gate reads.
    private static let buildNumber: String = {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }()

    private func send(path: String, method: HTTPMethod, body: Data?, authorized: Bool, isRetry: Bool) async throws -> Data {
        guard let url = URL(string: Config.baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        // API responses are personalized + time-sensitive (the Review deck resolves reservations,
        // day-relative nudges). Never serve them from the on-disk URLCache — that surfaced a stale
        // deck across force-quits (a resolved restaurant kept its old city). Always fetch fresh.
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(TimeZone.current.identifier, forHTTPHeaderField: "X-Timezone")
        // (D207) The build number, so the server can answer "is any active client still below
        // BUILD_FLOOR?" before it deletes a dual-written field (NUDGE_FOUNDRY_SPEC §4.1). Without
        // this the gate is a guess, and guessing wrong blanks a chip on someone's phone.
        // CFBundleVersion = CURRENT_PROJECT_VERSION — the monotonic one. Deliberately NOT
        // CFBundleShortVersionString, which sits at "1.0" across many builds.
        req.setValue(Self.buildNumber, forHTTPHeaderField: "X-App-Build")
        if authorized, let token = tokenStore.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.network(error) }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }

        if http.statusCode == 401 && authorized && !isRetry {
            try await refreshTokens()
            return try await send(path: path, method: method, body: body, authorized: authorized, isRetry: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: Self.message(from: data))
        }
        return data
    }

    // Single-flight refresh: concurrent 401s await one refresh, not many.
    private func refreshTokens() async throws {
        if let existing = refreshTask { return try await existing.value }
        let task = Task<Void, Error> { try await self.performRefresh() }
        refreshTask = task
        do { try await task.value; refreshTask = nil }
        catch { refreshTask = nil; throw error }
    }

    private func performRefresh() async throws {
        guard let refresh = tokenStore.refreshToken else { throw APIError.unauthorized }
        guard let url = URL(string: Config.baseURL + "/auth/refresh") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(RefreshRequest(refreshToken: refresh))

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            tokenStore.clear()
            throw APIError.unauthorized
        }
        let auth: AuthResponse = try decode(data)
        tokenStore.save(access: auth.accessToken, refresh: auth.refreshToken)
    }

    private static func message(from data: Data) -> String {
        if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data), let e = body.error {
            return e
        }
        return "Something went wrong."
    }
}
