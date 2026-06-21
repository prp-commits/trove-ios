import SwiftUI

struct ProfileView: View {
    @Environment(Session.self) private var session
    @Environment(NotificationManager.self) private var notifications
    @Environment(\.openURL) private var openURL
    let user: User
    @State private var testing = false
    @State private var testNote: String?
    @State private var calSyncing = false
    @State private var calStatus: String?

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

                // Calendar & Contacts (Phase C) — device sync keeps relationships
                // warm from whatever calendars live on the phone.
                VStack(spacing: 10) {
                    Text("CALENDAR & CONTACTS").font(.troveMono(11)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(calSyncing ? "Syncing…" : "Sync device calendar") { syncCalendar() }
                        .buttonStyle(PillButtonStyle(filled: false))
                        .disabled(calSyncing)
                    Text(calStatus ?? "Keep relationships warm using the calendars already on your phone — iCloud, Google, or Exchange. Trove reads who you meet with to notice when someone goes quiet; your address book never floods your Library.")
                        .font(.troveMono(10)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))

                // Feedback (M8) — the highest-signal channel for the beta.
                VStack(spacing: 10) {
                    Text("FEEDBACK").font(.troveMono(11)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Send feedback") { sendFeedback() }
                        .buttonStyle(PillButtonStyle(filled: false))
                    Text("Bugs, ideas, anything that felt off — it comes straight to us.")
                        .font(.troveMono(10)).foregroundStyle(Theme.muted)
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

    private func syncCalendar() {
        calSyncing = true; calStatus = nil
        Task {
            let granted = await CalendarSync.shared.requestAccess()
            guard granted else {
                calStatus = "Calendar access is off. Turn it on in Settings › Trove › Calendars (Full Access), then try again."
                calSyncing = false
                return
            }
            let events = CalendarSync.shared.collectEvents()
            do {
                let s = try await session.syncDeviceCalendar(events: events)
                let n = s.interactions ?? 0
                calStatus = "Synced \(events.count) event\(events.count == 1 ? "" : "s") · \(n) check-in\(n == 1 ? "" : "s") logged. Quiet friends will surface in Review and Pulse."
                Haptics.success()
            } catch {
                calStatus = (error as? APIError)?.errorDescription ?? "Sync failed. Try again."
            }
            calSyncing = false
        }
    }

    private func sendFeedback() {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let subject = "Trove beta feedback"
        let body = "\n\n—\nApp \(v) (\(b))"   // version only — never any note content
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
        if let url = URL(string: "mailto:\(Config.feedbackEmail)?subject=\(enc(subject))&body=\(enc(body))") {
            openURL(url)
        }
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
