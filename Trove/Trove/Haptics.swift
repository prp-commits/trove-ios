import UIKit

/// One restrained, *semantic* haptic vocabulary (P0 polish). Award-tier apps use a
/// small, consistent set tied to meaning — never haptic-spam. Spend the budget on
/// the 3–4 gestures users do daily (capture, caught-up/act, swipe, snooze).
///
/// - `success`  — a meaningful completion: a capture filed, "Caught up", acted on a nudge.
/// - `commit`   — a deliberate commit: a Review swipe resolving left/right.
/// - `soft`     — a lighter acknowledgement: snooze / minor selection.
@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func commit()  { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func soft()    { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
