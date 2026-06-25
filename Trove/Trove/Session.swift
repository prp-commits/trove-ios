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

    /// Which providers the backend has configured (public, pre-auth). Drives whether
    /// the sign-in screen shows "Continue with Google" (Phase B).
    func authConfig() async -> AuthConfig? {
        try? await api.request("/auth/config")
    }

    /// Native Google Sign-In (Phase B): the SDK gives us a Google ID token; the
    /// backend verifies it and returns our own session — same path as email/demo.
    func signInGoogle(idToken: String) async {
        await authenticate {
            try await self.api.request("/auth/google", .post, body: GoogleSignInRequest(credential: idToken))
        }
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
        // Re-arm onboarding so a different account on this device gets the full
        // first-run + priming again (existing-account/already-connected states still
        // self-skip via their own checks).
        UserDefaults.standard.set(false, forKey: "hasOnboarded")
        UserDefaults.standard.set(false, forKey: "hasConsented")
        UserDefaults.standard.set(false, forKey: "hasPrimedNudges")
        UserDefaults.standard.set(false, forKey: "hasPrimedDeviceSync")
        // Drop on-device contact links + phone numbers so they never bleed across
        // accounts on a shared device (Phase C, slice 5).
        ContactLinkStore.forget()
        // Clear this account's scheduled/delivered local notifications so they don't
        // fire (or linger in Notification Center) under the next account — local
        // notifications aren't account-scoped in iOS's queue.
        NotificationManager.shared.clearAll()
        state = .signedOut
        Analytics.reset()
    }

    /// Edit name + avatar (D87). PATCH /auth/me recomputes the display name from
    /// first/last and accepts a `data:` URI photo (capped server-side); the response
    /// is the updated user, which becomes the new signed-in state.
    func updateProfile(firstName: String, lastName: String, photoUrl: String?) async throws {
        let body = UpdateProfileRequest(firstName: firstName, lastName: lastName, photoUrl: photoUrl)
        let me: MeResponse = try await api.request("/auth/me", .patch, body: body)
        state = .signedIn(me.user)
        dataVersion += 1
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

    // MARK: - Video capture (D141, Phase B)

    func loadConnections() async throws -> ConnectionsState {
        try await api.request("/api/connections")
    }

    /// Toggle the per-user video-capture connection (gates the share → WayIn path).
    func setVideoCapture(_ enabled: Bool) async throws {
        let _: ConnectionsState = try await api.request("/api/connections/video", .put, body: ConnectionToggle(enabled: enabled))
    }

    /// Recent video jobs for the "Recent captures" activity surface.
    func loadVideoJobs() async throws -> [VideoJob] {
        try await api.request("/api/video-jobs")
    }

    /// Retry a failed capture by re-submitting its URL (fire-and-forget → 202).
    func retryVideo(url: String) async throws {
        let _: IngestAck = try await api.request("/api/ingest", .post, body: IngestURL(url: url))
        dataVersion += 1
    }

    // Capture (M2) — the AI ingest path.
    func ingestText(_ text: String, title: String? = nil) async throws -> IngestResponse {
        let cleanTitle = (title?.isEmpty ?? true) ? nil : title
        let res: IngestResponse = try await api.request("/api/ingest", .post, body: IngestText(text: text, title: cleanTitle))
        dataVersion += 1
        Analytics.capture("ingest_completed", ["kind": "text", "count": res.count])
        Analytics.noteCapture()
        return res
    }

    func ingestURL(_ url: String) async throws -> IngestResponse {
        let res: IngestResponse = try await api.request("/api/ingest", .post, body: IngestURL(url: url))
        dataVersion += 1
        Analytics.capture("ingest_completed", ["kind": "url", "count": res.count])
        Analytics.noteCapture()
        return res
    }

    func ingestImage(base64: String, mediaType: String = "image/jpeg") async throws -> IngestResponse {
        let title = "photo-\(Int(Date().timeIntervalSince1970)).jpg"
        let res: IngestResponse = try await api.request("/api/ingest", .post, body: IngestImage(imageBase64: base64, imageMediaType: mediaType, title: title))
        dataVersion += 1
        Analytics.capture("ingest_completed", ["kind": "image", "count": res.count])
        Analytics.noteCapture()
        return res
    }

    // Ask (M3) — grounded Q&A over the library.
    func ask(_ question: String) async throws -> AskResponse {
        let res: AskResponse = try await api.request("/api/ask", .post, body: AskRequest(question: question))
        Analytics.capture("ask_submitted")
        Analytics.noteValueMoment()        // engaging with Ask = an activation value moment
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

    // Device calendar/contacts sync (Phase C). The client reads EventKit +
    // Contacts on-device and posts the normalized batch; the server reuses the
    // calendar pipeline (keepEvent → resolve/create/hold → warmth interactions).
    @discardableResult
    func syncDeviceCalendar(events: [DeviceEvent], contacts: [DeviceContact] = []) async throws -> DeviceSyncSummary {
        let res: DeviceSyncSummary = try await api.request(
            "/api/calendar/device-sync", .post,
            body: DeviceSyncRequest(events: events, contacts: contacts)
        )
        dataVersion += 1   // new interactions/entities → refresh Pulse + Library
        Analytics.capture("device_calendar_synced", ["events": events.count, "interactions": res.interactions ?? 0])
        return res
    }

    /// "Unsync" — forget everything device sync derived (server-side): calendar
    /// warmth interactions, seen-counts, and contacts-sourced birthdays.
    func forgetDeviceData() async throws {
        let _: OKResponse = try await api.request("/api/calendar/device-forget", .post)
        dataVersion += 1
        Analytics.capture("device_calendar_forgotten")
    }

    // Pulse (M5)
    func loadPulse() async throws -> [PulseItem] {
        let res: HealthResponse = try await api.request("/api/relationships/health")
        return res.items
    }

    /// "Showed up" — marks an event acted (suppresses it in Pulse + the deck).
    func actEvent(_ id: Int) async throws {
        let _: OKResponse = try await api.request("/api/events/\(id)/act", .post)
        dataVersion += 1
    }

    /// Undo "Showed up" for an event card — clears acted_at so the nudge returns.
    func unactEvent(_ id: Int) async throws {
        let _: OKResponse = try await api.request("/api/events/\(id)/unact", .post)
        dataVersion += 1
    }

    /// Undo a manual catch-up (the "Showed up" undo on a reconnect card) — removes
    /// the most recent manual touch so the cold relationship nudge returns.
    func undoContact(entityId: Int) async throws {
        let _: OKResponse = try await api.request("/api/entities/\(entityId)/uncontact", .post)
        dataVersion += 1
    }

    /// Confirm an inferred event date so it can drive nudges. Pass `date`
    /// ("YYYY-MM-DD") to set the actual day when the inferred anchor was vague
    /// (e.g. "this week"); omit it to accept the inferred date as-is.
    func confirmEvent(_ id: Int, date: String? = nil) async throws {
        if let date {
            struct Body: Encodable { let date: String }
            let _: OKResponse = try await api.request("/api/events/\(id)/confirm", .post, body: Body(date: date))
        } else {
            let _: OKResponse = try await api.request("/api/events/\(id)/confirm", .post)
        }
        dataVersion += 1
    }

    // Review deck (M4)
    func loadDeck(n: Int = 15) async throws -> [DeckCard] {
        let res: DeckResponse = try await api.request("/api/review/deck?n=\(n)")
        Analytics.capture("deck_viewed", ["count": res.cards.count])
        // Per-nudge impression → the act-rate denominator. (Server also records a
        // de-duped impression in D114; this feeds PostHog's funnel/cohort tooling.)
        for card in res.cards {
            switch card {
            case .nudge(let n):
                Analytics.capture("nudge_shown", ["nudge_kind": n.pill.kind ?? "none",
                                                  "event_type": n.pill.eventType ?? "none"])
            case .other(let o):
                Analytics.capture("nudge_shown", ["nudge_kind": o.type, "event_type": "none"])
            }
        }
        return res.cards
    }

    func swipe(entityId: Int, direction: String, nudgeKind: String?, eventType: String?) async {
        let body = SwipeRequest(entityId: entityId, direction: direction, nudgeKind: nudgeKind, eventType: eventType)
        _ = try? await api.request("/api/review/swipe", .post, body: body) as OKResponse
        let props: [String: Any] = ["nudge_kind": nudgeKind ?? "none", "event_type": eventType ?? "none"]
        if direction == "right" {
            // KEEP swipe — a positive signal, distinct from the explicit "Showed up"
            // act (which carries action:"showed_up" from the deck).
            Analytics.capture("nudge_acted", props.merging(["action": "kept"]) { a, _ in a })
        } else {
            Analytics.capture("nudge_dismissed", props)   // fatigue guardrail
        }
    }

    /// Snooze a nudge for 1 / 3 / 7 days (suppresses the entity from the deck).
    func snooze(entityId: Int, days: Int, nudgeKind: String?, eventType: String?) async {
        struct Body: Encodable { let entityId: Int; let days: Int; let nudgeKind: String?; let eventType: String? }
        _ = try? await api.request("/api/review/snooze", .post,
                                   body: Body(entityId: entityId, days: days, nudgeKind: nudgeKind, eventType: eventType)) as OKResponse
        Analytics.capture("nudge_snoozed", ["nudge_kind": nudgeKind ?? "none",
                                            "event_type": eventType ?? "none", "days": days])
        dataVersion += 1
    }

    private func authenticate(_ op: @escaping () async throws -> AuthResponse) async {
        isWorking = true
        authError = nil
        do {
            let auth = try await op()
            tokens.save(access: auth.accessToken, refresh: auth.refreshToken)
            // Clear any notifications left from a prior account before this one's
            // nudges get scheduled — covers the case where the previous session ended
            // via token expiry (which bypasses signOut).
            NotificationManager.shared.clearAll()
            state = .signedIn(auth.user)
            Analytics.identify(userId: auth.user.id, provider: auth.user.provider)
            Analytics.capture("signin", ["provider": auth.user.provider ?? "email"])
        } catch {
            authError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isWorking = false
    }
}
