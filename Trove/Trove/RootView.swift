import SwiftUI

/// Routes between loading / signed-out / signed-in. Owns the Session.
struct RootView: View {
    @State private var session = Session()
    @State private var minSplashDone = false   // keep the splash up a beat even on a fast bootstrap
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Environment(\.scenePhase) private var scenePhase

    /// Show the splash while bootstrapping AND until a minimum on-screen time has
    /// passed, so a warm start doesn't flash it for a split second.
    private var showSplash: Bool {
        if case .loading = session.state { return true }
        return !minSplashDone
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch session.state {
            case .loading:
                Color.clear            // the splash overlay covers this
            case .signedOut:
                SignInView()
            case .signedIn(let user):
                // Value-first first-run (#1) before the app + any permission ask.
                // A non-empty library (demo / returning user) self-skips inside.
                if hasOnboarded {
                    MainTabView(user: user)
                } else {
                    FirstRunView(onComplete: { hasOnboarded = true })
                }
            }

            if showSplash {
                SplashView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showSplash)
        .environment(session)
        .environment(NotificationManager.shared)
        .task { await session.bootstrap() }
        .task {
            // Minimum splash dwell (~1.2s): lets the fade-in finish and adds a calm hold.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            minSplashDone = true
        }
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
