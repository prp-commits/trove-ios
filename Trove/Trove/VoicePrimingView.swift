import SwiftUI

/// Voice-capture permission priming (Theme C, C1b / §7 state 2). A warm explainer
/// shown *before* the iOS microphone + speech dialogs, leading with the value and
/// the **on-device / private** promise — so the user understands both before a cold
/// system prompt. "Enable voice capture" triggers the real requests; "Not now"
/// defers gracefully. Mirrors `NudgePrimingView`.
struct VoicePrimingView: View {
    var onEnable: () -> Void
    var onSkip: () -> Void

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 38))
                    .foregroundStyle(Theme.gold)
                Text("Just say it")
                    .font(.troveSerif(28))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("Tap to record and Trove files what matters — who you saw, what you said you'd do. On the free tier it's transcribed right on your phone; your audio never leaves your device.")
                    .font(.troveMono(13))
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 6)
                Label("On-device · private", systemImage: "lock.fill")
                    .font(.troveMono(11, .medium))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 2)
                Spacer()
                Button("Enable voice capture") { onEnable() }
                    .buttonStyle(PillButtonStyle(filled: true))
                Button("Not now") { onSkip() }
                    .font(.troveMono(13))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 44)
            .frame(maxWidth: 480)
        }
        .interactiveDismissDisabled(true)   // make them choose, so the flow is deterministic
    }
}
