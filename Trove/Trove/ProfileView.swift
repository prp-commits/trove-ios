import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(Session.self) private var session
    @Environment(NotificationManager.self) private var notifications
    @Environment(\.openURL) private var openURL
    let user: User
    @State private var testing = false
    @State private var testNote: String?
    @State private var calWorking = false
    @State private var calStatus: String?
    @State private var calAuthorized = false
    @State private var calDenied = false
    @AppStorage(DeviceSync.enabledKey) private var deviceSyncEnabled = false
    @AppStorage(DeviceSync.lastSyncKey) private var lastSyncAt = 0.0

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

                // Calendar & Contacts (Phase C) — device sync runs silently once
                // connected; the control here is the state + Unsync.
                connectionsSection



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
        .task { refreshCalState() }
    }

    // MARK: Connections (Phase C) — state-driven; sync is silent, control is Unsync.

    @ViewBuilder private var connectionsSection: some View {
        VStack(spacing: 10) {
            Text("CALENDAR & CONTACTS").font(.troveMono(11)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            if calAuthorized && deviceSyncEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold)
                    Text("Connected").font(.troveMono(13, .medium)).foregroundStyle(Theme.ink)
                    Spacer()
                }
                Text(lastSyncedLine).font(.troveMono(10)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(calWorking ? "Unsyncing…" : "Unsync") { unsyncCalendar() }
                    .buttonStyle(PillButtonStyle(filled: false))
                    .disabled(calWorking)
                Text("Trove stops syncing and forgets what it built. To fully revoke access, turn it off in Settings.")
                    .font(.troveMono(10)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if calDenied {
                Text("Calendar access is off. Turn it on in Settings so Trove can notice who's gone quiet and remember birthdays.")
                    .font(.troveMono(10)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(PillButtonStyle(filled: false))
            } else {
                Text("Connect the calendars and contacts on your phone — iCloud, Google, or Exchange. Trove notices who you've seen, who's drifting, and whose birthday is near. Your address book never floods your library.")
                    .font(.troveMono(10)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(calWorking ? "Connecting…" : "Connect calendar & contacts") { connectCalendar() }
                    .buttonStyle(PillButtonStyle(filled: false))
                    .disabled(calWorking)
            }

            if let calStatus {
                Text(calStatus).font(.troveMono(10)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))
    }

    private var lastSyncedLine: String {
        guard lastSyncAt > 0 else { return "Syncing on each app open." }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .full
        return "Last synced \(f.localizedString(for: Date(timeIntervalSince1970: lastSyncAt), relativeTo: Date()))."
    }

    private func refreshCalState() {
        calAuthorized = CalendarSync.shared.isAuthorized
        calDenied = CalendarSync.shared.isDenied
    }

    private func connectCalendar() {
        calWorking = true; calStatus = nil
        Task {
            let granted = await DeviceSync.connect(session)
            refreshCalState()
            calStatus = granted
                ? "Connected — your people will start surfacing in Review and Pulse."
                : "Calendar access is off. Turn it on in Settings, then come back."
            calWorking = false
            if granted { Haptics.success() }
        }
    }

    private func unsyncCalendar() {
        calWorking = true; calStatus = nil
        Task {
            await DeviceSync.unsync(session)
            refreshCalState()
            calStatus = "Unsynced. Trove stopped syncing and forgot what it built."
            calWorking = false
            Haptics.soft()
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
