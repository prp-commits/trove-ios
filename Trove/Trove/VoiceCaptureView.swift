import SwiftUI

// Hold-to-talk voice capture — the §7 active-capture state machine (states 3–5),
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

    @Environment(\.dismiss) private var dismiss
    @State private var engine: VoiceCaptureEngine?
    @State private var listening = false
    @State private var levels: [CGFloat] = []      // rolling waveform buffer
    @State private var elapsed: TimeInterval = 0
    @State private var partial = ""
    @State private var cancelArmed = false
    @State private var noteText: String?        // inline note: empty / failure copy (§7 state 8)

    private let barCount = 34
    private let cancelThreshold: CGFloat = -90      // drag up this far to arm cancel

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 22) {
                header
                Spacer()
                waveform
                Text(timeLabel).font(.troveMono(13, .medium)).foregroundStyle(Theme.muted)
                    .opacity(listening ? 1 : 0)
                transcript
                Spacer()
                holdButton
                hint
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 40)
            .frame(maxWidth: 520)
        }
        .interactiveDismissDisabled(listening)   // don't let a swipe kill an in-progress capture
    }

    // MARK: pieces

    private var header: some View {
        VStack(spacing: 6) {
            Text(listening ? "Listening…" : "Hold to talk")
                .font(.troveSerif(26)).foregroundStyle(Theme.ink)
            Label("On-device · private", systemImage: "lock.fill")
                .font(.troveMono(11, .medium)).foregroundStyle(Theme.muted)
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(cancelArmed ? Theme.danger.opacity(0.6) : Theme.gold)
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

    private var holdButton: some View {
        Circle()
            .fill(listening ? (cancelArmed ? Theme.danger : Theme.accent) : Theme.accent)
            .frame(width: 84, height: 84)
            .overlay(
                Image(systemName: cancelArmed ? "xmark" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
            )
            .scaleEffect(listening ? 1.12 : 1)
            .animation(.spring(duration: 0.2), value: listening)
            .animation(.easeOut(duration: 0.12), value: cancelArmed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !listening { startListening() }
                        cancelArmed = g.translation.height < cancelThreshold
                    }
                    .onEnded { _ in
                        if cancelArmed { cancelCapture() } else { finishCapture() }
                    }
            )
    }

    private var hint: some View {
        Text(listening ? (cancelArmed ? "Release to cancel" : "Slide up to cancel") : "Press and hold")
            .font(.troveMono(11)).foregroundStyle(cancelArmed ? Theme.danger : Theme.muted)
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
        onCaptured(text)                    // parent dismisses + shows the saved toast + Undo
        dismiss()
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
        listening = false; cancelArmed = false; levels = []; elapsed = 0; partial = ""; engine = nil
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
