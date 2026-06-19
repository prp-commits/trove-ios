import Foundation
import Observation

/// App-wide auth state + the shared APIClient. Injected into the view tree via
/// `.environment(...)` and read with `@Environment(Session.self)`.
@MainActor
@Observable
final class Session {
    enum State {
        case loading
        case signedOut
        case signedIn(User)
    }

    private(set) var state: State = .loading
    var authError: String?
    var isWorking = false

    /// Bumped after any write (add/edit/delete/rename/ingest/contact) so list
    /// screens can reload — keeps the Library in sync with detail-screen edits.
    private(set) var dataVersion = 0

    /// Force list screens to reload — used when a change may have happened
    /// outside the app (e.g. the Share Extension captured something while we were
    /// backgrounded), which doesn't go through our write methods.
    func markDataPossiblyChanged() { dataVersion += 1 }

    private let tokens = TokenStore()
    let api: APIClient

    init() {
        api = APIClient(tokenStore: tokens)
    }

    /// On launch: if we have a stored session, validate it via /auth/me.
    func bootstrap() async {
        guard tokens.hasSession else { state = .signedOut; return }
        do {
            let me: MeResponse = try await api.request("/auth/me")
            state = .signedIn(me.user)
            Analytics.identify(userId: me.user.id, provider: me.user.provider)
        } catch {
            state = .signedOut
        }
    }

    func signInDemo() async {
        await authenticate { try await self.api.request("/auth/demo", .post) }
    }

    func signIn(email: String, password: String) async {
        await authenticate {
            try await self.api.request("/auth/signin", .post, body: SignInRequest(email: email, password: password))
        }
    }

    func signUp(email: String, password: String, firstName: String, lastName: String) async {
        await authenticate {
            try await self.api.request(
                "/auth/signup", .post,
                body: SignUpRequest(email: email, password: password, firstName: firstName, lastName: lastName)
            )
        }
    }

    func signOut() async {
        if let refresh = tokens.refreshToken {
            _ = try? await api.request("/auth/logout", .post, body: LogoutRequest(refreshToken: refresh)) as OKResponse
        }
        tokens.clear()
        authError = nil
        // Re-arm first-run so a different account on this device gets onboarded
        // (an existing account with data still self-skips via the empty-library check).
        UserDefaults.standard.set(false, forKey: "hasOnboarded")
        state = .signedOut
        Analytics.reset()
    }

    // MARK: - Data (M1)

    func loadEntities() async throws -> [Entity] {
        try await api.request("/api/entities")
    }

    func loadEntity(_ id: Int) async throws -> EntityDetail {
        let res: EntityDetail = try await api.request("/api/entities/\(id)")
        Analytics.capture("entity_opened")
        return res
    }

    // Capture (M2) — the AI ingest path.
    func ingestText(_ text: String, title: String? = nil) async throws -> IngestResponse {
        let cleanTitle = (title?.isEmpty ?? true) ? nil : title
        let res: IngestResponse = try await api.request("/api/ingest", .post, body: IngestText(text: text, title: cleanTitle))
        dataVersion += 1
        Analytics.capture("ingest_completed", ["kind": "text", "count": res.count])
        return res
    }

    func ingestURL(_ url: String) async throws -> IngestResponse {
        let res: IngestResponse = try await api.request("/api/ingest", .post, body: IngestURL(url: url))
        dataVersion += 1
        Analytics.capture("ingest_completed", ["kind": "url", "count": res.count])
        return res
    }

    func ingestImage(base64: String, mediaType: String = "image/jpeg") async throws -> IngestResponse {
        let title = "photo-\(Int(Date().timeIntervalSince1970)).jpg"
        let res: IngestResponse = try await api.request("/api/ingest", .post, body: IngestImage(imageBase64: base64, imageMediaType: mediaType, title: title))
        dataVersion += 1
        Analytics.capture("ingest_completed", ["kind": "image", "count": res.count])
        return res
    }

    // Ask (M3) — grounded Q&A over the library.
    func ask(_ question: String) async throws -> AskResponse {
        let res: AskResponse = try await api.request("/api/ask", .post, body: AskRequest(question: question))
        Analytics.capture("ask_submitted")
        return res
    }

    // Push / right-time delivery (D115). Register the device + persist this
    // device's timezone (push is server-initiated). Then pull the next nudge.
    func registerDevice(token: String) async throws {
        let _: OKResponse = try await api.request(
            "/api/devices", .post,
            body: RegisterDeviceRequest(token: token, platform: "ios", timezone: TimeZone.current.identifier)
        )
    }
    func nextNudge() async throws -> NextNudge {
        try await api.request("/api/notifications/next")
    }
    func testNudge() async throws -> NextNudge {
        try await api.request("/api/notifications/test", .post)
    }

