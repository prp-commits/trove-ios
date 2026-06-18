import Foundation

enum ShareConfig {
    /// Keep in sync with the app's `Config.baseURL` (same simulator/device split).
    #if targetEnvironment(simulator)
    static let baseURL = "http://localhost:3100"
    #else
    static let baseURL = "https://trove-api-wewx.onrender.com"
    #endif
}

/// Minimal ingest client for the Share Extension. Reuses the app's session from
/// the shared keychain, posts to `/api/ingest` (camelCase bodies), and transparently
/// refreshes once on a 401 — access tokens are short-lived and the extension is
/// used sporadically, so a stale token is the common case.
enum ShareIngest {
    enum IngestError: Error, LocalizedError {
        case noSession
        case server(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noSession: return "You're not signed in to Trove. Open the app and sign in, then try again."
            case .server(_, let m): return m
            case .badResponse: return "Couldn't read the shared item."
            }
        }
    }

    static func ingestText(_ text: String, title: String?) async throws {
        var body: [String: Any] = ["kind": "text", "text": text]
        if let title, !title.isEmpty { body["title"] = title }
        try await post(body)
    }

    static func ingestURL(_ url: String) async throws {
        try await post(["kind": "url", "url": url])
    }

    static func ingestImage(base64: String, mediaType: String, title: String?) async throws {
        var body: [String: Any] = ["kind": "image", "imageBase64": base64, "imageMediaType": mediaType]
        if let title, !title.isEmpty { body["title"] = title }
        try await post(body)
    }

    // MARK: - Core

    private static func post(_ json: [String: Any], isRetry: Bool = false) async throws {
        guard let token = SharedKeychain.read(SharedKeychain.accessKey) else { throw IngestError.noSession }
        guard let url = URL(string: ShareConfig.baseURL + "/api/ingest") else { throw IngestError.badResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(TimeZone.current.identifier, forHTTPHeaderField: "X-Timezone")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw IngestError.badResponse }

        if http.statusCode == 401 && !isRetry {
            if await refresh() { return try await post(json, isRetry: true) }
            throw IngestError.noSession
        }
        guard (200..<300).contains(http.statusCode) else {
            throw IngestError.server(http.statusCode, message(from: data))
        }
    }

    /// One-shot refresh: `/auth/refresh` takes snake_case `refresh_token`; on
    /// success we persist the rotated pair back to the shared keychain so the app
    /// and extension stay in lockstep.
    private static func refresh() async -> Bool {
        guard let refreshToken = SharedKeychain.read(SharedKeychain.refreshKey),
              let url = URL(string: ShareConfig.baseURL + "/auth/refresh") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String,
              let newRefresh = obj["refresh_token"] as? String else { return false }
        SharedKeychain.set(access, for: SharedKeychain.accessKey)
        SharedKeychain.set(newRefresh, for: SharedKeychain.refreshKey)
        return true
    }

    private static func message(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let e = obj["error"] as? String { return e }
        return "Something went wrong."
    }
}
