import Foundation
import UserNotifications
import UIKit

/// Push / right-time delivery — iOS client (D115, slice 1).
///
/// Slice 1 uses **local notifications** driven by the server's decision engine
/// (`GET /api/notifications/next`): permission → register the device (+ timezone)
/// → pull the next nudge → schedule a local notification at the server's chosen
/// hour. When remote push lands (option 2), the APNs device token replaces the
/// vendor id and the server pushes directly — this client code (content, tap
/// routing, prefs) is reused.
@MainActor
@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Set to the tapped nudge's ref (or "review") so the UI can route to Review.
    var pendingDeepLink: String?

    private weak var session: Session?
    private var configured = false

    func configure(session: Session) {
        self.session = session
        if !configured {
            UNUserNotificationCenter.current().delegate = self
            configured = true
        }
    }

    /// Ask once for permission, then register the device. Safe to call repeatedly.
    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        // Slice 1: a stable per-install id stands in for the APNs token (which a
        // real remote-push build will supply via registerForRemoteNotifications).
        let token = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        try? await session?.registerDevice(token: token)
        await refresh()
    }

    /// Pull the next nudge and schedule a local notification for it (at the
    /// server-chosen waking hour). No-op when there's nothing worth sending.
    func refresh() async {
        guard let session, let res = try? await session.nextNudge(), let n = res.nudge else { return }
        schedule(n, hour: res.deliverHour ?? 9)
    }

    /// Profile "Send a test nudge" — fire the next nudge ~now so it's visible.
    func sendTest() async {
        guard let session, let res = try? await session.testNudge(), let n = res.nudge else { return }
        let content = makeContent(n)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let req = UNNotificationRequest(identifier: "nudge-test-\(UUID().uuidString)", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(req)
    }

    private func schedule(_ n: NudgePayload, hour: Int) {
        let center = UNUserNotificationCenter.current()
        let id = "nudge-\(n.nudgeRef)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        var comps = DateComponents()
        comps.hour = max(0, min(23, hour))
        comps.minute = 0
        // Non-repeating: fires at the next occurrence of that hour (today if still
        // ahead, else tomorrow) — the engine re-decides each day.
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: makeContent(n), trigger: trigger))
    }

    private func makeContent(_ n: NudgePayload) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = n.title
        c.body = n.body
        c.sound = .default
        c.threadIdentifier = "trove-nudge"
        c.userInfo = ["nudge_ref": n.nudgeRef, "entity_id": n.entityId ?? 0]
        return c
    }

    // Show the banner even when the app is in the foreground (so a test is visible).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Tap → route to Review.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let ref = response.notification.request.content.userInfo["nudge_ref"] as? String
        await MainActor.run { self.pendingDeepLink = ref ?? "review" }
    }
}
