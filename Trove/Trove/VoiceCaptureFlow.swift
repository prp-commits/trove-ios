import SwiftUI

/// A request to start voice capture, carrying the analytics `launch_source`.
struct VoiceTrigger: Equatable { let source: String }

/// The entire voice-capture flow as one reusable modifier (Theme C): permission gate →
/// priming (only if undetermined) → the tap-to-record surface as a **full-screen cover**
/// (direct, no composer, no sheet-on-sheet) → background ingest → "Saved to Trove" + Undo.
///
/// Used by BOTH the in-app mic and the Action-button / Shortcut reflex path, so pressing
/// the Action button lands you straight in the capture surface (D248 — the UX polish).
private struct VoiceCaptureModifier: ViewModifier {
    @Environment(Session.self) private var session
    @Binding var trigger: VoiceTrigger?
    var onIngested: () -> Void

    @State private var source = "in_app"
    @State private var showingCapture = false
    @State private var showingPriming = false
    @State private var deniedToast = false
    @State private var ingestTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $showingCapture) {
                // The confirmation of WHAT was captured (+ Undo) lives inside VoiceCaptureView now,
                // so there's no separate saved-toast here — just the denied toast below.
                VoiceCaptureView(launchSource: source,
                                 onCaptured: { saveVoice($0) },
                                 onCancelled: {},
                                 onUndo: { ingestTask?.cancel() })
            }
            .sheet(isPresented: $showingPriming) {
                VoicePrimingView(
                    onEnable: {
                        Task {
                            let ok = await VoicePermissions.request()
                            showingPriming = false
                            if ok { showingCapture = true } else { flashDenied() }
                        }
                    },
                    onSkip: { showingPriming = false }
                )
            }
            .overlay(alignment: .bottom) { toast }
            .animation(.spring(duration: 0.3), value: deniedToast)
            .onChange(of: trigger) { _, t in
                guard let t else { return }
                source = t.source
                trigger = nil                 // consume the request
                start()
            }
    }

    // Gate on permission: granted → straight in; undetermined → prime first; denied → nudge to Settings.
    private func start() {
        if VoicePermissions.bothGranted { showingCapture = true; return }
        if VoicePermissions.micStatus() == .denied || VoicePermissions.speechStatus() == .denied { flashDenied(); return }
        showingPriming = true
    }

    // Instant handoff (§7 state 4): fire the ingest in the background, show the toast; Undo cancels it.
    private func saveVoice(_ text: String) {
        ingestTask?.cancel()
        ingestTask = Task { _ = try? await session.ingestText(text); if !Task.isCancelled { onIngested() } }
    }

    private func flashDenied() {
        deniedToast = true
        Task { try? await Task.sleep(for: .seconds(3)); await MainActor.run { deniedToast = false } }
    }

    @ViewBuilder private var toast: some View {
        if deniedToast {
            Text("Enable microphone & speech in Settings to use voice")
                .font(.troveMono(12)).foregroundStyle(Theme.bg).multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.ink, in: Capsule()).padding(.bottom, 24)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

extension View {
    /// Attach the voice-capture flow. Set `trigger` to a `VoiceTrigger(source:)` to launch it.
    func voiceCapture(_ trigger: Binding<VoiceTrigger?>, onIngested: @escaping () -> Void = {}) -> some View {
        modifier(VoiceCaptureModifier(trigger: trigger, onIngested: onIngested))
    }
}
