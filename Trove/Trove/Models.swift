import Foundation

// Decodable models for the auth surface (M0). The decoder uses
// `.convertFromSnakeCase`, so snake_case JSON keys map to camelCase here.

struct User: Decodable, Identifiable, Sendable {
    let id: Int
    let email: String?
    let name: String?
    let firstName: String?
    let lastName: String?
    let photoUrl: String?
    let provider: String?
    let emailVerified: Bool?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let firstName, !firstName.isEmpty { return firstName }
        return email ?? "there"
    }
}

struct AuthResponse: Decodable, Sendable {
    let user: User
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

struct MeResponse: Decodable, Sendable {
    let user: User
}

struct OKResponse: Decodable, Sendable {
    let ok: Bool?
}

// Request bodies (encoded with `.convertToSnakeCase`).
struct SignInRequest: Encodable, Sendable {
    let email: String
    let password: String
}

/// `POST /auth/google` — `credential` is the Google ID token from the native SDK.
struct GoogleSignInRequest: Encodable, Sendable {
    let credential: String
}

/// `GET /auth/config` — public; tells the sign-in screen which providers are live.
struct AuthConfig: Decodable, Sendable {
    let google: Bool?
}

// MARK: - Device calendar/contacts sync (Phase C)
// Posted to POST /api/calendar/device-sync. Keys are camelCase to match the
// backend's normalized event shape (the encoder preserves property names).

struct DeviceAttendee: Encodable, Sendable {
    let email: String?
    let displayName: String?
    let isSelf: Bool
    let responseStatus: String
    let resource: Bool
    enum CodingKeys: String, CodingKey {
        case email, displayName, responseStatus, resource
        case isSelf = "self"   // backend reads attendee.self
    }
}

struct DeviceEvent: Encodable, Sendable {
    let id: String              // occurrence-unique: eventIdentifier + start
    let title: String
    let start: String           // ISO8601
    let end: String?
    let allDay: Bool
    let organizerSelf: Bool
    let machineCalendar: Bool
    let canceled: Bool
    let attendees: [DeviceAttendee]
}

struct DeviceBirthday: Encodable, Sendable {
    let month: Int
    let day: Int
    let year: Int?
}

struct DeviceContact: Encodable, Sendable {
    let name: String
    let emails: [String]
    let birthday: DeviceBirthday?
}

struct DeviceSyncRequest: Encodable, Sendable {
    let events: [DeviceEvent]
    let contacts: [DeviceContact]
}

struct DeviceSyncSummary: Decodable, Sendable {
    let ok: Bool?
    let kept: Int?
    let skipped: Int?
    let created: Int?
    let resolved: Int?
    let held: Int?
    let interactions: Int?
    let birthdays: Int?
}

// /auth/* bodies are snake_case — map explicitly (no global encode strategy).
struct SignUpRequest: Encodable, Sendable {
    let email: String
    let password: String
    let firstName: String
    let lastName: String
    enum CodingKeys: String, CodingKey {
        case email, password
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

struct RefreshRequest: Encodable, Sendable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}

struct LogoutRequest: Encodable, Sendable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}

// MARK: - Library (M1)

/// A row from `GET /api/entities` (extra fields are ignored).
struct Entity: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let type: String
    let insightCount: Int?
    let archivedAt: String?

    var isPerson: Bool { type == "person" }
    var isArchived: Bool { archivedAt != nil }
    var insightCountText: String {
        let n = insightCount ?? 0
        return "\(n) note\(n == 1 ? "" : "s")"
    }
}

/// `GET /api/entities/:id` — the full profile.
struct EntityDetail: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let type: String
    let aliases: [String]?
    let lastInteractionAt: String?
    let archivedAt: String?
    let insights: [Insight]

    var isPerson: Bool { type == "person" }
    var isArchived: Bool { archivedAt != nil }
}

struct Insight: Decodable, Identifiable, Sendable {
    let id: Int
    let text: String
    let createdAt: String?
    let sourceKind: String?
    let sourceId: Int?
    let sourceRef: String?   // D141: original URL for url/video sources (← source_ref)
    let hasImage: Int?       // SQLite returns 1/0, not a JSON bool

    var hasPhoto: Bool { (hasImage ?? 0) == 1 }

