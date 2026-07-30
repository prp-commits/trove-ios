import Foundation

enum ShareConfig {
    /// Keep in sync with the app's `Config.baseURL` (same simulator/device split).
    #if targetEnvironment(simulator)
    static let baseURL = "http://localhost:3100"
    #else
    static let baseURL = "https://trove-api-wewx.onrender.com"
    #endif
}

/// The account the APP considers active, published to the shared app group on every
/// session establishment (sign-in + launch validation). The extension reads it to
/// guard against a STALE shared-keychain token silently posting under the wrong
/// account after an account switch. Suite name mirrors both targets' entitlements.
enum SharedSession {
    static let appGroup = "group.ai.trovestore.Trove"
    static let activeAccountKey = "activeAccountId"

    static var activeAccountId: Int? {
        guard let d = UserDefaults(suiteName: appGroup),
              d.object(forKey: activeAccountKey) != nil else { return nil } // absent → no opinion (fail open)
        return d.integer(forKey: activeAccountKey)
    }
}

/// Minimal ingest client for the Share Extension. Reuses the app's session from
/// the shared keychain, posts to `/api/ingest` (camelCase bodies), and transparently
/// refreshes once on a 401 — access tokens are short-lived and the extension is
/// used sporadically, so a stale token is the common case.
enum ShareIngest {
    enum IngestError: Error, LocalizedError {
        case noSession
        case wrongAccount
        case server(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noSession: return "You're not signed in to Trove. Open the app and sign in, then try again."
            case .wrongAccount: return "This would save to a different Trove account. Open Trove, make sure the right account is signed in, then share again."
            case .server(_, let m): return m
            case .badResponse: return "Couldn't read the shared item."
            }
        }
    }

    @discardableResult
    static func ingestText(_ text: String, title: String?) async throws -> Bool {
        var body: [String: Any] = ["kind": "text", "text": text]
        if let title, !title.isEmpty { body["title"] = title }
        return try await post(body)
    }

    /// Returns true when the server reported this video was already saved (dedup).
    static func ingestURL(_ url: String) async throws -> Bool {
        try await post(["kind": "url", "url": url])
    }

    static func ingestImage(base64: String, mediaType: String, title: String?) async throws {
        var body: [String: Any] = ["kind": "image", "imageBase64": base64, "imageMediaType": mediaType]
        if let title, !title.isEmpty { body["title"] = title }
        try await post(body)
    }

    // MARK: - D231: split the CHEAP duplicate check from the EXPENSIVE upload

    /// The pre-flight (D231): "have I already saved this photo?" by content hash, BEFORE the heavy
    /// upload. Small + fast, so the share sheet blocks only for this — not the whole extraction.
    /// Reuses `post`, so it carries the same account guard + 401-refresh as a real ingest.
    static func preflightImage(contentHash: String) async throws -> Bool {
        try await post(["contentHash": contentHash], path: "/api/ingest/image-check")
    }

    /// Hand the full image to a BACKGROUND URLSession and return immediately. The upload is owned by
    /// `nsurlsessiond`, so it survives the extension being killed the instant the sheet dismisses,
    /// and auto-retries on network. The body is written to a file in the shared app-group container
    /// (background sessions upload from a file, not in-memory). Fire-and-forget: the server's ingest
    /// re-checks the hash, so a race can't double-save; a hard failure after dismiss is silent.
    static func enqueueImageUpload(base64: String, mediaType: String, title: String?, contentHash: String) throws {
        guard let token = SharedKeychain.read(SharedKeychain.accessKey) else { throw IngestError.noSession }
        var body: [String: Any] = ["kind": "image", "imageBase64": base64, "imageMediaType": mediaType, "contentHash": contentHash]
        if let title, !title.isEmpty { body["title"] = title }
        let data = try JSONSerialization.data(withJSONObject: body)

        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedSession.appGroup)?
            .appendingPathComponent("share-uploads", isDirectory: true) else { throw IngestError.badResponse }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: fileURL, options: .atomic)

        guard let url = URL(string: ShareConfig.baseURL + "/api/ingest") else { throw IngestError.badResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(TimeZone.current.identifier, forHTTPHeaderField: "X-Timezone")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // A UNIQUE identifier per upload: two processes (extension + app) can't share one background
        // session, so each share is its own session. If the extension dies before it finishes, iOS
        // relaunches the APP with this identifier to deliver the final callbacks (AppDelegate).
        let id = "ai.trovestore.Trove.upload." + UUID().uuidString
        let config = URLSessionConfiguration.background(withIdentifier: id)
        config.sharedContainerIdentifier = SharedSession.appGroup
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        let session = URLSession(configuration: config, delegate: BackgroundUploadDelegate.shared, delegateQueue: nil)
        let task = session.uploadTask(with: req, fromFile: fileURL)
        task.taskDescription = fileURL.path   // so the delegate can delete the temp file when done
        task.resume()
    }

    // MARK: - Core

    /// @returns true when the server replied 200 {duplicate:true} (already saved).
    /// `path` lets the same auth/refresh/account-guard back both /api/ingest and the D231
    /// /api/ingest/image-check pre-flight.
    @discardableResult
    private static func post(_ json: [String: Any], path: String = "/api/ingest", isRetry: Bool = false) async throws -> Bool {
        guard let token = SharedKeychain.read(SharedKeychain.accessKey) else { throw IngestError.noSession }
        // Guard a STALE shared session: if the token's account differs from the app's
        // active account, REFUSE rather than silently ingest under the wrong user
        // (the D144 cross-account bug). Fail open when either side is unknown.
        if let active = SharedSession.activeAccountId, let owner = accountId(fromJWT: token), active != owner {
            throw IngestError.wrongAccount
        }
        guard let url = URL(string: ShareConfig.baseURL + path) else { throw IngestError.badResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(TimeZone.current.identifier, forHTTPHeaderField: "X-Timezone")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw IngestError.badResponse }

        if http.statusCode == 401 && !isRetry {
            if await refresh() { return try await post(json, path: path, isRetry: true) }
            throw IngestError.noSession
        }
        guard (200..<300).contains(http.statusCode) else {
            throw IngestError.server(http.statusCode, message(from: data))
        }
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["duplicate"] as? Bool) ?? false
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

    /// Extract the `sub` (user id) claim from a JWT access token WITHOUT verifying the
    /// signature — we only compare it to the app's active account to catch a stale
    /// shared session, so trust isn't at stake (the server still verifies the token).
    /// Best-effort: nil if it can't be parsed → the caller fails open.
    private static func accountId(fromJWT token: String) -> Int? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let sub = obj["sub"] as? Int { return sub }
        if let sub = obj["sub"] as? String { return Int(sub) }
        return nil
    }

    private static func message(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let e = obj["error"] as? String { return e }
        return "Something went wrong."
    }
}

// D231: the extension's own background-session delegate. Handles the case where the extension is
// still alive when a (small, fast) upload finishes — it just deletes the temp file. If the extension
// has already been killed, the APP receives these callbacks instead (see AppDelegate).
final class BackgroundUploadDelegate: NSObject, URLSessionDataDelegate {
    static let shared = BackgroundUploadDelegate()
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let path = task.taskDescription { try? FileManager.default.removeItem(atPath: path) }
        session.finishTasksAndInvalidate()
    }
}
