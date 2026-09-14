import AppIntents
import Foundation

// Theme C C2 — the access path (the reflex). An App Intent that launches Trove
// straight into voice capture, surfaced as an App Shortcut so it's mappable to the
// **Action button** (Settings → Action Button → Shortcut) and runnable from the
// Shortcuts app / Spotlight. (A Control Center *control* additionally needs a Widget
// Extension target — tracked as C2b.)

extension Notification.Name {
    /// Posted when a launch surface (Action button / Shortcut / Control) asks to
    /// start a voice capture; `userInfo["source"]` carries the launch_source.
    static let troveVoiceCapture = Notification.Name("troveVoiceCapture")
}

/// Cold-launch handoff: the intent may run before the signed-in UI is listening, so
/// it also stashes the pending source here for `MainTabView` to consume on appear.
@MainActor enum VoiceLaunch {
    static var pendingSource: String?
}

/// "New voice note" — opens the app and starts hold-free tap-to-record capture.
struct CaptureVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "New voice note"
    static var description = IntentDescription("Start a voice capture in Trove.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            VoiceLaunch.pendingSource = "action_button"     // the primary reflex surface
            NotificationCenter.default.post(name: .troveVoiceCapture, object: nil,
                                            userInfo: ["source": "action_button"])
        }
        return .result()
    }
}

struct TroveAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureVoiceIntent(),
            phrases: [
                "New voice note in \(.applicationName)",
                "Capture with \(.applicationName)",
            ],
            shortTitle: "Voice note",
            systemImageName: "mic.fill"
        )
    }
}
