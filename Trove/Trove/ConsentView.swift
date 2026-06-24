import SwiftUI

/// One-time data-consent screen (beta). Shown once per account, **before** the
/// value-first first-run capture — i.e. before any note leaves the device — so
/// consent is informed (the first capture is real third-party data → Anthropic).
/// Copy is the in-app surface from `docs/BETA_CONSENT.md`; the truth constraints are
/// load-bearing: "secured server, **not** end-to-end encrypted" — never "encrypted."
/// Gated by `@AppStorage("hasConsented")`; reset on sign-out so a new account on the
/// same device re-consents. Skipped for the demo/sandbox account.
struct ConsentView: View {
    var onAccept: () -> Void

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Spacer(minLength: 24)
                    Image(systemName: "lock.shield").font(.system(size: 32)).foregroundStyle(Theme.gold)
                    Text("Before we start —\nwhat Trove does with your stuff")
                        .font(.troveSerif(26)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Trove builds private notes about the people and topics you care about. A few honest things:")
                        .font(.troveMono(14)).foregroundStyle(Theme.ink2).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 14) {
                        point("sparkles", "Your notes help build profiles.",
                              "What you save is sent to a third-party AI provider to pull out the useful details, then stored on our secured server. It's not end-to-end encrypted.")
                        point("lock", "It's yours alone.",
                              "Your notes and the profiles you build are never shared or sold — they're private to your account.")
                        point("slider.horizontal.3", "You're in control.",
                              "Edit or delete anything anytime, or delete your whole account by emailing paramclaudeuse@gmail.com.")
                        point("chart.bar.xaxis", "Anonymous usage only.",
                              "We measure how the app is used with no personal content — no names, notes, or messages ever leave for analytics.")
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))

                    Button("Got it — continue") { onAccept() }
                        .buttonStyle(PillButtonStyle(filled: true))
                        .padding(.top, 4)
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
            }
        }
    }

    private func point(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.gold).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.troveMono(13, .medium)).foregroundStyle(Theme.ink)
                Text(body).font(.troveMono(12)).foregroundStyle(Theme.ink2).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
