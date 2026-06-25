import Foundation

/// A simple async-load state for a screen's data.
enum Loadable<T> {
    case idle
    case loading
    case loaded(T)
    case failed(String)
}

enum DateUtils {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    /// "2026-06-14 21:52:00" (UTC) → "Jun 14, 2026" in the device's zone.
    static func friendly(_ raw: String?) -> String? {
        guard let raw, let date = parser.date(from: raw) else { return nil }
        return display.string(from: date)
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let dayDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    /// An event day "2026-06-27" → "Today" / "Tomorrow" / "Sat, Jun 27" (device zone).
    /// For the "go together" card's dated event.
    static func friendlyEventDay(_ raw: String?) -> String? {
        guard let raw, let date = dayParser.date(from: raw) else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return dayDisplay.string(from: date)
    }

    /// Coarse age of a stored item from its UTC `created_at` string, for
    /// content-free analytics (a young delete ≈ the extraction was wrong).
    /// "<1h" | "1-24h" | "1-7d" | "7d+"; "unknown" if the date can't be parsed.
    static func ageBucket(_ raw: String?) -> String {
        guard let raw, let date = parser.date(from: raw) else { return "unknown" }
        switch Date().timeIntervalSince(date) {
        case ..<3_600:    return "<1h"
        case ..<86_400:   return "1-24h"
        case ..<604_800:  return "1-7d"
        default:          return "7d+"
        }
    }
}
