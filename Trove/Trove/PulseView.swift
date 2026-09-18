import SwiftUI

struct PulseView: View {
    @Binding var receiptDeepLinkPeriod: String?         // Theme A slice 6: a tapped receipt push ("YYYY-MM")
    @Environment(Session.self) private var session
    @State private var state: Loadable<[PulseItem]> = .idle
    @State private var horizon: [HorizonItem] = []      // "On the Horizon" (D149)
    @State private var confirming: ConfirmTarget?
    @State private var receipt: MonthlyReceipt?         // Theme A: monthly "showed up" receipt
    @State private var showingReceipt = false
    @State private var deepLinkedReceipt: MonthlyReceipt?   // slice 6: the receipt a push opened (may be a prior month)
    @State private var showingDeepLinkedReceipt = false
    @State private var commitments: [Commitment] = []       // Theme D (D3): follow-through surface
    @State private var commitmentUndo: CommitmentUndo?      // brief Undo after a resolve
    @State private var surfacedCommitments = Set<Int>()     // fire commitment_surfaced once per id/run

    /// A just-resolved commitment held for a one-tap Undo (kept/snoozed/released).
    struct CommitmentUndo: Identifiable, Equatable { let id: Int; let label: String }

    // An inferred-date event the user is confirming. "this week" has no real anchor,
    // so confirming opens a date picker (prefilled with the guess) to set the actual
    // day — not silently rubber-stamp the guess.
    struct ConfirmTarget: Identifiable {
        let id: Int          // event id
        let name: String
        let date: Date       // prefill
    }

    // D121: four tiles as one warmth gradient — Upcoming → In sync (warm) →
    // Drifting (cooling) → Reconnect (gone cold). Splitting the old "Keeping up"
    // (warm+cooling) gives each tile one honest job: reassurance vs gentle nudge.
    enum Bucket: String, CaseIterable, Hashable {
        case upcoming = "Upcoming"
        case inSync = "In sync"
        case drifting = "Drifting"
        case reconnect = "Reconnect"

        var job: String {
            switch self {
            case .upcoming: return "Moments coming up — show up on time."
            case .inSync: return "In good rhythm — nothing needed."
            case .drifting: return "Starting to cool — a good moment to reach out."
            case .reconnect: return "Gone quiet — time to reconnect."
            }
        }
        var emptyLine: String {
            switch self {
            case .upcoming: return "Nothing on the horizon"
            case .inSync: return "Nothing here yet"
            case .drifting: return "No one drifting — nice ✦"
            case .reconnect: return "You're all caught up ✦"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pulse").font(.troveSerif(34)).foregroundStyle(Theme.ink)
                        Text("How you're showing up, at a glance.")
                            .font(.troveMono(12)).foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 8)

                    if let receipt {
                        ReceiptCard(receipt: receipt) { Haptics.soft(); showingReceipt = true }
                    }

                    commitmentsSection()

                    switch state {
                    case .idle, .loading:
                        PulseSkeleton()
                    case .failed(let message):
                        MessageBlock(title: "Couldn't load Pulse", detail: message) { Task { await load() } }
                    case .loaded(let items):
                        ForEach(Bucket.allCases, id: \.self) { bucket in
                            let bucketItems = filtered(bucket, items)
                            NavigationLink(value: bucket) {
                                tile(bucket, bucketItems)
                            }
                            .buttonStyle(.plain)
                            .disabled(bucketItems.isEmpty)
                        }
                        horizonSection()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .navigationBarHidden(true)
            .navigationDestination(for: Bucket.self) { bucket in
                bucketList(bucket)
            }
            // Declared at the root so BOTH horizon rows (here) and bucket-detail rows
            // (pushed) resolve to it — one destination for the whole stack.
            .navigationDestination(for: PulseTarget.self) { t in
                EntityDetailView(entityId: t.id, name: t.name)
            }
        }
        .sheet(item: $confirming) { target in
            ConfirmDateSheet(name: target.name, initial: target.date) { picked in
                confirming = nil
                Task { try? await session.confirmEvent(target.id, date: Self.isoDay(picked)) }
            } onCancel: { confirming = nil }
        }
        .sheet(isPresented: $showingReceipt) {
            if let receipt { ReceiptDetailView(receipt: receipt) }
        }
        .sheet(isPresented: $showingDeepLinkedReceipt) {
            if let deepLinkedReceipt { ReceiptDetailView(receipt: deepLinkedReceipt) }
        }
        .task { if case .idle = state { await load() } }
        .onChange(of: session.dataVersion) { Task { await load() } }
        // Theme A slice 6: a tapped "your month is ready" push opens THAT month's receipt
        // (often a prior month, not the card's current one) and attributes the view to the
        // nudge surface. `.task(id:)` covers both a live tap and a cold launch from the push.
        .task(id: receiptDeepLinkPeriod) {
            guard let period = receiptDeepLinkPeriod else { return }
            if let r = try? await session.loadReceipt(month: period) {
                deepLinkedReceipt = r
                ReceiptAnalytics.viewedOnce(r, surface: "nudge")
                showingDeepLinkedReceipt = true
            }
            receiptDeepLinkPeriod = nil   // consume the intent
        }
    }

