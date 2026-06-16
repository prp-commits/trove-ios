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
}