    // D141: a video-sourced insight links back to the reel. Tapping opens the
    // https URL → iOS Universal Links launch the source app (Safari fallback).
    var videoURL: URL? {
        guard sourceKind == "video", let ref = sourceRef else { return nil }
        return URL(string: ref)
    }
    /// "YouTube" / "Instagram" / "TikTok" for the source chip (derived from host).
    var videoProviderLabel: String {
        let host = videoURL?.host?.lowercased() ?? ""
        if host.contains("youtu") { return "YouTube" }
        if host.contains("instagr") { return "Instagram" }
        if host.contains("tiktok") { return "TikTok" }
        return "video"
    }
}

// MARK: - Capture / ingest (M2)
// /api/ingest bodies are camelCase — property names match the keys exactly.

struct IngestText: Encodable, Sendable {
    let kind = "text"
    let text: String
    let title: String?
}

struct IngestURL: Encodable, Sendable {
    let kind = "url"
    let url: String
}

struct IngestImage: Encodable, Sendable {
    let kind = "image"
    let imageBase64: String
    let imageMediaType: String
    let title: String?
}

// MARK: - Video capture (D141, Phase B)

/// Per-user connection toggles (`/api/connections`). Add fields as providers land.
struct ConnectionsState: Decodable, Sendable {
    let video: Bool?
    let zola: Bool?
}

struct ConnectionToggle: Encodable, Sendable { let enabled: Bool }

/// An async video-summarization job (`/api/video-jobs`). Drives the activity surface.
struct VideoJob: Decodable, Identifiable, Sendable {
    let id: Int
    let url: String
    let provider: String        // youtube | instagram | tiktok | video
    let status: String          // QUEUED | ONGOING | DONE | FAILED
    let sourceId: Int?
    let reason: String?         // user-safe failure copy (server-sanitized; FAILED only)
    let createdAt: String?

    var isPending: Bool { status == "QUEUED" || status == "ONGOING" }
    var isFailed: Bool { status == "FAILED" }
    var providerLabel: String {
        switch provider { case "youtube": return "YouTube"; case "instagram": return "Instagram"
                          case "tiktok": return "TikTok"; default: return "Video" }
    }
}

/// 202 ack from `/api/ingest` for a video URL (extra keys ignored).
struct IngestAck: Decodable, Sendable { let jobId: Int? }

// MARK: - Pulse (M5)

struct HealthResponse: Decodable, Sendable {
    let items: [PulseItem]
    let horizon: [HorizonItem]?     // D149: events beyond their action window ("On the Horizon")
}

/// One "On the Horizon" row — an entity with a dated event beyond its action window.
/// The server collapses to one row per entity (D149c): `moreCount` > 0 means the entity
/// has several upcoming notes and this is a summary (tap through to see them all).
struct HorizonItem: Decodable, Identifiable, Sendable {
    let entityId: Int
    let name: String
    let type: String
    let eventId: Int?
    let eventType: String?
    let eventDate: String?
    let daysUntil: Int?
    let insightText: String?
    let unconfirmed: Bool?
    let moreCount: Int?

    var id: Int { entityId }
    var isSummary: Bool { (moreCount ?? 0) > 0 }
}

struct PulseItem: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let type: String
    let insightCount: Int?
    let daysSince: Int?
    let threshold: Int?
    let status: String          // upcoming | warm | cooling | reach_out
    let upcoming: Upcoming?

    var isPerson: Bool { type == "person" }

    struct Upcoming: Decodable, Sendable {
        let eventId: Int?
        let eventType: String?
        let eventDate: String?
        let daysUntil: Int?
        let kind: String?
        let insightId: Int?
        let insightText: String?
        let unconfirmed: Bool?
    }
}

// MARK: - Review deck (M4)

struct DeckResponse: Decodable, Sendable {
    let cards: [DeckCard]
}

/// A deck card is either a normal nudge (no `type`) or a topic card (`type` set).
enum DeckCard: Decodable, Sendable {
    case nudge(NudgeCard)
    case other(OtherCard)

    private enum TypeKey: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TypeKey.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type)
        if let type, ["connection", "resurface", "reflection", "together"].contains(type) {
            self = .other(try OtherCard(from: decoder))
        } else {
            self = .nudge(try NudgeCard(from: decoder))
        }
    }
}

