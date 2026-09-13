import SwiftUI
import UIKit

// The monthly "showed up" receipt (Theme A, docs/BUILD_PLAN_THEME_A_RECEIPTS.md).
// A warm reflection surfaced at the top of Pulse: counts framed as what you DID
// (never a scoreboard of misses), with tap-through to the real people (provenance).
//
// Slice 4 (share export) adds an aggregate-only shareable image — counts, no names,
// content-free by construction — as the organic-distribution loop. See ReceiptShareCard.

/// The summary card. Taps open the detail sheet.
struct ReceiptCard: View {
    let receipt: MonthlyReceipt
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(receipt.monthLabel.uppercased())
                        .font(.troveMono(11, .medium)).foregroundStyle(Theme.muted)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                }

                if receipt.hasActivity {
                    Text(headline)
                        .font(.troveSerif(24)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !statChips.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(statChips, id: \.self) { chip in
                                Text(chip)
                                    .font(.troveMono(11, .medium)).foregroundStyle(Theme.ink2)
                                    .padding(.vertical, 5).padding(.horizontal, 10)
                                    .background(Theme.surface, in: Capsule())
                                    .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                            }
                        }
                    }
                } else {
                    Text("A fresh month — here's where it fills in.")
                        .font(.troveSerif(20)).foregroundStyle(Theme.ink)
                    Text("Every note you save and person you reach for shows up here.")
                        .font(.troveMono(12)).foregroundStyle(Theme.muted)
                }

                if let span = receipt.library.monthsSpan, span >= 1, receipt.library.people > 0 {
                    Text("Your library connects across \(span) month\(span == 1 ? "" : "s") · \(receipt.library.people) \(receipt.library.people == 1 ? "person" : "people")")
                        .font(.troveMono(11)).foregroundStyle(Theme.muted)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.gold.opacity(0.4), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { ReceiptAnalytics.viewedOnce(receipt, surface: "pulse") }
    }

    // Lead with the strongest positive so a quiet-on-people month never reads
    // "showed up for 0 people."
    private var headline: String {
        if receipt.showedUpPeople > 0 {
            let n = receipt.showedUpPeople
            return "You showed up for \(n) \(n == 1 ? "person" : "people")."
        }
        if receipt.rememberedNew > 0 {
            let n = receipt.rememberedNew
            return "You remembered \(n) new thing\(n == 1 ? "" : "s")."
        }
        let n = receipt.plansKept
        return "You kept \(n) plan\(n == 1 ? "" : "s")."
    }

    private var statChips: [String] {
        var out: [String] = []
        if receipt.reconnectedPeople > 0 { out.append("\(receipt.reconnectedPeople) reconnected") }
        if receipt.plansKept > 0 { out.append("\(receipt.plansKept) plan\(receipt.plansKept == 1 ? "" : "s") kept") }
        // Only surface "remembered" as a chip when it isn't already the headline.
        if receipt.rememberedNew > 0 && receipt.showedUpPeople > 0 {
            out.append("\(receipt.rememberedNew) remembered")
        }
        return out
    }
}

/// The detail sheet: the full breakdown + a provenance list of the people you
/// showed up for (names resolved from the library, so nothing extra ships in the
/// receipt payload itself). Each person taps through to their profile.
struct ReceiptDetailView: View {
    let receipt: MonthlyReceipt
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var names: [Int: String] = [:]
    @State private var shareItem: ShareImage?          // slice 4: the rendered aggregate-only export

