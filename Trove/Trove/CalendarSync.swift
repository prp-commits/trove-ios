import Foundation
import EventKit

/// Reads the device's calendars (EventKit) and normalizes events into the shape
/// the backend's `processEvents` pipeline consumes (Phase C, slice 2). One
/// on-device permission covers every account on the phone — iCloud, Google,
/// Exchange — so this is ecosystem-agnostic.
///
/// We only upload events that have attendees: the server's eval-gated `keepEvent`
/// makes the real keep/drop decision, but an attendee-less block can never yield a
/// relationship signal, so there's no reason to send it. Contacts (the dictionary
/// + birthdays) come in slice 3.
@MainActor
final class CalendarSync {
    static let shared = CalendarSync()
    private let store = EKEventStore()

    /// Window: past 90 days (the interaction/warmth signal) + next 180 days.
    private let pastDays = 90
    private let futureDays = 180

    var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) { return status == .fullAccess }
        return status == .authorized
    }

    /// Permission was actively refused — we can't re-prompt; only Settings can flip it.
    var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    /// Prompt for calendar access (the system dialog). Returns whether granted.
    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }

    /// Read the window and normalize. Pure read — no writes to the calendar.
    func collectEvents() -> [DeviceEvent] {
        let now = Date()
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -pastDays, to: now),
              let end = cal.date(byAdding: .day, value: futureDays, to: now) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let iso = ISO8601DateFormatter()

        return store.events(matching: predicate).compactMap { ev -> DeviceEvent? in
            guard ev.hasAttendees, let participants = ev.attendees, !participants.isEmpty else { return nil }

            let attendees = participants.map { p -> DeviceAttendee in
                let raw = p.url.absoluteString.replacingOccurrences(of: "mailto:", with: "").lowercased()
                return DeviceAttendee(
                    email: raw.contains("@") ? raw : nil,
                    displayName: p.name,
                    isSelf: p.isCurrentUser,
                    responseStatus: Self.responseStatus(p.participantStatus),
                    resource: p.participantType == .room || p.participantType == .resource
                )
            }

            // Occurrence-unique id so a recurring meeting logs one warmth signal
            // per occurrence yet a re-sync of the same window stays idempotent.
            let identifier = ev.eventIdentifier ?? UUID().uuidString
            let id = "\(identifier)|\(iso.string(from: ev.startDate))"

            return DeviceEvent(
                id: id,
                title: ev.title ?? "",
                start: iso.string(from: ev.startDate),
                end: ev.endDate.map { iso.string(from: $0) },
                allDay: ev.isAllDay,
                organizerSelf: ev.organizer?.isCurrentUser ?? false,
                machineCalendar: ev.calendar.type == .birthday || ev.calendar.type == .subscription,
                canceled: ev.status == .canceled,
                attendees: attendees
            )
        }
    }

    private static func responseStatus(_ s: EKParticipantStatus) -> String {
        switch s {
        case .accepted:  return "accepted"
        case .tentative: return "tentative"
        case .declined:  return "declined"
        default:         return "needsAction"
        }
    }
}