struct EntityRef: Decodable, Sendable {
    let id: Int
    let name: String
    let type: String
    var isPerson: Bool { type == "person" }
}

struct NudgeCard: Decodable, Sendable {
    let entity: EntityRef
    let insights: [Insight]
    let pill: Pill
    // Restaurant reservation hand-off (RESERVATIONS_SPEC §5/§6). nil unless the server
    // has RESERVATIONS_ENABLED — so in prod (flag off) the card decodes without a chip.
    //
    // (D206 server / build 1.0 (8) client) `reservation` is the LEGACY singular field; the server
    // now also sends `actions[]` and dual-writes `reservation = actions[0]`. Read `actions` and fall
    // back, so this build works against a server on either side of D206 — and so the server can drop
    // the singular field at BUILD_FLOOR without a second client release.
    let reservation: Reservation?
    let actions: [Reservation]?
    /// Every action to offer, newest contract first. One element today; a concert becomes
    /// tickets + calendar in Phase 3, which is the whole reason the list exists.
    var actionList: [Reservation] {
        if let a = actions, !a.isEmpty { return a }
        return reservation.map { [$0] } ?? []
    }

    struct Pill: Decodable, Sendable {
        let text: String
        let kind: String?          // upcoming_event | reconnect | suggestion
        let eventType: String?
        let eventDate: String?
        let eventId: Int?          // D130: in-window event to mark acted on "Showed up"
        let daysUntil: Int?
        let daysSince: Int?
    }

    struct Reservation: Decodable, Sendable {
        let platform: String       // opentable | resy | sevenrooms | tock | web | maps
        let action: String         // app | web | maps — how to open `url`
        let url: String            // deep/universal link or web reservation page
        let label: String          // "Reserve on OpenTable" / "Find a table" / "Find tickets"
        // (D206) `restaurant` is the legacy name field — it has always also carried film titles and
        // artist names. The server now dual-writes `title` with the same value; prefer it, and keep
        // the fallback so this build still renders against a pre-D206 server.
        let restaurant: String?
        let title: String?
        /// The display name, whichever key the server used. Never empty — falls back to the kind.
        var displayTitle: String { title ?? restaurant ?? kindNoun }
        let eventId: Int?
        // D178: "event" = a ticketed-outing venue (concert/comedy/museum/sports) → a ticket icon.
        // Phase 4 (D188): "movie" = a film → a clapperboard. D205: the server now always sets this,
        // including "dining"; nil only from a pre-D205 server, and means dining.
        var kind: String? = nil
        var isEvent: Bool { kind == "event" }
        var isMovie: Bool { kind == "movie" }
        var isNote: Bool { kind == "note" }
        // (D219) the gift chip: a real web link-out to an Amazon search built from a captured hint.
        var isShop: Bool { kind == "shop" }
        var iconName: String {
            switch kind {
            case "movie": return "movieclapper" // Phase 4 (D188): a film → "Find showtimes"
            case "event": return "ticket"        // D178: concert/comedy/museum/sports
            case "note":  return "square.and.pencil"  // (D208) the recap write-back
            case "shop":  return "gift"          // (D219) a gift hint → an Amazon search
            default:      return "fork.knife"    // dining / nil
            }
        }
        /// What this action is *about*, for copy that has to name it generically.
        var kindNoun: String {
            switch kind {
            case "movie": return "the film"
            case "event": return "the event"
            case "note":  return "this"
            case "shop":  return "the gift"
            default:      return "the restaurant"
            }
        }
        /// The return-prompt question, per kind (§4 item 8). Asking "did you book?" after a ticket
        /// tap — which is what every kind got before — was simply the wrong question.
        var outcomeQuestion: String {
            switch kind {
            case "movie": return "Did you get tickets to \(displayTitle)?"
            case "event": return "Did you get tickets to \(displayTitle)?"
            // (D219) A gift is got, not booked. displayTitle is the item itself ("cast-iron pan").
            case "shop":  return "Did you get \(displayTitle)?"
            default:      return "Did you book \(displayTitle)?"
            }
        }
        /// The affirmative button, per kind. "Yes, add it" reads oddly for a showtime.
        var outcomeAffirmative: String {
            switch kind {
            case "movie", "event": return "Yes, I'm going"
            case "shop":           return "Yes, I got it"
            default:               return "Yes, add it"
            }
        }
        /// (D222) The reassurance line. D206 made the question and the affirmative per-kind but
        /// left this and the decline hardcoded to dining — so a TICKET tap has always said "we
        /// don't see the booking" too. The gift chip only made an existing gap visible.
        var outcomeSubtitle: String {
            switch kind {
            case "movie", "event": return "Only you can confirm — we don't see your tickets."
            case "shop":           return "Only you can confirm — we don't see your orders."
            default:               return "Only you can confirm — we don't see the booking."
            }
        }
        /// The decline option. "Didn't book" is wrong for anything you don't book.
        var outcomeDecline: String {
            switch kind {
            case "movie", "event": return "Didn't get tickets"
            case "shop":           return "Didn't get it"
            default:               return "Didn't book"
            }
        }
        /// An action the user completes in-app (the note composer) rather than by leaving for a
        /// browser — so it must never arm the "did you book?" return prompt.
        /// `shop` is deliberately NOT in-app — it really does leave for Amazon, so both the
        /// hand-off arrow and the return prompt are correct for it.
        var isInApp: Bool { isNote }
        // Phase B (D163): "their city or yours?" — distinct known cities to pick from when the
        // venue would otherwise floor and the note named no city. nil/empty when unambiguous.
        var cityOptions: [CityOption]? = nil

