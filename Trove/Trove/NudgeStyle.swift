import SwiftUI

/// Per-nudge-type label + color, ported from the web `.ntype-*` palette so a
/// nudge reads the same across platforms.
enum NudgeStyle {
    static func label(kind: String?, eventType: String?) -> String {
        if let eventType { return eventLabel(eventType) }
        switch kind {
        case "reconnect": return "Reconnect"
        case "suggestion": return "Suggestion"
        default: return "Reminder"
        }
    }

    static func color(kind: String?, eventType: String?) -> Color {
        if let eventType { return eventColor(eventType) }
        switch kind {
        case "reconnect": return Color(hex: 0xc97a45)   // terracotta
        default: return Color(hex: 0x6b82b8)            // slate
        }
    }

    private static func eventLabel(_ t: String) -> String {
        switch t {
        case "birthday": return "Birthday"
        case "anniversary": return "Anniversary"
        case "health": return "Check-in"
        case "travel": return "Travel"
        case "travel_return": return "Welcome back"
        case "meeting": return "Meeting"
        case "deadline": return "Deadline"
        default: return "Upcoming"
        }
    }

    private static func eventColor(_ t: String) -> Color {
        switch t {
        case "birthday": return Color(hex: 0xe0903a)
        case "anniversary": return Color(hex: 0xcf6a90)
        case "health": return Color(hex: 0x3fa06b)
        case "travel": return Color(hex: 0x4b8fd1)
        case "travel_return": return Color(hex: 0x3f93a0)
        case "meeting": return Color(hex: 0x7a68c8)
        case "deadline": return Color(hex: 0xd8674e)
        default: return Color(hex: 0x6b82b8)
        }
    }

    /// "today" / "in 3 days" / "2 days ago" / "quiet 40 days".
    static func timing(daysUntil: Int?, daysSince: Int?) -> String? {
        if let d = daysUntil {
            if d == 0 { return "today" }
            if d == 1 { return "tomorrow" }
            if d == -1 { return "yesterday" }
            return d > 0 ? "in \(d) days" : "\(abs(d)) days ago"
        }
        if let s = daysSince { return "quiet \(s) days" }
        return nil
    }
}
