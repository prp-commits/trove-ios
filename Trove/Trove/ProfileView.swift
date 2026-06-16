import SwiftUI

struct ProfileView: View {
    @Environment(Session.self) private var session
    let user: User

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Trove").font(.troveSerif(34)).foregroundStyle(Theme.ink).padding(.top, 16)

                VStack(spacing: 6) {
                    Text(user.displayName).font(.troveSerif(24)).foregroundStyle(Theme.ink)
                    if let email = user.email {
                        Text(email).font(.troveMono(12)).foregroundStyle(Theme.ink2)
                    }
                    if user.emailVerified == false {
                        Text("Email not verified")
                            .font(.troveMono(10)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))

                Button("Sign out") { Task { await session.signOut() } }
                    .buttonStyle(PillButtonStyle(filled: false))

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .background(Theme.bg)
    }
}

/// Placeholder for tabs not built yet (Review, Pulse).
struct ComingSoonView: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 8) {
                Text(title).font(.troveSerif(30)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.troveMono(12)).foregroundStyle(Theme.muted)
            }
        }
    }
}