        struct CityOption: Decodable, Sendable, Hashable {
            let city: String       // the locality to re-resolve in
            let why: String        // provenance, e.g. "where Michael lives" / "your area"
        }
    }
}

/// Topic cards (connection / resurface / reflection) — decoded loosely so the
/// deck never breaks. Full per-type actions come in a follow-up; for now these
/// render their content and advance.
struct OtherCard: Decodable, Sendable {
    let type: String
    let entity: EntityRef?
    let recap: String?
    let prompt: String?
    let relationship: String?
    let insights: [Insight]?
    // Connection cards (D74/D143): two entities + a cited insight from each side.
    let linkId: Int?              // ← link_id (snooze/dismiss target)
    let entityA: EntityRef?
    let entityB: EntityRef?
    let citeA: [ConnectionCite]?
    let citeB: [ConnectionCite]?
    // "Go together" cards (D143 Phase 3): a dated event ⨯ the person to bring.
    let matchId: Int?              // ← match_id (act/dismiss target)
    let why: String?              // grounded one-liner (the gate's reason)
    let person: EntityRef?        // the matched person — the one we text
    let event: TogetherEvent?     // the dated event (topic + date)
    let citeEvent: [ConnectionCite]?   // ← cite_event (the event/topic's own notes)
    let citePerson: [ConnectionCite]?  // ← cite_person (the person's interest note)
    let reservation: NudgeCard.Reservation?  // (D156) Reserve hand-off when the matched topic is a restaurant
    let actions: [NudgeCard.Reservation]?    // (D206) the list form; `reservation` is actions[0]
    /// Same precedence as NudgeCard: prefer the list, fall back to the singular field.
    var actionList: [NudgeCard.Reservation] {
        if let a = actions, !a.isEmpty { return a }
        return reservation.map { [$0] } ?? []
    }

    var isTogether: Bool { type == "together" }
    /// The person side of a connection (if any) — the one we offer "text" on.
    var connectionPerson: EntityRef? {
        if entityA?.isPerson == true { return entityA }
        if entityB?.isPerson == true { return entityB }
        return nil
    }
    /// Both cited insights, each tagged with its entity, for rendering below the card.
    var connectionCites: [ConnectionCite] { (citeA ?? []) + (citeB ?? []) }
}

/// The dated event on a "go together" card (← `event`): topic + date.
struct TogetherEvent: Decodable, Sendable {
    let id: Int?
    let topicId: Int?          // ← topic_id (the event's topic entity — snooze/affinity target)
    let text: String?
    let date: String?          // YYYY-MM-DD
    let eventType: String?     // ← event_type
    let topic: String?
}

/// A cited insight on a connection card (← cite_a / cite_b): the note + which entity it's from.
struct ConnectionCite: Decodable, Identifiable, Sendable {
    let id: Int
    let text: String
    let entityName: String?   // ← entity_name
}