    // MARK: tile

    private func tile(_ bucket: Bucket, _ items: [PulseItem]) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(bucket.rawValue).font(.troveSerif(20)).foregroundStyle(Theme.ink)
                Text(items.isEmpty ? bucket.emptyLine : (preview(bucket, items) ?? bucket.job))
                    .font(.troveMono(11)).foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
            if !items.isEmpty {
                Text("\(items.count)").font(.troveSerif(26)).foregroundStyle(Theme.ink)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint(bucket), in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))
    }

    private func tint(_ bucket: Bucket) -> Color {
        switch bucket {
        case .upcoming: return Theme.accentSoft.opacity(0.5)
        case .inSync: return Color(hex: 0xcfe9d8).opacity(0.5)   // soft green (healthy)
        case .drifting: return Color(hex: 0xeaddc0).opacity(0.5) // sand (starting to cool)
        case .reconnect: return Color(hex: 0xe6cdb4).opacity(0.5) // warm clay (gone quiet)
        }
    }

    // MARK: On the Horizon (D149)

    // A read-only lane below the tiles: dated events beyond their action window. The
    // server collapses to one row per entity (soonest-first, `+N more` summary). Not a
    // nudge — no push, no deck, no impression.
    @ViewBuilder
    private func horizonSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("On the horizon").font(.troveSerif(20)).foregroundStyle(Theme.ink)
                Spacer()
                Text("what's coming up").font(.troveMono(11)).foregroundStyle(Theme.muted)
            }
            .padding(.top, 10)

            if horizon.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing on the horizon yet.")
                        .font(.troveMono(13, .medium)).foregroundStyle(Theme.ink)
                    Text("Add a trip, a birthday, or plans with someone — it'll show up here.")
                        .font(.troveMono(12)).foregroundStyle(Theme.muted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
            } else {
                ForEach(horizon) { horizonRow($0) }
            }
        }
    }

    private func horizonRow(_ item: HorizonItem) -> some View {
        let tentative = item.unconfirmed == true && !item.isSummary   // Confirm only on a single tentative item
        let tint = NudgeStyle.color(kind: nil, eventType: item.eventType)
        return HStack(spacing: 12) {
            NavigationLink(value: PulseTarget(id: item.entityId, name: item.name)) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(NudgeStyle.label(kind: nil, eventType: item.eventType))
                            .font(.troveMono(10, .medium)).foregroundStyle(tint)
                            .padding(.vertical, 3).padding(.horizontal, 9)
                            .background(tint.opacity(0.14), in: Capsule())
                        Spacer()
                        Text((NudgeStyle.timing(daysUntil: item.daysUntil, daysSince: nil) ?? "") + (tentative ? " · ~" : ""))
                            .font(.troveMono(11)).foregroundStyle(Theme.muted)
                    }
                    HStack(spacing: 8) {
                        Text(item.name).font(.troveSerif(18)).foregroundStyle(Theme.ink)
                        if let m = item.moreCount, m > 0 {
                            Text("+\(m) more")
                                .font(.troveMono(10, .medium)).foregroundStyle(Theme.muted)
                                .padding(.vertical, 2).padding(.horizontal, 8)
                                .background(Theme.bg, in: Capsule())
                                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                        }
                    }
                    if let note = item.insightText, !note.isEmpty {
                        Text("“\(note)”").font(.troveMono(11)).foregroundStyle(Theme.muted)
                            .italic().lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if tentative, let eid = item.eventId {
                compactButton("Confirm date") {
                    Haptics.soft()
                    confirming = ConfirmTarget(id: eid, name: item.name, date: prefillDate(item.eventDate))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
    }

    // MARK: bucket detail

    private func bucketList(_ bucket: Bucket) -> some View {
        let rows: [PulseItem] = {
            if case .loaded(let items) = state { return self.filtered(bucket, items) }
            return []
        }()
        return ScrollView {
            LazyVStack(spacing: 10) {
                if rows.isEmpty {
                    MessageBlock(title: bucket.emptyLine, detail: bucket.job)
                } else {
                    ForEach(rows) { item in rowCard(item) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Theme.bg)
        .navigationTitle(bucket.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        // PulseTarget destination + the Confirm-date sheet are declared once at the root
        // (see `body`) so they serve both the horizon lane and this pushed detail list.
    }

    /// Parse a "YYYY-MM-DD" anchor to prefill the picker; fall back to today when the
    /// date is missing or unparseable (the whole reason we're asking).
    private func prefillDate(_ iso: String?) -> Date {
        guard let iso, let d = Self.dayParser.date(from: String(iso.prefix(10))) else { return Date() }
        return d
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func isoDay(_ date: Date) -> String { dayParser.string(from: date) }

    private struct PulseTarget: Hashable { let id: Int; let name: String }

    private func rowCard(_ item: PulseItem) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: PulseTarget(id: item.id, name: item.name)) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.troveSerif(18)).foregroundStyle(Theme.ink)
                    Text(subline(item)).font(.troveMono(11)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            actionButton(item)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func actionButton(_ item: PulseItem) -> some View {
        if item.status == "upcoming", let up = item.upcoming, let eid = up.eventId {
            if up.unconfirmed == true {
                compactButton("Confirm date") {
                    Haptics.soft()
                    confirming = ConfirmTarget(id: eid, name: item.name, date: prefillDate(up.eventDate))
                }
            } else {
                compactButton("Showed up") { Haptics.success(); try? await session.actEvent(eid) }
            }
        } else {
            compactButton("Showed up") { Haptics.success(); try? await session.logContact(entityId: item.id) }
        }
    }

    private func compactButton(_ title: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title)
                .font(.troveMono(11, .medium))
                .foregroundStyle(Theme.ink)
                .padding(.vertical, 7).padding(.horizontal, 12)
                .background(Theme.bg, in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: derive

    // Tiles just filter by status; the server (D120) already orders within each
    // group (upcoming soonest-first, warmth tiles quietest-first), so web + iOS stay
    // consistent. Filtering preserves the server's order.
    private func filtered(_ bucket: Bucket, _ items: [PulseItem]) -> [PulseItem] {
        switch bucket {
        case .upcoming:  return items.filter { $0.status == "upcoming" }
        case .inSync:    return items.filter { $0.status == "warm" }
        case .drifting:  return items.filter { $0.status == "cooling" }
        case .reconnect: return items.filter { $0.status == "reach_out" }
        }
    }

    private func preview(_ bucket: Bucket, _ items: [PulseItem]) -> String? {
        guard let top = items.first else { return nil }
        return "\(top.name) — \(subline(top))"
    }

    private func subline(_ item: PulseItem) -> String {
        switch item.status {
        case "upcoming":
            if let up = item.upcoming {
                let label = NudgeStyle.label(kind: nil, eventType: up.eventType)
                let timing = NudgeStyle.timing(daysUntil: up.daysUntil, daysSince: nil) ?? ""
                let confirm = (up.unconfirmed == true) ? " · confirm date" : ""
                return "\(label) \(timing)\(confirm)"
            }
            return "Coming up"
        case "reach_out": return "Quiet \(item.daysSince ?? 0) days"
        case "cooling": return "Quiet \(item.daysSince ?? 0) days"
        default: return "In touch"
        }
    }

    // MARK: Commitments (Theme D, D3) — the follow-through surface, folded into Pulse
    // (no dedicated screen, §1.4). Shows only the DUE commitments the server selector
    // returned; kept/snooze/release with a one-tap Undo. A "kept" is the value moment.

    @ViewBuilder
    private func commitmentsSection() -> some View {
        let due = Array(commitments.filter { $0.due }.prefix(4))
        if !due.isEmpty || commitmentUndo != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your word").font(.troveSerif(20)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("things you meant to do").font(.troveMono(11)).foregroundStyle(Theme.muted)
                }
                .padding(.top, 10)

                ForEach(due) { commitmentCard($0) }
                if let u = commitmentUndo { undoBar(u) }
            }
        }
    }

    private func commitmentCard(_ c: Commitment) -> some View {
        let accent = c.isQuestion ? Color(hex: 0x6b8fc4) : Theme.gold
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(c.isQuestion ? "TO ASK" : "YOU SAID YOU'D")
                    .font(.troveMono(10, .medium)).foregroundStyle(accent)
                    .padding(.vertical, 3).padding(.horizontal, 9)
                    .background(accent.opacity(0.14), in: Capsule())
                if c.reason == "overdue" {
                    Text("still owed").font(.troveMono(10, .medium)).foregroundStyle(Theme.muted)
                        .padding(.vertical, 3).padding(.horizontal, 9)
                        .background(Theme.bg, in: Capsule())
                        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                }
                Spacer()
                Menu {
                    Button { snoozeCommitmentCard(c) } label: { Label("Snooze 3 days", systemImage: "clock") }
                    Button(role: .destructive) { releaseCommitmentCard(c) } label: { Label("No longer relevant", systemImage: "xmark") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.muted).frame(width: 28, height: 28)
                }
            }
            Text(c.text).font(.troveSerif(18)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let person = c.personName {
                if let e = c.entity {
                    NavigationLink(value: PulseTarget(id: e.id, name: e.name)) { personLine(person) }
                        .buttonStyle(.plain)
                } else {
                    personLine(person)
                }
            }
            Button { keepCommitmentCard(c) } label: {
                Text("Kept ✓").font(.troveMono(12, .medium)).foregroundStyle(Theme.ink)
                    .padding(.vertical, 7).padding(.horizontal, 14)
                    .background(accent.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))
        .onAppear {
            guard !surfacedCommitments.contains(c.id) else { return }
            surfacedCommitments.insert(c.id)
            Analytics.capture("commitment_surfaced", ["kind": c.kind, "surface": "pulse", "reason": c.reason ?? "none"])
        }
    }

    private func personLine(_ name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill").font(.system(size: 10)).foregroundStyle(Theme.muted)
            Text(name).font(.troveMono(12)).foregroundStyle(Theme.muted)
        }
    }

    private func undoBar(_ u: CommitmentUndo) -> some View {
        HStack {
            Text(u.label).font(.troveMono(12)).foregroundStyle(Theme.muted)
            Spacer()
            Button("Undo") { undoCommitment(u) }
                .font(.troveMono(12, .medium)).foregroundStyle(Theme.ink)
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(Theme.surface.opacity(0.6), in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }

    // Actions — optimistic (drop locally + show Undo), then persist (the server call
    // bumps dataVersion → load() reconciles). Undo reopens the commitment.
    private func keepCommitmentCard(_ c: Commitment) {
        Haptics.success(); dropCommitment(c.id)
        commitmentUndo = CommitmentUndo(id: c.id, label: "Kept ✓")
        Task { try? await session.markCommitmentDone(c.id, kind: c.kind, reason: c.reason) }
        scheduleUndoDismiss(c.id)
    }
    private func snoozeCommitmentCard(_ c: Commitment) {
        Haptics.soft(); dropCommitment(c.id)
        commitmentUndo = CommitmentUndo(id: c.id, label: "Snoozed 3 days")
        Task { await session.snoozeCommitment(c.id, days: 3, kind: c.kind) }
        scheduleUndoDismiss(c.id)
    }
    private func releaseCommitmentCard(_ c: Commitment) {
        Haptics.soft(); dropCommitment(c.id)
        commitmentUndo = CommitmentUndo(id: c.id, label: "Cleared")
        Task { try? await session.releaseCommitment(c.id, kind: c.kind) }
        scheduleUndoDismiss(c.id)
    }
    private func undoCommitment(_ u: CommitmentUndo) {
        commitmentUndo = nil
        Task { await session.reopenCommitment(u.id) }
    }
    private func dropCommitment(_ id: Int) { commitments.removeAll { $0.id == id } }
    private func scheduleUndoDismiss(_ id: Int) {
        Task {
            try? await Task.sleep(for: .seconds(5))
            if commitmentUndo?.id == id { commitmentUndo = nil }
        }
    }

    private func load() async {
        state = .loading
        do {
            let resp = try await session.loadPulse()
            horizon = resp.horizon ?? []
            state = .loaded(resp.items)
            // Non-fatal: a receipt failure must never block Pulse (leave the card hidden).
            receipt = try? await session.loadReceipt()
            // Theme D (D3): follow-through commitments — also non-fatal.
            commitments = (try? await session.loadCommitments()) ?? []
        }
        catch { state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription) }
    }
}

/// Pick the real day for an inferred-date event ("this week" → an actual date).
/// Confirming sets it as an exact, nudge-eligible date; the date is otherwise just a
/// guess the model made.
private struct ConfirmDateSheet: View {
    let name: String
    let initial: Date
    let onConfirm: (Date) -> Void
    let onCancel: () -> Void

    @State private var date: Date

    init(name: String, initial: Date, onConfirm: @escaping (Date) -> Void, onCancel: @escaping () -> Void) {
        self.name = name; self.initial = initial; self.onConfirm = onConfirm; self.onCancel = onCancel
        _date = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("When is \(name)'s plan?")
                    .font(.troveSerif(20)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("We couldn't pin an exact date — set the day so it nudges you at the right time.")
                    .font(.troveMono(12)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                DatePicker("Date", selection: $date, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Theme.gold)
                Button { onConfirm(date) } label: {
                    Text("Set date").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(filled: true))
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Theme.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }.foregroundStyle(Theme.muted)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
