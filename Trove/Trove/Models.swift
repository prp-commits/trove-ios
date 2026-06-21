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
    let hasImage: Int?   // SQLite returns 1/0, not a JSON bool

    var hasPhoto: Bool { (hasImage ?? 0) == 1 }
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

// MARK: - Pulse (M5)

struct HealthResponse: Decodable, Sendable {
    let items: [PulseItem]
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
        if let type, ["connection", "resurface", "reflection"].contains(type) {
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

    struct Pill: Decodable, Sendable {
        let text: String
        let kind: String?          // upcoming_event | reconnect | suggestion
        let eventType: String?
        let eventDate: String?
        let daysUntil: Int?
        let daysSince: Int?
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
}

struct AddInsightRequest: Encodable, Sendable {
    let entityId: Int
    let text: String
}

struct TextRequest: Encodable, Sendable { let text: String }
struct NameRequest: Encodable, Sendable { let name: String }

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

