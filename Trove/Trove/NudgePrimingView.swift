import SwiftUI

/// Permission priming (P0 polish). A warm explainer shown *before* the iOS
/// notification dialog, so the user understands the value first — this lifts opt-in
/// (the whole moat depends on push being on) and avoids a cold system prompt.
/// "Turn on nudges" triggers the real system prompt; "Not now" defers gracefully.
struct NudgePrimingView: View {
    var onEnable: () -> Void
    var onSkip: () -> Void

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "bell.badge")
                    .font(.system(size: 38))
                    .foregroundStyle(Theme.gold)
                Text("Show up at the right moment")
                    .font(.troveSerif(28))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("Trove will quietly tap you on the shoulder — a birthday tomorrow, a friend you haven't spoken to in a while, or an evening nudge to capture a moment worth keeping. Gentle, never spam.")
                    .font(.troveMono(13))
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 6)
                Spacer()
                Button("Turn on nudges") { onEnable() }
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
        .interactiveDismissDisabled(true)   // make them choose, so the flag is always set
    }
}