    private struct PersonRef: Hashable { let id: Int; let name: String }
    private struct ShareImage: Identifiable { let id = UUID(); let image: UIImage }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(receipt.monthLabel).font(.troveSerif(30)).foregroundStyle(Theme.ink)
                        Text("How you showed up.").font(.troveMono(12)).foregroundStyle(Theme.muted)
                    }

                    VStack(spacing: 10) {
                        statRow(receipt.showedUpPeople, "Showed up for", receipt.showedUpPeople == 1 ? "person" : "people")
                        statRow(receipt.reconnectedPeople, "Reconnected", "after a quiet stretch")
                        statRow(receipt.plansKept, "Plans kept", "moments you showed up for")
                        statRow(receipt.rememberedNew, "Remembered", "new notes about \(receipt.rememberedAboutPeople) \(receipt.rememberedAboutPeople == 1 ? "profile" : "profiles")")
                    }

                    if !receipt.showedUpEntityIds.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("People you showed up for")
                                .font(.troveSerif(20)).foregroundStyle(Theme.ink)
                            ForEach(receipt.showedUpEntityIds, id: \.self) { id in
                                if let name = names[id] { personRow(id: id, name: name) }
                            }
                            if names.isEmpty {
                                Text("Loading…").font(.troveMono(11)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Your month")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PersonRef.self) { p in
                EntityDetailView(entityId: p.id, name: p.name)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.muted)
                }
                // Share an aggregate-only image (never for an empty month — nothing to
                // share, and the warmth rule forbids a "0" scoreboard going public).
                if receipt.hasActivity {
                    ToolbarItem(placement: .primaryAction) {
                        Button { presentShare() } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel("Share your month")
                    }
                }
            }
        }
        .task { await loadNames() }
        .sheet(item: $shareItem) { item in
            // completed == true only → a real share happened (cancel emits nothing).
            ShareSheet(items: [item.image]) { activityType, completed in
                if completed {
                    ReceiptAnalytics.shared(receipt, destination: shareDestination(activityType))
                }
                shareItem = nil
            }
        }
    }

    // Render the aggregate-only card to an image, then present the system share sheet.
    @MainActor private func presentShare() {
        Haptics.soft()
        let renderer = ImageRenderer(content: ReceiptShareCard(receipt: receipt))
        renderer.scale = 3   // crisp on any device; ~1080×1350 from the 360×450 card
        guard let image = renderer.uiImage else { return }
        shareItem = ShareImage(image: image)
    }

    // Map the chosen activity → the content-free share_destination enum
    // (image | link | messages | other). No app or recipient identity is recorded.
    private func shareDestination(_ type: UIActivity.ActivityType?) -> String {
        switch type {
        case .some(.message):                            return "messages"
        case .some(.mail), .some(.copyToPasteboard):     return "link"
        case .some(.saveToCameraRoll), .some(.airDrop):  return "image"
        default:                                         return "other"
        }
    }

    private func personRow(id: Int, name: String) -> some View {
        NavigationLink(value: PersonRef(id: id, name: name)) {
            HStack {
                Text(name).font(.troveSerif(17)).foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statRow(_ value: Int, _ label: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(value)").font(.troveSerif(26)).foregroundStyle(Theme.ink)
                .frame(minWidth: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.troveMono(12, .medium)).foregroundStyle(Theme.ink2)
                Text(unit).font(.troveMono(11)).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }

    // Resolve ids → names from the library (the receipt itself carries no names).
    private func loadNames() async {
        guard names.isEmpty, !receipt.showedUpEntityIds.isEmpty else { return }
        guard let entities = try? await session.loadEntities() else { return }
        let wanted = Set(receipt.showedUpEntityIds)
        names = Dictionary(uniqueKeysWithValues:
            entities.filter { wanted.contains($0.id) }.map { ($0.id, $0.name) })
    }
}

/// The aggregate-only share image (Theme A slice 4). Content-free **by construction**:
/// first-person counts + the compounding line, and **never a name** — safe to post.
/// This is the organic-distribution loop; do not render `showedUpEntityIds` here.
struct ReceiptShareCard: View {
    let receipt: MonthlyReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TROVE")
                .font(.troveMono(13, .semibold)).tracking(3).foregroundStyle(Theme.gold)

            Spacer(minLength: 0)

            Text(receipt.monthLabel.uppercased())
                .font(.troveMono(12, .medium)).tracking(1).foregroundStyle(Theme.muted)
            Text(shareHeadline)
                .font(.troveSerif(34)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if !subLines.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(subLines, id: \.self) { line in
                        Text(line).font(.troveMono(13)).foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 16)
            }

            Spacer(minLength: 0)

            Text("a private relationship second brain")
                .font(.troveMono(10)).foregroundStyle(Theme.muted)
        }
        .padding(28)
        .frame(width: 360, height: 450, alignment: .leading)
        .background(Theme.bg)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .stroke(Theme.gold.opacity(0.5), lineWidth: 2)
                .padding(8)
        )
    }

    // First-person, aggregate — mirrors the card's strongest-positive rule so a
    // quiet-on-people month never posts "I showed up for 0 people."
    private var shareHeadline: String {
        if receipt.showedUpPeople > 0 {
            let n = receipt.showedUpPeople
            return "I showed up for \(n) \(n == 1 ? "person" : "people")."
        }
        if receipt.rememberedNew > 0 {
            let n = receipt.rememberedNew
            return "I remembered \(n) new thing\(n == 1 ? "" : "s")."
        }
        let n = receipt.plansKept
        return "I kept \(n) plan\(n == 1 ? "" : "s")."
    }

    private var subLines: [String] {
        var out: [String] = []
        if receipt.reconnectedPeople > 0 {
            out.append("Reconnected with \(receipt.reconnectedPeople) after a quiet stretch")
        }
        if receipt.plansKept > 0 && receipt.showedUpPeople > 0 {
            out.append("Kept \(receipt.plansKept) plan\(receipt.plansKept == 1 ? "" : "s")")
        }
        if let span = receipt.library.monthsSpan, span >= 1, receipt.library.people > 0 {
            out.append("My library spans \(span) month\(span == 1 ? "" : "s") · \(receipt.library.people) \(receipt.library.people == 1 ? "person" : "people")")
        }
        return out
    }
}

/// Thin wrapper over `UIActivityViewController`. Unlike `ShareLink`, this surfaces
/// the completion (activity + completed) so we can attribute a content-free
/// `share_destination` — and emit nothing at all when the user cancels.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (UIActivity.ActivityType?, Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { activityType, completed, _, _ in
            onComplete(activityType, completed)
        }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Fires `receipt_viewed` at most once per period per app run (content-free).
enum ReceiptAnalytics {
    private static var seen: Set<String> = []

    @MainActor
    static func viewedOnce(_ r: MonthlyReceipt, surface: String) {
        guard !seen.contains(r.period) else { return }
        seen.insert(r.period)
        Analytics.capture("receipt_viewed", [
            "period": r.period,
            "surface": surface,
            "showed_up_bucket": bucket(r.showedUpPeople),
            "remembered_bucket": bucket(r.rememberedNew),
            "has_activity": r.hasActivity,
        ])
    }

    /// Fires `receipt_shared` on a completed share (content-free: buckets, no names).
    /// Not deduped — each completed share is a distinct organic-distribution signal.
    @MainActor
    static func shared(_ r: MonthlyReceipt, destination: String) {
        Analytics.capture("receipt_shared", [
            "period": r.period,
            "share_destination": destination,
            "showed_up_bucket": bucket(r.showedUpPeople),
        ])
    }

    private static func bucket(_ n: Int) -> String {
        switch n {
        case 0: return "0"
        case 1...3: return "1-3"
        case 4...10: return "4-10"
        default: return "11+"
        }
    }
}
