import SwiftUI

// Theme D (D3b) — the uncertainty-gated capture confirm (§1.5). Shown ONLY after a
// capture whose commitment extraction was low-confidence (Session gates on the
// threshold), so it never interrupts a confident capture. It doubles as the
// extraction/transcription QUALITY instrument: we record whether the user proceeded
// unchanged, edited, or dismissed — plus a coarse edit-distance bucket — and NEVER the
// text of either version (content-free, computed on-device).

extension Notification.Name {
    /// Posted by Session after a low-confidence commitment capture; MainTabView presents the sheet.
    static let troveCommitmentConfirm = Notification.Name("troveCommitmentConfirm")
}

/// Hand-off for the pending confirm (mirrors VoiceLaunch.pendingSource): the notification
/// is a bare signal, the payload is read from here.
enum CommitmentConfirmInbox {
    static var pending: PendingCommitmentConfirm?
}

struct CommitmentConfirmView: View {
    let commitment: PendingCommitmentConfirm
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var resolved = false   // guard against double-firing on swipe-dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A quick check").font(.troveMono(11, .medium)).tracking(0.5).foregroundStyle(Theme.muted)
            Text(commitment.isQuestion ? "Want to remember to ask this?" : "Want me to remember this?")
                .font(.troveSerif(24)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            // Editable so a mishearing is corrected in place — the "modified" quality signal.
            TextField("", text: $text, axis: .vertical)
                .font(.troveSerif(18)).foregroundStyle(Theme.ink)
                .lineLimit(1...4)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))

            Text("Edit it if I got it wrong, or dismiss if it's not something to track.")
                .font(.troveMono(11)).foregroundStyle(Theme.muted)

            HStack(spacing: 10) {
                Button("Not this") { resolveDismiss() }
                    .buttonStyle(PillButtonStyle(filled: false))
                Button(commitment.isQuestion ? "Yes, remind me" : "Yes, keep it") { resolveConfirm() }
                    .buttonStyle(PillButtonStyle(filled: true))
            }
            .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .onAppear {
            text = commitment.text
            Analytics.capture("commitment_confirm_shown", ["kind": commitment.kind])
        }
    }

    private func resolveConfirm() {
        let edited = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = !edited.isEmpty && edited != commitment.text
        let bucket = changed ? Self.editDistanceBucket(commitment.text, edited) : "none"
        Analytics.capture("commitment_confirm_resolved",
                          ["kind": commitment.kind,
                           "outcome": changed ? "modified" : "unchanged",
                           "edit_distance_bucket": bucket])
        resolved = true
        if changed { Task { await session.editCommitment(commitment.id, text: edited) } }
        Haptics.success()
        dismiss()
    }

    private func resolveDismiss() {
        Analytics.capture("commitment_confirm_resolved",
                          ["kind": commitment.kind, "outcome": "dismissed", "edit_distance_bucket": "none"])
        resolved = true
        Task { await session.dismissCommitment(commitment.id) }
        Haptics.soft()
        dismiss()
    }

    // Coarse, content-free edit-distance bucket (none | minor | major) computed on-device.
    // "minor" = a small correction (a name/word); "major" = a substantive rewrite. Only the
    // bucket leaves the device — never the text.
    static func editDistanceBucket(_ a: String, _ b: String) -> String {
        if a == b { return "none" }
        let d = levenshtein(a, b)
        let threshold = max(3, Int(Double(a.count) * 0.15))
        return d <= threshold ? "minor" : "major"
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }
}
