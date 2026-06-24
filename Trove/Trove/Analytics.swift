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
    private static let apiKey = "phc_unMrZwSxvghTkfRF4esW3mvKujdk2QpEKCt3waKc5eKd"
    private static let host = "https://us.i.posthog.com"

    private static var distinctId: String?
    private static var optedOut = false   // demo account → never sends

    /// Call on sign-in / session-restore. Demo accounts opt out of all events.
    static func identify(userId: Int, provider: String?) {
        optedOut = (provider == "demo")
        distinctId = "u\(userId)"
        // Stamp first-seen for the activation window (once per user, non-demo).
        if !optedOut, let fk = aKey("firstSeen"), defaults.object(forKey: fk) == nil {
            defaults.set(Date(), forKey: fk)
        }
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
        // Never let PostHog GeoIP-enrich from the request IP — App Privacy declares
        // Location is NOT collected, and the promise is content-free / IP-discarded.
        props["$geoip_disable"] = true
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

    // MARK: - Activation milestone (content-free)
    // Fires `activation_reached` ONCE per user the first time they reach **>=3 captures
    // AND a value moment** (a successful Ask, or an acted-on nudge). Carries
    // `hours_since_install` so analysis can apply the 48h activation window (we emit
    // whenever the bar is first met; the 48h cut is applied downstream, so a late
    // activator isn't lost). Per-user state in UserDefaults, namespaced by the opaque
    // distinct id; demo is excluded.
    private static let defaults = UserDefaults.standard
    private static func aKey(_ k: String) -> String? {
        guard let did = distinctId else { return nil }
        return "activation.\(did).\(k)"
    }

    /// One capture action happened — counts toward the >=3 threshold.
    static func noteCapture() {
        guard !optedOut, let ck = aKey("captures") else { return }
        defaults.set(defaults.integer(forKey: ck) + 1, forKey: ck)
        checkActivation()
    }

    /// A value moment happened (a successful Ask, or an acted-on nudge).
    static func noteValueMoment() {
        guard !optedOut, let vk = aKey("value") else { return }
        defaults.set(true, forKey: vk)
        checkActivation()
    }

    private static func checkActivation() {
        guard let firedKey = aKey("fired"), !defaults.bool(forKey: firedKey),
              let capturesKey = aKey("captures"), let valueKey = aKey("value") else { return }
        let captures = defaults.integer(forKey: capturesKey)
        guard captures >= 3, defaults.bool(forKey: valueKey) else { return }
        defaults.set(true, forKey: firedKey)
        let hours = (aKey("firstSeen").flatMap { defaults.object(forKey: $0) as? Date })
            .map { Int(Date().timeIntervalSince($0) / 3600) } ?? 0
        capture("activation_reached", ["captures_count": captures, "hours_since_install": hours])
    }
}
