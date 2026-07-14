import Foundation

/// Bridges a capture-nudge TAP to the next successful capture so we can emit `capture_after_nudge`
/// (CAPTURE_NUDGES_SPEC §7 — the metric the feature is judged on). On tap we stamp the time +
/// scenario; on the next ingest within the window we emit + clear. UserDefaults-backed so it
/// survives the app being backgrounded between the tap and the capture. Content-free.
@MainActor
enum CaptureNudgeTracker {
    private static let tsKey = "captureNudgeTapAt"
    private static let scKey = "captureNudgeScenario"
    private static let windowSeconds: TimeInterval = 3 * 3600   // §7: within N hours (recommend 3h)

    /// Record a capture-prompt tap (called when a `nudge_ref="capture"` notification is opened).
    static func noteTap(scenario: String?) {
        let d = UserDefaults.standard
        d.set(Date().timeIntervalSince1970, forKey: tsKey)
        d.set(scenario ?? "", forKey: scKey)
    }

    /// If a capture tap is pending, consume it (always clears — one capture attributed per tap) and,
    /// when it's within the window, emit `capture_after_nudge`. Call after a successful ingest.
    static func recordIfAfterNudge() {
        let d = UserDefaults.standard
        let at = d.double(forKey: tsKey)
        guard at > 0 else { return }
        let elapsed = Date().timeIntervalSince1970 - at
        let scenario = d.string(forKey: scKey) ?? ""
        d.removeObject(forKey: tsKey)
        d.removeObject(forKey: scKey)
        guard elapsed >= 0, elapsed <= windowSeconds else { return }   // stale tap → discarded
        Analytics.capture("capture_after_nudge", [
            "scenario": scenario.isEmpty ? "unknown" : scenario,
            "latency_bucket": latencyBucket(elapsed),
        ])
    }

    /// Coarse latency bucket (content-free).
    static func latencyBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<300:  return "<5m"
        case ..<1800: return "5-30m"
        case ..<3600: return "30-60m"
        default:      return "1-3h"
        }
    }
}
