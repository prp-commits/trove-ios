import SwiftUI

struct MainTabView: View {
    let user: User
    @Environment(Session.self) private var session
    @Environment(NotificationManager.self) private var notifications
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(0)

            ReviewView()
                .tabItem { Label("Review", systemImage: "rectangle.portrait.on.rectangle.portrait") }
                .tag(1)

            PulseView()
                .tabItem { Label("Pulse", systemImage: "waveform.path.ecg") }
                .tag(2)

            ProfileView(user: user)
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(3)
        }
        .tint(Theme.ink)
        // Push / right-time delivery (D115): ask for permission + register on first
        // appearance after sign-in.
        .task {
            notifications.configure(session: session)
            await notifications.requestAuthorizationAndRegister()
        }
        // Tapping a nudge notification routes to Review.
        .onChange(of: notifications.pendingDeepLink) { _, ref in
            if ref != nil { tab = 1; notifications.pendingDeepLink = nil }
        }
    }
}
