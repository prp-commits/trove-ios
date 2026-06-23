//
//  TroveApp.swift
//  Trove
//
//  Created by Param Pandey on 6/16/26.
//

import SwiftUI
import GoogleSignIn
import UIKit

/// Receives the APNs device token (remote push, D115 Build #2). A pure-SwiftUI app
/// can't get this callback, so we bridge a minimal app delegate. The token is handed
/// to NotificationManager, which registers it with the server (POST /api/devices).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in NotificationManager.shared.registerAPNsToken(hex) }
    }
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Non-fatal: remote push just won't arrive for this launch.
        print("[apns] registration failed: \(error.localizedDescription)")
    }
}

@main
struct TroveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                // Hand the Google OAuth redirect back to the SignIn SDK (Phase B).
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                // Trove's "Monad" palette is a fixed light "paper" theme (Theme.swift
                // hexes are non-adaptive). Without locking the scheme, a dark-mode
                // device flips system text (e.g. TextEditor/TextField input) to white
                // while our backgrounds stay light → invisible typing. Pin light mode
                // app-wide so the palette always renders as designed. (Real dark-mode
                // support would mean adaptive color sets — deferred to M7 polish.)
                .preferredColorScheme(.light)
        }
    }
}