    // Entity detail actions
    func addInsight(entityId: Int, text: String) async throws {
        let _: OKResponse = try await api.request("/api/insights", .post, body: AddInsightRequest(entityId: entityId, text: text))
        dataVersion += 1
    }

    func deleteInsight(_ id: Int) async throws {
        let _: OKResponse = try await api.request("/api/insights/\(id)", .delete)
        dataVersion += 1
    }

    func editInsight(_ id: Int, text: String) async throws {
        let _: OKResponse = try await api.request("/api/insights/\(id)", .patch, body: TextRequest(text: text))
        dataVersion += 1
    }

    /// Rename an entity. Throws APIError.server with a friendly message on a
    /// same-type name collision (the backend suggests merging).
    func renameEntity(_ id: Int, name: String) async throws {
        let _: OKResponse = try await api.request("/api/entities/\(id)", .patch, body: NameRequest(name: name))
        dataVersion += 1
    }

    /// "Caught up" (person + topic) — records a touch / resets the decay clock.
    func logContact(entityId: Int) async throws {
        let _: OKResponse = try await api.request("/api/entities/\(entityId)/contact", .post)
        dataVersion += 1
    }

    func deleteEntity(_ id: Int) async throws {
        let _: OKResponse = try await api.request("/api/entities/\(id)", .delete)
        dataVersion += 1
    }

    func archiveEntity(_ id: Int) async throws {
        let _: OKResponse = try await api.request("/api/entities/\(id)/archive", .post)
        dataVersion += 1
    }

    func restoreEntity(_ id: Int) async throws {
        let _: OKResponse = try await api.request("/api/entities/\(id)/restore", .post)
        dataVersion += 1
    }

    /// Merge `sourceId` INTO `intoId` (source is absorbed, then gone).
    func mergeEntity(sourceId: Int, intoId: Int) async throws {
        struct Body: Encodable { let intoId: Int }
        let _: OKResponse = try await api.request("/api/entities/\(sourceId)/merge", .post, body: Body(intoId: intoId))
        dataVersion += 1
    }

    /// Raw image bytes for a source (M0/D105 attachments).
    func image(sourceId: Int) async throws -> Data {
        try await api.getData("/api/sources/\(sourceId)/image")
    }

    // Pulse (M5)
    func loadPulse() async throws -> [PulseItem] {
        let res: HealthResponse = try await api.request("/api/relationships/health")
        return res.items
    }

    /// "I reached out" — marks an event acted (suppresses it in Pulse + the deck).
    func actEvent(_ id: Int) async throws {
        let _: OKResponse = try await api.request("/api/events/\(id)/act", .post)
        dataVersion += 1
    }

    /// Confirm an inferred event date so it can drive nudges.
    func confirmEvent(_ id: Int) async throws {
        let _: OKResponse = try await api.request("/api/events/\(id)/confirm", .post)
        dataVersion += 1
    }

    // Review deck (M4)
    func loadDeck(n: Int = 15) async throws -> [DeckCard] {
        let res: DeckResponse = try await api.request("/api/review/deck?n=\(n)")
        Analytics.capture("deck_viewed", ["count": res.cards.count])
        return res.cards
    }

    func swipe(entityId: Int, direction: String, nudgeKind: String?, eventType: String?) async {
        let body = SwipeRequest(entityId: entityId, direction: direction, nudgeKind: nudgeKind, eventType: eventType)
        _ = try? await api.request("/api/review/swipe", .post, body: body) as OKResponse
        if direction == "right" {
            Analytics.capture("nudge_acted", ["nudge_kind": nudgeKind ?? "none", "event_type": eventType ?? "none"])
        }
    }

    /// Snooze a nudge for 1 / 3 / 7 days (suppresses the entity from the deck).
    func snooze(entityId: Int, days: Int, nudgeKind: String?, eventType: String?) async {
        struct Body: Encodable { let entityId: Int; let days: Int; let nudgeKind: String?; let eventType: String? }
        _ = try? await api.request("/api/review/snooze", .post,
                                   body: Body(entityId: entityId, days: days, nudgeKind: nudgeKind, eventType: eventType)) as OKResponse
        dataVersion += 1
    }

    private func authenticate(_ op: @escaping () async throws -> AuthResponse) async {
        isWorking = true
        authError = nil
        do {
            let auth = try await op()
            tokens.save(access: auth.accessToken, refresh: auth.refreshToken)
            state = .signedIn(auth.user)
            Analytics.identify(userId: auth.user.id, provider: auth.user.provider)
            Analytics.capture("signin", ["provider": auth.user.provider ?? "email"])
        } catch {
            authError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isWorking = false
    }
}
