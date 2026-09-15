import SwiftUI

// Tap-to-toggle voice capture — the §7 active-capture state machine (states 3–5),
// Theme C C1c. Built against a STUBBED engine so the whole interaction (waveform,
// timer, live partial transcript, slide-to-cancel, release-to-save, haptics) is
// exercisable with NO microphone/STT yet. C1d drops a real engine in behind the
// same `VoiceCaptureEngine` protocol.

/// The recorder seam. C1c ships `StubVoiceCaptureEngine`; C1d adds an Apple-Speech
/// implementation with the identical surface (level from audio metering, partial
/// from on-device recognition).
@MainActor protocol VoiceCaptureEngine: AnyObject {
    /// Called frequently while listening: a 0…1 input level, elapsed seconds, and
    /// the running partial transcript.
    var onTick: ((CGFloat, TimeInterval, String) -> Void)? { get set }
    /// Called if capture can't start / the recognizer fails, with a `reason_code`
    /// (C1d). The stub never fails.
    var onFailure: ((String) -> Void)? { get set }
    func start()
    func finish() -> String   // stop + return the final transcript
    func cancel()
}

/// A fake engine that fabricates amplitude + a dribbling partial transcript, so the
/// UX can be built and demoed before any real capture exists.
@MainActor final class StubVoiceCaptureEngine: VoiceCaptureEngine {
    var onTick: ((CGFloat, TimeInterval, String) -> Void)?
    var onFailure: ((String) -> Void)?      // never fires; the stub always "works"
    private var running = false
    private var startedAt = Date()
    private var text = ""
    private var wordIndex = 0
    private let words = ["so", "I", "caught", "up", "with", "Maya", "today", "—", "she",
                         "starts", "the", "new", "job", "Monday", "and", "asked", "about",
                         "getting", "dinner", "next", "week"]

