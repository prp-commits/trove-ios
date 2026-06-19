import SwiftUI

struct MainTabView: View {
    let user: User
    @Environment(Session.self) private var session
    @Environment(NotificationManager.self) private var notifications
    @State private var tab = 0
    @State private var showNudgePriming = false
    @AppStorage("hasPrimedNudges") private var hasPrimedNudges = false

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
        // Push / right-time delivery (D115): prime BEFORE the system prompt. Only
        // show the warm explainer when status is undetermined and we haven't asked;
        // otherwise just (re)register — already-determined states never re-prompt.
        .task {
            notifications.configure(session: session)
            let status = await notifications.authorizationStatus()
            if status == .notDetermined && !hasPrimedNudges {
                showNudgePriming = true
            } else {
                await notifications.requestAuthorizationAndRegister()
            }
        }
        .sheet(isPresented: $showNudgePriming) {
            NudgePrimingView(
                onEnable: {
                    hasPrimedNudges = true
                    showNudgePriming = false
                    Task { await notifications.requestAuthorizationAndRegister() }
                },
                onSkip: {
                    hasPrimedNudges = true
                    showNudgePriming = false
                }
            )
        }
        // Tapping a nudge notification routes to Review.
        .onChange(of: notifications.pendingDeepLink) { _, ref in
            if ref != nil { tab = 1; notifications.pendingDeepLink = nil }
        }
    }
}
