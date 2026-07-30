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
final class AppDelegate: NSObject, UIApplicationDelegate, URLSessionDataDelegate {
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

    // MARK: - D231: background share-upload completion

    /// Completion handlers iOS hands us when it relaunches the app to finish a background upload the
    /// share extension started but couldn't finish (it was killed when the sheet dismissed). Keyed by
    /// the session identifier.
    private var bgUploadCompletions: [String: () -> Void] = [:]

    /// iOS relaunches us (often in the background) with the session identifier once a background
    /// share-upload has events to deliver. We recreate a session with that exact identifier so its
    /// delegate callbacks land here, and stash the completion handler to call when they're done.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        bgUploadCompletions[identifier] = completionHandler
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.sharedContainerIdentifier = "group.ai.trovestore.Trove"
        _ = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // The server already created the note; we don't need the response — just tidy the temp file.
        if let path = task.taskDescription { try? FileManager.default.removeItem(atPath: path) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let id = session.configuration.identifier else { return }
        let handler = bgUploadCompletions.removeValue(forKey: id)
        session.finishTasksAndInvalidate()
        DispatchQueue.main.async { handler?() }
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
