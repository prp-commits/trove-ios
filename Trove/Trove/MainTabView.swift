import SwiftUI

struct MainTabView: View {
    let user: User

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack") }

            ComingSoonView(title: "Review", subtitle: "Your nudge deck lands next.")
                .tabItem { Label("Review", systemImage: "rectangle.portrait.on.rectangle.portrait") }

            ComingSoonView(title: "Pulse", subtitle: "Who needs attention, at a glance.")
                .tabItem { Label("Pulse", systemImage: "waveform.path.ecg") }

            ProfileView(user: user)
                .tabItem { Label("Profile", systemImage: "person") }
        }
        .tint(Theme.ink)
    }
}
