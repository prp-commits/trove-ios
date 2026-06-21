import SwiftUI

/// Calendar/Contacts permission priming (Phase C, slice 4), shown once in the
/// onboarding sequence right after the notification primer — a warm explainer
/// before the system dialog, so the value lands first. "Connect" requests access
/// and does the first sync; "Not now" defers (re-enableable later in Profile).
struct DeviceSyncPrimingView: View {
    var onConnect: () -> Void
    var onSkip: () -> Void

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 38))
                    .foregroundStyle(Theme.gold)
                Text("Stay close, automatically")
                    .font(.troveSerif(28))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("Connect the calendars and contacts already on your phone, and Trove quietly notices who you've seen, who's gone quiet, and whose birthday is coming up — so the right people surface on their own.")
                    .font(.troveMono(13))
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 6)
                Text("Stays private to your account. Your address book never floods your library, and you can unsync anytime.")
                    .font(.troveMono(11))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                Spacer()
                Button("Connect") { onConnect() }
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
        .interactiveDismissDisabled(true)
    }
}
