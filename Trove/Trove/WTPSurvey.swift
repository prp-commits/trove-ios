import SwiftUI

// The willingness-to-pay probe (Theme B, B2) — the Sean-Ellis disappointment test.
// Surfaced ONCE, after the user has clearly gotten value, never nagged. Content-free:
// only the `response` enum leaves the device. It's the instrument that informs the
// buyer/price fork ($10 consumer vs $20 prosumer) before any paywall is built.

extension Notification.Name {
    /// Posted when the WTP survey should be shown (a value moment, user is eligible).
    static let troveWTPSurvey = Notification.Name("troveWTPSurvey")
}

@MainActor
enum WTPSurvey {
    private static let doneKey = "wtp.done"            // shown once, ever
    private static let countKey = "wtp.valueMoments"
    private static let surveyAfter = 2                 // ask only once value is real (2nd+ moment)

    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }
    static func markDone() { UserDefaults.standard.set(true, forKey: doneKey) }

    /// Called from `Analytics.noteValueMoment()` (a successful Ask / acted nudge / receipt
    /// view) — already demo-excluded there. After the user has felt the value and hasn't
    /// been asked, request the survey once, a beat later so it never interrupts the moment.
    static func noteValueMoment() {
        guard !isDone else { return }
        let n = UserDefaults.standard.integer(forKey: countKey) + 1
        UserDefaults.standard.set(n, forKey: countKey)
        guard n >= surveyAfter else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !isDone { NotificationCenter.default.post(name: .troveWTPSurvey, object: nil) }
        }
    }
}

/// The one-question WTP sheet. Self-contained: fires `disappointment_survey_shown` on
/// appear (and marks the probe done so it's truly once), `disappointment_survey_answered`
/// on a choice. Content-free — the wording never leaves the device, only the enum.
struct DisappointmentSurveyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A quick one").font(.troveMono(11, .medium)).tracking(0.5).foregroundStyle(Theme.muted)
            Text("How would you feel if you could no longer use Trove?")
                .font(.troveSerif(24)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                choice("Very disappointed", "very", filled: true)
                choice("Somewhat disappointed", "somewhat", filled: false)
                choice("Not disappointed", "not", filled: false)
            }
            .padding(.top, 4)

            Button("Skip") { dismiss() }
                .font(.troveMono(12)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .onAppear {
            Analytics.capture("disappointment_survey_shown")
            WTPSurvey.markDone()      // once, ever — whether or not they answer
        }
    }

    private func choice(_ label: String, _ response: String, filled: Bool) -> some View {
        Button(label) {
            Analytics.capture("disappointment_survey_answered", ["response": response])
            dismiss()
        }
        .buttonStyle(PillButtonStyle(filled: filled))
    }
}
