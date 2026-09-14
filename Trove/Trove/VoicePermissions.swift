import Foundation
import AVFoundation
import Speech

/// Voice-capture permissions (Theme C, C1b). Requests microphone + on-device speech
/// authorization and reports status, emitting the content-free permission funnel
/// events (`permission_prompted` / `permission_result`, kind = microphone | speech).
/// The priming screen (`VoicePrimingView`) explains the value + the on-device/private
/// promise BEFORE these system dialogs fire.
enum VoicePermissions {
    enum Status { case granted, denied, undetermined }

    static func micStatus() -> Status {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    static func speechStatus() -> Status {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .undetermined
        }
    }

    /// True only when BOTH mic and speech are granted (either already, or after asking).
    static var bothGranted: Bool { micStatus() == .granted && speechStatus() == .granted }

    /// Prime-then-request both. Only prompts for a permission still `.undetermined`;
    /// an already-decided one is reported, not re-asked. Returns true iff both granted.
    @MainActor
    static func request() async -> Bool {
        let mic = await requestMic()
        let speech = await requestSpeech()
        return mic && speech
    }

    @MainActor
    private static func requestMic() async -> Bool {
        guard micStatus() == .undetermined else { return micStatus() == .granted }
        Analytics.capture("permission_prompted", ["kind": "microphone"])
        let granted = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        Analytics.capture("permission_result", ["kind": "microphone", "granted": granted])
        return granted
    }

    @MainActor
    private static func requestSpeech() async -> Bool {
        guard speechStatus() == .undetermined else { return speechStatus() == .granted }
        Analytics.capture("permission_prompted", ["kind": "speech"])
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        let granted = (status == .authorized)
        Analytics.capture("permission_result", ["kind": "speech", "granted": granted])
        return granted
    }
}
