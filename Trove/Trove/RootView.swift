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
                ProgressView().tint(Theme.ink)
            case .signedOut:
                SignInView()
            case .signedIn(let user):
                MainTabView(user: user)
            }
        }
        .environment(session)
        .task { await session.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            // Returning to the foreground may follow an external capture (Share
            // Extension), which doesn't bump dataVersion — refresh list screens.
            if phase == .active { session.markDataPossiblyChanged() }
        }
    }
}
