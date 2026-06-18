import SwiftUI

struct ProfileView: View {
    @Environment(Session.self) private var session
    @Environment(NotificationManager.self) private var notifications
    let user: User
    @State private var testing = false
    @State private var testNote: String?

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

                // Notifications (D115) — verify the right-time nudge flow.
                VStack(spacing: 10) {
                    Text("NOTIFICATIONS").font(.troveMono(11)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(testing ? "Sending…" : "Send a test nudge") {
                        testing = true; testNote = nil
                        Task {
                            await notifications.requestAuthorizationAndRegister()
                            await notifications.sendTest()
                            testing = false
                            testNote = "If nothing appears, there may be no nudge-worthy person right now (try after adding a birthday or an overdue contact)."
                        }
                    }
                    .buttonStyle(PillButtonStyle(filled: false))
                    .disabled(testing)
                    if let testNote {
                        Text(testNote).font(.troveMono(10)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(16)
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
