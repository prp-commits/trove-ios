import SwiftUI

/// Routes between loading / signed-out / signed-in. Owns the Session.
struct RootView: View {
    @State private var session = Session()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch session.state {
            case .loading:
                ProgressView().tint(Theme.ink)
            case .signedOut:
                SignInView()
            case .signedIn(let user):
                HomeView(user: user)
            }
        }
        .environment(session)
        .task { await session.bootstrap() }
    }
}
