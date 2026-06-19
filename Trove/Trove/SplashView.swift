import SwiftUI

/// Branded launch moment (P0 polish). Echoes the app icon's world — paper field,
/// gilt sparkle, serif "Trove" wordmark — shown while the session bootstraps
/// (which is also the Render cold-start window), so the wait reads as intentional
/// rather than a blank frame. The tagline lives on Sign-in, not here (a launch
/// moment flashes too briefly to read).
struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "sparkle")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.gold)
                Text("Trove")
                    .font(.troveSerif(54))
                    .foregroundStyle(Theme.ink)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.97)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
        }
    }
}
