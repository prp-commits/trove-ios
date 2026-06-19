import SwiftUI

// The "Monad" visual system, ported from the web app's CSS variables so brand
// fidelity holds across web + iOS. (Hexes mirror public/styles.css :root.)

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

enum Theme {
    static let bg = Color(hex: 0xf6f3f1)          // paper canvas
    static let surface = Color(hex: 0xffffff)     // card / sheet
    static let ink = Color(hex: 0x000000)         // primary text & action
    static let ink2 = Color(hex: 0x4e4d4d)        // secondary text
    static let muted = Color(hex: 0x797776)       // tertiary text
    static let line = Color(hex: 0xe7e2dd)        // warm border
    static let accent = Color(hex: 0x242424)      // primary button bg
    static let accentSoft = Color(hex: 0xcfdaf5)  // atmosphere wash
    static let danger = Color(hex: 0x8a1f1f)
    static let gold = Color(hex: 0xc4a86b)        // the icon's gilt — brand accent (splash/wordmark)

    // Spacing + radii (roadmap §6 shape language).
    static let radiusCard: CGFloat = 28
    static let radiusField: CGFloat = 14
}

extension Font {
    /// Display / titles — serif voice (system serif now; bundle Noto Serif later).
    static func troveSerif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// UI voice — monospace (system mono now; bundle IBM Plex Mono later).
    static func troveMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Primary pill button (fully rounded). `filled` = accent fill; otherwise outlined.
struct PillButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.troveMono(15, .medium))
            .foregroundStyle(filled ? Color.white : Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 22)
            .background(filled ? Theme.accent : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: filled ? 0 : 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#if canImport(UIKit)
import UIKit

/// Dismiss the keyboard from anywhere by resigning the current first responder.
/// Powers the "Done" key on text-entry screens (works for multi-field forms and
/// TextEditors, where Return inserts a newline rather than dismissing).
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
#endif
