//
//  TroveApp.swift
//  Trove
//
//  Created by Param Pandey on 6/16/26.
//

import SwiftUI

@main
struct TroveApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
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
