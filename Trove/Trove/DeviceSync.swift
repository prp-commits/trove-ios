import Foundation

/// Coordinates device calendar/contacts sync (Phase C, slice 4). There is no manual
/// "Sync" button: once the user connects, sync runs silently on app foreground
/// (throttled). The user's control is **Unsync** (stop + forget). State persists in
/// UserDefaults so `@AppStorage` views and this coordinator share it.
@MainActor
enum DeviceSync {
    static let enabledKey = "deviceSyncEnabled"
    static let lastSyncKey = "lastDeviceSyncAt"
    private static let throttle: TimeInterval = 4 * 60 * 60   // 4h between auto-syncs

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var lastSyncAt: Date? {
        let t = UserDefaults.standard.double(forKey: lastSyncKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// True when the app is actively syncing: enabled by the user AND still
    /// permitted by iOS (they may have revoked in Settings).
    static var isConnected: Bool { isEnabled && CalendarSync.shared.isAuthorized }

    /// Run a sync now. Caller ensures calendar access. Contacts are optional and
    /// only prompted when `requestContacts` is true (never during a silent sync).
    @discardableResult
    static func sync(_ session: Session, requestContacts: Bool = false) async -> DeviceSyncSummary? {
        guard CalendarSync.shared.isAuthorized else { return nil }
        let events = CalendarSync.shared.collectEvents()
        var contacts: [DeviceContact] = []
        if ContactsReader.shared.isAuthorized {
            contacts = ContactsReader.shared.collectContacts()
        } else if requestContacts, await ContactsReader.shared.requestAccess() {
            contacts = ContactsReader.shared.collectContacts()
        }
        let summary = try? await session.syncDeviceCalendar(events: events, contacts: contacts)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
        return summary
    }

    /// Request access, turn sync on, and do the first sync. Returns whether calendar
    /// access was granted.
    @discardableResult
    static func connect(_ session: Session) async -> Bool {
        let granted = await CalendarSync.shared.requestAccess()
        guard granted else { return false }
        UserDefaults.standard.set(true, forKey: enabledKey)
        await sync(session, requestContacts: true)
        return true
    }

    /// Stop syncing and forget what the server derived. (Can't revoke the iOS
    /// permission for the user — that's theirs to do in Settings.)
    static func unsync(_ session: Session) async {
        UserDefaults.standard.set(false, forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
        try? await session.forgetDeviceData()
    }

    /// Silent foreground sync, when enabled + authorized + the throttle has elapsed.
    static func autoSyncIfDue(_ session: Session) async {
        guard isEnabled, CalendarSync.shared.isAuthorized else { return }
        if let last = lastSyncAt, Date().timeIntervalSince(last) < throttle { return }
        await sync(session, requestContacts: false)
    }
}
