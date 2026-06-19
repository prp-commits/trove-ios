import SwiftUI

/// Routes between loading / signed-out / signed-in. Owns the Session.
struct RootView: View {
    @State private var session = Session()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch session.state {
            case .loading:
                SplashView()
            case .signedOut:
                SignInView()
            case .signedIn(let user):
                MainTabView(user: user)
            }
        }
        .environment(session)
        .environment(NotificationManager.shared)
        .task { await session.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Returning to the foreground may follow an external capture (Share
            // Extension), which doesn't bump dataVersion — refresh list screens.
            session.markDataPossiblyChanged()
            // Re-decide the day's nudge (D115) when we come back to the app.
            Task { await NotificationManager.shared.refresh() }
        }
    }
}
