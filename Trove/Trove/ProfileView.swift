import SwiftUI
import UIKit
import PhotosUI

struct ProfileView: View {
    @Environment(Session.self) private var session
    @Environment(NotificationManager.self) private var notifications
    @Environment(\.openURL) private var openURL
    let user: User
    @State private var testing = false
    @State private var editing = false
    @State private var testNote: String?
    @State private var calWorking = false
    @State private var calStatus: String?
    @State private var calAuthorized = false
    @State private var calDenied = false
    @AppStorage(DeviceSync.enabledKey) private var deviceSyncEnabled = false
    @AppStorage(DeviceSync.lastSyncKey) private var lastSyncAt = 0.0
    @State private var videoCaptureOn = false
    @State private var showRecentCaptures = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Trove").font(.troveSerif(34)).foregroundStyle(Theme.ink).padding(.top, 16)

                VStack(spacing: 12) {
                    AvatarView(photoUrl: user.photoUrl, name: user.displayName, size: 76)
                    VStack(spacing: 4) {
                        Text(user.displayName).font(.troveSerif(24)).foregroundStyle(Theme.ink)
                        if let email = user.email {
                            Text(email).font(.troveMono(12)).foregroundStyle(Theme.ink2)
                        }
                        if user.emailVerified == false {
                            Text("Email not verified")
                                .font(.troveMono(10)).foregroundStyle(Theme.muted)
                        }
                    }
                    Button("Edit profile") { editing = true }
                        .buttonStyle(PillButtonStyle(filled: false))
                        .padding(.top, 2)
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

                // Video capture (D141) — share a reel → summarized into insights.
                videoSection

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
        .task { refreshCalState(); await loadVideoState() }
        .sheet(isPresented: $editing) { EditProfileView(user: user) }
        .sheet(isPresented: $showRecentCaptures) { NavigationStack { RecentCapturesView() } }
    }

    // MARK: Video capture (D141)

    @ViewBuilder private var videoSection: some View {
        VStack(spacing: 10) {
            Text("VIDEO CAPTURE").font(.troveMono(11)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: Binding(
                get: { videoCaptureOn },
                set: { on in videoCaptureOn = on; Task { try? await session.setVideoCapture(on) } }
            )) {
                Text("Save reels & videos").font(.troveMono(13)).foregroundStyle(Theme.ink)
            }
            .tint(Theme.gold)
            Text("Share a reel, Short, or TikTok to Trove and it pulls out the useful details. The video link is sent to a third-party video provider to summarize it.")
                .font(.troveMono(10)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Recent captures") { showRecentCaptures = true }
                .buttonStyle(PillButtonStyle(filled: false))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))
    }

    private func loadVideoState() async {
        if let conns = try? await session.loadConnections() { videoCaptureOn = conns.video ?? false }
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

// MARK: - Avatar

/// A circular avatar that renders either a remote `http(s)` photo (e.g. Google) or
/// an inline `data:` URI (a user-picked photo), falling back to initials.
struct AvatarView: View {
    let photoUrl: String?
    let name: String
    var size: CGFloat = 76

    @State private var uiImage: UIImage?

    var body: some View {
        ZStack {
            if let uiImage {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                Circle().fill(Theme.line)
                Text(initials).font(.troveSerif(size * 0.42)).foregroundStyle(Theme.ink2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: photoUrl) { await load() }
    }

    private var initials: String {
        let s = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? "·" : s.uppercased()
    }

    private func load() async {
        uiImage = nil
        guard let s = photoUrl, !s.isEmpty else { return }
        if s.hasPrefix("data:") {
            guard let comma = s.firstIndex(of: ","),
                  let data = Data(base64Encoded: String(s[s.index(after: comma)...])) else { return }
            uiImage = UIImage(data: data)
        } else if let url = URL(string: s),
                  let (data, _) = try? await URLSession.shared.data(from: url) {
            uiImage = UIImage(data: data)
        }
    }
}

// MARK: - Edit profile (name + photo)

/// Minimal account editing for the beta: name + avatar. Email is read-only (provider
/// identity). Password change + account deletion are a post-beta "Account management"
/// pass (IOS_ROADMAP). The photo is downscaled to a small JPEG and sent as a `data:`
/// URI via PATCH /auth/me.
struct EditProfileView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let user: User

    @State private var firstName: String
    @State private var lastName: String
    @State private var photoUrl: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var saving = false
    @State private var error: String?

    init(user: User) {
        self.user = user
        _firstName = State(initialValue: user.firstName ?? "")
        _lastName  = State(initialValue: user.lastName ?? "")
        _photoUrl  = State(initialValue: user.photoUrl)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 12) {
                        AvatarView(photoUrl: photoUrl, name: [firstName, lastName].joined(separator: " "), size: 96)
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Text("Change photo").font(.troveMono(13, .medium)).foregroundStyle(Theme.gold)
                        }
                    }
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        field("First name", $firstName)
                        field("Last name", $lastName)
                    }

                    if let error {
                        Text(error).font(.troveMono(12)).foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(20)
                .frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
            .background(Theme.bg)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }
                        .disabled(saving || firstName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: pickerItem) { _, item in Task { await loadPhoto(item) } }
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.troveMono(10)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField(label, text: text)
                .font(.troveMono(15)).foregroundStyle(Theme.ink)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusField))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusField).stroke(Theme.line, lineWidth: 1))
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) else {
            error = "Couldn't load that image."; return
        }
        let small = ui.avatarDownscaled(to: 256)
        guard let jpeg = small.jpegData(compressionQuality: 0.7) else { return }
        photoUrl = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }

    private func save() {
        saving = true; error = nil
        Task {
            do {
                try await session.updateProfile(
                    firstName: firstName.trimmingCharacters(in: .whitespaces),
                    lastName: lastName.trimmingCharacters(in: .whitespaces),
                    photoUrl: photoUrl)
                Haptics.success()
                dismiss()
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
                saving = false
            }
        }
    }
}

private extension UIImage {
    /// Aspect-preserving downscale to a max dimension — keeps the avatar payload small.
    func avatarDownscaled(to maxDim: CGFloat) -> UIImage {
        let m = max(size.width, size.height)
        guard m > maxDim else { return self }
        let s = maxDim / m
        let newSize = CGSize(width: size.width * s, height: size.height * s)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
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
