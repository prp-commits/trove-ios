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

    /// Theme A slice 5: the tapped briefing's digest size, so MainTabView can attach it
    /// to `daily_briefing_opened`. Set alongside a `briefing:*` deep link, else nil.
    var pendingBriefingItemCount: Int?

    /// The briefing's notification category + its one-thumb "Not today" snooze action.
    static let briefingCategory = "briefing"
    static let briefingSnoozeAction = "briefing.snooze"

    /// The capture-nudge scenario tag (D169), set alongside `pendingDeepLink == "capture"` so the
    /// router can attribute `capture_nudge_opened`. nil for non-capture taps.
    var pendingCaptureScenario: String?

    private weak var session: Session?
    private var configured = false
    private var pendingAPNsToken: String?   // may arrive before the session is wired

    func configure(session: Session) {
        self.session = session
        if !configured {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            // Theme A slice 5: register the briefing's one-thumb "Not today" snooze action.
            let snooze = UNNotificationAction(identifier: Self.briefingSnoozeAction, title: "Not today", options: [])
            let briefing = UNNotificationCategory(identifier: Self.briefingCategory, actions: [snooze],
                                                  intentIdentifiers: [], options: [])
            center.setNotificationCategories([briefing])
            configured = true
        }
        flushAPNsToken()   // register a token that arrived before the session existed
    }

    /// Current notification authorization status — used to decide whether to show
    /// the priming screen (only when `.notDetermined`).
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Ask once for permission, then register the device. Safe to call repeatedly.
    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        // Remote push (D115 Build #2): ask iOS for the APNs device token. It arrives
        // asynchronously in AppDelegate → registerAPNsToken. Must run on the main thread.
        UIApplication.shared.registerForRemoteNotifications()
        await refresh()
    }

    /// Called from the AppDelegate when the APNs device token arrives. Registers it
    /// (+ this device's timezone) with the server so it can push remotely. If the
    /// session isn't wired yet, stash it and flush on configure().
    func registerAPNsToken(_ hexToken: String) {
        pendingAPNsToken = hexToken
        flushAPNsToken()
    }

    private func flushAPNsToken() {
        guard let token = pendingAPNsToken, session != nil else { return }
        pendingAPNsToken = nil
        Task { try? await session?.registerDevice(token: token) }
    }

    /// Pull the next nudge and schedule a local notification for it (at the
    /// server-chosen waking hour). No-op when there's nothing worth sending.
    func refresh() async {
        guard let session, let res = try? await session.nextNudge(), let n = res.nudge else { return }
        schedule(n, hour: res.deliverHour ?? 9)
    }

    /// Clear every scheduled + delivered local notification and reset the badge.
    /// Local notifications live in iOS's queue, not per-account, so without this a
    /// previous account's nudges keep firing (or sit in Notification Center) after
    /// switching users. Called on sign-out.
    func clearAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        pendingDeepLink = nil
        if #available(iOS 17.0, *) {
            Task { try? await center.setBadgeCount(0) }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
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
        // One push/day, but if more nudges are waiting, a soft tail points to Review
        // (still a single notification — never a stack). D132. A briefing already
        // summarizes the day ("…and N more today."), so it skips the tail and carries
        // its digest size + the snooze action instead (Theme A slice 5).
        let isBriefing = n.nudgeKind == "briefing"
        if !isBriefing, let more = n.moreCount, more > 0 {
            c.body = "\(n.body)\n+\(more) more in Review"
        } else {
            c.body = n.body
        }
        c.sound = .default
        c.threadIdentifier = "trove-nudge"
        var info: [AnyHashable: Any] = ["nudge_ref": n.nudgeRef, "entity_id": n.entityId ?? 0]
        if isBriefing {
            c.categoryIdentifier = Self.briefingCategory
            info["item_count"] = n.itemCount ?? 0
        }
        c.userInfo = info
        return c
    }

    // Foreground presentation. Include `.list` (not just `.banner`) so a nudge that
    // fires while the app is open is also kept in Notification Center — otherwise it
    // shows as a transient banner and vanishes with no trace. `.badge` adds a count.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    // Tap → route (Review, or the capture composer for a capture nudge — D169).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let ref = info["nudge_ref"] as? String
        let scenario = info["scenario"] as? String
        let itemCount = info["item_count"] as? Int

        // Theme A slice 5: the briefing's "Not today" — snooze server-side, don't open/route.
        if response.actionIdentifier == Self.briefingSnoozeAction {
            let s = await MainActor.run { self.session }
            await s?.snoozeBriefing()
            return
        }

        await MainActor.run {
            self.pendingCaptureScenario = (ref == "capture") ? scenario : nil
            self.pendingBriefingItemCount = (ref?.hasPrefix("briefing") == true) ? itemCount : nil
            self.pendingDeepLink = ref ?? "review"   // set LAST — MainTabView routes off this change
        }
    }
}
