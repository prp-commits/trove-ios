import SwiftUI

/// M0 placeholder for the authenticated app. Confirms the round-trip works
/// (token stored, /auth/me validated). Replaced by the Library + tab bar in M1.
struct HomeView: View {
    @Environment(Session.self) private var session
    let user: User

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Text("Trove")
                .font(.troveSerif(40))
                .foregroundStyle(Theme.ink)

            VStack(spacing: 6) {
                Text("You're signed in")
                    .font(.troveMono(13))
                    .foregroundStyle(Theme.muted)
                Text(user.displayName)
                    .font(.troveSerif(24))
                    .foregroundStyle(Theme.ink)
                if let email = user.email {
                    Text(email)
                        .font(.troveMono(12))
                        .foregroundStyle(Theme.ink2)
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1)
            )

            Text("Library, capture, nudges & Pulse land next.")
                .font(.troveMono(12))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Sign out") {
                Task { await session.signOut() }
            }
            .buttonStyle(PillButtonStyle(filled: false))
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }
}