    func start() {
        running = true; startedAt = Date(); text = ""; wordIndex = 0
        Task { @MainActor in
            while running {
                let elapsed = Date().timeIntervalSince(startedAt)
                let level = CGFloat.random(in: 0.12...1.0)         // fake amplitude
                if Int(elapsed / 0.35) > wordIndex, wordIndex < words.count {  // dribble a word in
                    text += (text.isEmpty ? "" : " ") + words[wordIndex]; wordIndex += 1
                }
                onTick?(level, elapsed, text)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
    func finish() -> String { running = false; return text }
    func cancel() { running = false; text = "" }
}

struct VoiceCaptureView: View {
    /// The on-device engine by default (C1d); inject a stub for previews/tests.
    var makeEngine: () -> VoiceCaptureEngine = { AppleVoiceCaptureEngine() }
    /// Where this capture was launched from (C2 passes control/action_button/widget).
    var launchSource: String = "in_app"
    var onCaptured: (String) -> Void
    var onCancelled: () -> Void
    var onUndo: () -> Void = {}   // cancel the in-flight ingest from the saved-confirmation

    @Environment(\.dismiss) private var dismiss
    @State private var engine: VoiceCaptureEngine?
    @State private var listening = false
    @State private var levels: [CGFloat] = []      // rolling waveform buffer
    @State private var elapsed: TimeInterval = 0
    @State private var partial = ""
    @State private var noteText: String?        // inline note: empty / failure copy (§7 state 8)
    @State private var savedText: String?       // the captured transcript, shown as confirmation before dismiss

    private let barCount = 34

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let savedText {
                savedConfirmation(savedText)
                    .padding(.horizontal, 28).frame(maxWidth: 520)
            } else {
                VStack(spacing: 22) {
                    header
                    Spacer()
                    waveform
                    Text(timeLabel).font(.troveMono(13, .medium)).foregroundStyle(Theme.muted)
                        .opacity(listening ? 1 : 0)
                    transcript
                    Spacer()
                    recordButton
                    hint
                    if listening {
                        Button("Cancel") { cancelCapture() }
                            .font(.troveMono(12, .medium))
                            .foregroundStyle(Theme.danger)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 40)
                .frame(maxWidth: 520)
            }
        }
        .overlay(alignment: .topLeading) {
            // Full-screen cover (no swipe-to-dismiss) — an always-present close, except during
            // the brief saved-confirmation beat which dismisses itself.
            if savedText == nil {
                Button {
                    if listening { cancelCapture() } else { onCancelled(); dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(12)
                }
                .accessibilityLabel("Close")
                .padding(8)
            }
        }
    }

    // Confirmation: shows WHAT was captured (the transcript) so a voice note never resolves
    // silently, then auto-dismisses. The ingest is already running in the background.
    private func savedConfirmation(_ text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46)).foregroundStyle(Theme.gold)
            Text("Saved to Trove").font(.troveSerif(26)).foregroundStyle(Theme.ink)
            Text("“\(text)”")
                .font(.troveMono(13)).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center).lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
            Text("Filing the details now.").font(.troveMono(11)).foregroundStyle(Theme.muted)
            Button("Undo") { onUndo(); onCancelled(); dismiss() }
                .font(.troveMono(12, .medium)).foregroundStyle(Theme.gold)
                .padding(.top, 6)
        }
        .transition(.opacity)
    }

    // MARK: pieces

    private var header: some View {
        VStack(spacing: 6) {
            Text(listening ? "Listening…" : "Tap to record")
                .font(.troveSerif(26)).foregroundStyle(Theme.ink)
            Label("On-device · private", systemImage: "lock.fill")
                .font(.troveMono(11, .medium)).foregroundStyle(Theme.muted)
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(Theme.gold)
                    .frame(width: 4, height: barHeight(i))
            }
        }
        .frame(height: 64)
        .animation(.linear(duration: 0.05), value: levels)
    }

    @ViewBuilder private var transcript: some View {
        if let noteText {
            Text(noteText)
                .font(.troveMono(12)).foregroundStyle(Theme.danger)
                .multilineTextAlignment(.center)
        } else if listening {
            Text(partial.isEmpty ? "…" : partial)
                .font(.troveMono(13)).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center).lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                .transition(.opacity)
        } else {
            Color.clear.frame(height: 44)
        }
    }

    private var recordButton: some View {
        Button {
            if listening { finishCapture() } else { startListening() }
        } label: {
            Circle()
                .fill(listening ? Theme.danger : Theme.accent)
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                )
                .scaleEffect(listening ? 1.12 : 1)
                .animation(.spring(duration: 0.2), value: listening)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(listening ? "Stop recording" : "Start recording")
    }

    private var hint: some View {
        Text(listening ? "Tap to stop" : "Tap to record")
            .font(.troveMono(11)).foregroundStyle(Theme.muted)
    }

    // MARK: state transitions

    private func startListening() {
        noteText = nil
        let e = makeEngine()
        e.onTick = { lvl, el, txt in
            elapsed = el; partial = txt
            levels.append(lvl)
            if levels.count > barCount { levels.removeFirst(levels.count - barCount) }
        }
        e.onFailure = { code in handleFailure(code) }
        engine = e
        listening = true
        Haptics.commit()
        Analytics.capture("voice_capture_started", ["launch_source": launchSource])
        e.start()
    }

    private func finishCapture() {
        let text = (engine?.finish() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        resetListening()
        guard !text.isEmpty else {          // §7 state 8 — empty: keep the user here, don't save nothing
            noteText = "Didn't catch that — try again."
            Analytics.capture("voice_capture_failed", ["reason_code": "empty_transcript"])
            Haptics.soft(); return
        }
        Haptics.success()
        Analytics.capture("voice_capture_submitted", ["transcriber": "on_device_apple"])
        onCaptured(text)                    // ingest fires in the background (never lost to the dismiss)
        // Show WHAT was captured for a beat (never a silent resolve), then auto-dismiss.
        withAnimation(.easeInOut(duration: 0.2)) { savedText = text }
        Task { try? await Task.sleep(for: .seconds(2)); dismiss() }
    }

    // §7 state 8 — the engine couldn't start / recognizer failed: keep the capture flow
    // honest (never a silent fail), surface a note, and record the reason_code.
    private func handleFailure(_ code: String) {
        engine?.cancel()
        resetListening()
        Analytics.capture("voice_capture_failed", ["reason_code": code])
        noteText = "Couldn't start recording — check mic access in Settings."
        Haptics.soft()
    }

    private func cancelCapture() {
        engine?.cancel()
        resetListening()
        Haptics.soft()
        onCancelled()
        dismiss()
    }

    private func resetListening() {
        listening = false; levels = []; elapsed = 0; partial = ""; engine = nil
    }

    // MARK: helpers

    private func barHeight(_ i: Int) -> CGFloat {
        // Right-align the rolling buffer so the newest sample is at the leading edge.
        let idx = i - (barCount - levels.count)
        let lvl = (idx >= 0 && idx < levels.count) ? levels[idx] : 0
        return max(4, lvl * 60)
    }

    private var timeLabel: String {
        let s = Int(elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
