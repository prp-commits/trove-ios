import Foundation

/// Content-free product analytics (M8). **Curated events only** — no note content,
/// names, emails, or message text ever leave the device. We send an opaque user id
/// (`u<dbId>`) plus small enum-like properties (kind, count, event_type). Posts
/// straight to PostHog's `/capture` HTTP API, so there's no SDK/SPM dependency.
///
/// Two hard rules (IOS_ROADMAP §M8 / DESIGN privacy): the **demo account is
/// excluded**, and analytics is a **full no-op until `apiKey` is set**. If you can't
/// describe a property to a tester in one sentence as "not your data," don't send it.
///
/// Trade-off vs the original "PostHog autocapture" note: autocapture needs the SDK
/// (Xcode SPM). This HTTP client ships the ~6 curated funnel events with zero deps
/// and zero PII risk. If you later want autocapture, add the PostHog SPM package —
/// the `Analytics.capture(...)` call sites stay the same.
@MainActor
enum Analytics {
    /// PostHog project API key (`phc_…`). Empty → analytics fully disabled.
    /// For a private beta it's fine inline; for a public build move it to an xcconfig.
    private static let apiKey = ""
    private static let host = "https://us.i.posthog.com"

    private static var distinctId: String?
    private static var optedOut = false   // demo account → never sends

    /// Call on sign-in / session-restore. Demo accounts opt out of all events.
    static func identify(userId: Int, provider: String?) {
        optedOut = (provider == "demo")
        distinctId = "u\(userId)"
    }

    /// Call on sign-out.
    static func reset() {
        distinctId = nil
        optedOut = false
    }

    /// Fire-and-forget a curated event. No-ops unless configured + identified + not demo.
    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        guard !apiKey.isEmpty, !optedOut, let did = distinctId else { return }
        var props = properties
        props["$lib"] = "trove-ios"
        let payload: [String: Any] = [
            "api_key": apiKey,
            "event": event,
            "distinct_id": did,
            "properties": props,
        ]
        guard let url = URL(string: "\(host)/capture/"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        URLSession.shared.dataTask(with: req).resume()   // never blocks the UI
    }
}