struct AddInsightRequest: Encodable, Sendable {
    let entityId: Int
    let text: String
}

struct TextRequest: Encodable, Sendable { let text: String }
struct NameRequest: Encodable, Sendable { let name: String }

/// POST /api/reservations/confirm — the user-asserted outcome of a reservation hand-off
/// (RESERVATIONS_SPEC §6/§7). Keys are camelCase (the /api/* convention); server reads them.
struct ReservationConfirmRequest: Encodable, Sendable {
    let entityId: Int
    let restaurant: String
    let outcome: String        // "booked" | "not_yet" | "declined"
    let platform: String?
    let eventId: Int?
    let kind: String?          // (D228) dining|shop|event|movie — drives the note copy the server writes
}

struct ReservationConfirmResponse: Decodable, Sendable {
    let ok: Bool?
    let insightId: Int?        // the user_asserted note we wrote — deleted on Undo
    let bookedEventId: Int?    // the event we marked booked_at — cleared on Undo
    let calendar: CalendarResult?
    struct CalendarResult: Decodable, Sendable { let created: Bool? }
}

/// POST /api/reservations/resolve-city (D163, Phase B) — re-resolve a floored venue in a specific
/// city the user picked from the "their city or yours?" clarification.
struct ReservationResolveCityRequest: Encodable, Sendable {
    let eventId: Int
    let city: String
}
struct ReservationResolveCityResponse: Decodable, Sendable {
    let reservation: NudgeCard.Reservation?   // the freshly routed action, or nil if still unresolved
}

/// POST /api/reservations/unconfirm — Undo a booking: clears booked_at (the nudge returns)
/// and deletes the insight it wrote.
struct ReservationUnconfirmRequest: Encodable, Sendable {
    let eventId: Int?
    let insightId: Int?
}

/// PATCH /auth/me — edit name + avatar (D87). The encoder doesn't snake-case, so
/// keys are mapped explicitly. `photoUrl` may be a `data:` URI (backend caps it).
struct UpdateProfileRequest: Encodable, Sendable {
    let firstName: String?
    let lastName: String?
    let photoUrl: String?
    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case photoUrl = "photo_url"
    }
}

// MARK: - Push / right-time delivery (D115)

struct RegisterDeviceRequest: Encodable, Sendable {
    let token: String
    let platform: String
    let timezone: String
}

/// `/api/notifications/next` (and `/test`). Decoded via `.convertFromSnakeCase`,
/// so `deliver_hour` → `deliverHour`, `nudge_ref` → `nudgeRef`, etc.
struct NextNudge: Decodable, Sendable {
    let nudge: NudgePayload?
    let deliverHour: Int?
    let today: String?
}

struct NudgePayload: Decodable, Sendable {
    let nudgeRef: String
    let nudgeKind: String
    let eventType: String?
    let entityId: Int?
    let entityName: String?
    let title: String
    let body: String
    let moreCount: Int?        // D132: other nudges waiting → "+N more in Review" tail
}

struct SwipeRequest: Encodable, Sendable {
    let entityId: Int
    let direction: String       // left | right
    let nudgeKind: String?
    let eventType: String?
}

// MARK: - Ask (M3)

struct AskRequest: Encodable, Sendable {
    let question: String
}

struct AskResponse: Decodable, Sendable {
    let answer: String
    let unknown: Bool
    let citations: [AskCitation]
}

struct AskCitation: Decodable, Identifiable, Sendable {
    let refType: String?
    let insightId: Int?
    let sourceId: Int?
    let text: String?
    let geoPlace: String?
    let entityId: Int?
    let entityName: String?

    var id: String { "\(refType ?? "insight")-\(insightId ?? sourceId ?? 0)" }
    var isPhoto: Bool { refType == "image" }
}

struct IngestResponse: Decodable, Sendable {
    let sourceId: Int?
    let count: Int
    let insights: [IngestedInsight]
    // (server also returns `primaryEntity` {name,type} and `ambiguous[]`; unused here)

    struct IngestedInsight: Decodable, Identifiable, Sendable {
        let id: Int
        let text: String
        let entity: Ref
        struct Ref: Decodable, Sendable {
            let id: Int
            let name: String
            let type: String
            let created: Bool?
        }
    }
}

