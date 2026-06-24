import SwiftUI
import MessageUI

struct ReviewView: View {
    @Environment(Session.self) private var session
    @State private var state: Loadable<[Item]> = .idle
    @State private var drag: CGSize = .zero
    @State private var sheet: ActiveSheet?
    @State private var showNoMessaging = false

    // The contact each person card will message, resolved once per entity so the
    // card can show *who* before you tap (a wrong guess is caught up front) and
    // offer "Change contact". Keyed by entity id.
    @State private var resolvedLinks: [Int: ContactLink] = [:]

    // Messaging surfaces: compose pre-addressed, or pick the contact one time first.
    // Driven by a single sheet so the picker → composer handoff doesn't collide.
    private enum ActiveSheet: Identifiable {
        case compose(Item, [String])
        case pick(Item)
        var id: String {
            switch self {
            case .compose(let i, _): return "compose-\(i.id)"
            case .pick(let i): return "pick-\(i.id)"
            }
        }
    }

    // Undo for the easy-to-misfire swipe (keep/skip is a local learning signal,
    // so restoring the card is fully honest — no server effect to reverse).
    @State private var undo: Undoable?
    @State private var undoTask: Task<Void, Never>?

    struct Item: Identifiable { let id = UUID(); let card: DeckCard }
    // A reversible action on a card: `revert` undoes the server-side effect; the card
    // is re-inserted on top. Serves both the keep/skip swipe and "Showed up".
    struct Undoable { let item: Item; let revert: () -> Void }

    // How far a card must travel to commit, and the off-screen exit distance.
    private let commitThreshold: CGFloat = 120
    private let flyOff: CGFloat = 700

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 4) {
                Text("Review").font(.troveSerif(34)).foregroundStyle(Theme.ink)
                Text("The people and topics worth your attention right now.")
                    .font(.troveMono(12)).foregroundStyle(Theme.muted)

                switch state {
                case .idle, .loading:
                    ReviewSkeleton()
                case .failed(let message):
                    centered { MessageBlock(title: "Couldn't load your deck", detail: message) { Task { await load() } } }
                case .loaded(let items):
                    if items.isEmpty {
                        centered {
                            VStack(spacing: 8) {
                                Text("You're all caught up ✦").font(.troveSerif(22)).foregroundStyle(Theme.ink)
                                Text("New nudges arrive as dates approach and friends go quiet.")
                                    .font(.troveMono(12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                            }
                        }
                    } else {
                        deck(items)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // Undo floats at the app level so it survives the deck emptying after
            // the last card is swiped (otherwise it vanishes with the deck view).
            VStack { Spacer(); undoPill.padding(.bottom, 18) }
        }
        .task { if case .idle = state { await load() } }
    }

    private func centered<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack { Spacer(minLength: 40); content(); Spacer() }
            .frame(maxWidth: .infinity)
    }

    // MARK: deck

    private func deck(_ items: [Item]) -> some View {
        VStack(spacing: 18) {
            ZStack {
                // Next card peeking behind the top one.
                ForEach(Array(items.prefix(2).enumerated()).reversed(), id: \.element.id) { idx, item in
                    cardView(item)
                        .overlay {
                            if idx == 0 {
                                RoundedRectangle(cornerRadius: Theme.radiusCard)
                                    .stroke(swipeTint, lineWidth: 2)
                                    .opacity(swipeProgress)
                            }
                        }
                        .overlay(alignment: drag.width > 0 ? .topLeading : .topTrailing) {
                            if idx == 0 { swipeStamp }
                        }
                        .scaleEffect(idx == 0 ? 1 : 0.96)
                        .offset(y: idx == 0 ? drag.height * 0.3 : 10)
                        .offset(x: idx == 0 ? drag.width : 0)
                        .rotationEffect(.degrees(idx == 0 ? Double(drag.width / 22) : 0))
                        .opacity(idx == 0 ? 1 : 0.6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: drag)
                        .gesture(swipeGesture(item))
                        .allowsHitTesting(idx == 0)
                }
            }
            .frame(maxHeight: .infinity)

            // Swipe handles keep/skip (warmth); these are the prominent actions.
            HStack(spacing: 14) {
                Menu {
                    Button("Tomorrow") { snooze(items[0], 1) }
                    Button("In 3 days") { snooze(items[0], 3) }
                    Button("Next week") { snooze(items[0], 7) }
                } label: {
                    actionLabel("Snooze", system: "clock")
                        .font(.troveMono(15, .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14).padding(.horizontal, 22)
                        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                }
                Button { showedUp(items[0]) } label: { actionLabel("Showed up", system: "checkmark.circle") }
                    .buttonStyle(PillButtonStyle(filled: true))
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .sheet(item: $sheet) { active in
            switch active {
            case .compose(let item, let recipients):
                MessageComposer(body: draftMessage(item), recipients: recipients) { result in
                    handleMessageResult(item, result)
                }
                .ignoresSafeArea()
            case .pick(let item):
                if let person = messagePerson(of: item) {
                    ContactPickerView(
                        onPick: { link in
                            ContactLinkStore.save(link, for: person.id)
                            resolvedLinks[person.id] = link
                            sheet = nil
                            presentCompose(item, [link.phone])
                        },
                        onCancel: { sheet = nil }
                    )
                    .ignoresSafeArea()
                }
            }
        }
        .alert("Messaging unavailable", isPresented: $showNoMessaging) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device can't send texts (the Simulator can't). Try on a real device, or use Showed up.")
        }
    }

    private func actionLabel(_ text: String, system: String) -> some View {
        HStack(spacing: 6) { Image(systemName: system); Text(text) }
    }

    // MARK: swipe cue

    /// 0→1 as the top card nears the commit threshold; drives the cue's strength.
    private var swipeProgress: Double { min(abs(drag.width) / commitThreshold, 1) }

    /// Warm gold = keep (right), calm muted = skip (left). No alarmist red/green.
    private var swipeTint: Color { drag.width >= 0 ? Theme.gold : Theme.muted }

    @ViewBuilder private var swipeStamp: some View {
        if abs(drag.width) > 6 {
            let keep = drag.width > 0
            Text(keep ? "KEEP" : "SKIP")
                .font(.troveMono(13, .bold)).tracking(1.5)
                .foregroundStyle(keep ? Theme.gold : Theme.muted)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(keep ? Theme.gold : Theme.muted, lineWidth: 2))
                .rotationEffect(.degrees(keep ? -10 : 10))
                .opacity(swipeProgress)
                .padding(28)
        }
    }

    @ViewBuilder private var undoPill: some View {
        if let undo {
            Button { performUndo(undo) } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.troveMono(12, .medium))
                    .foregroundStyle(Theme.bg)
                    .padding(.vertical, 8).padding(.horizontal, 16)
                    .background(Theme.ink, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func swipeGesture(_ item: Item) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if abs(value.translation.width) > commitThreshold {
                    resolve(item, value.translation.width > 0 ? "right" : "left")
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = .zero }
                }
            }
    }

    // MARK: card content

    @ViewBuilder
    private func cardView(_ item: Item) -> some View {
        switch item.card {
        case .nudge(let n): nudgeCard(n, item: item)
        case .other(let o): otherCard(o, item: item)
        }
    }

    private func nudgeCard(_ n: NudgeCard, item: Item) -> some View {
        let label = NudgeStyle.label(kind: n.pill.kind, eventType: n.pill.eventType)
        let color = NudgeStyle.color(kind: n.pill.kind, eventType: n.pill.eventType)
        let timing = NudgeStyle.timing(daysUntil: n.pill.daysUntil, daysSince: n.pill.daysSince)
        let link = n.entity.isPerson ? resolvedLinks[n.entity.id] : nil
        return cardShell {
            HStack(spacing: 8) {
                Text(label.uppercased())
                    .font(.troveMono(10, .medium)).tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.vertical, 4).padding(.horizontal, 9)
                    .background(color, in: Capsule())
                if let timing {
                    Text(timing).font(.troveMono(11)).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            // Tap the suggestion → message the person (auto-tracks on send).
            Button { if n.entity.isPerson { startMessage(item) } } label: {
                Text(n.pill.text)
                    .font(.troveSerif(22))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!n.entity.isPerson)

            // One compact line: the contact we'll message + a quiet "Change" to
            // re-link. (The system composer can't report who you actually texted, so
            // a wrong auto-match is corrected here, not inside Messages.)
            if n.entity.isPerson {
                HStack(spacing: 6) {
                    Button { startMessage(item) } label: {
                        Label(link?.name ?? "Tap to message", systemImage: "message")
                            .font(.troveMono(11, .medium)).foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                    if link != nil {
                        Text("·").font(.troveMono(11)).foregroundStyle(Theme.muted)
                        Button { relink(item) } label: {
                            Text("Change").font(.troveMono(11)).foregroundStyle(Theme.muted).underline()
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 6) {
                TypeChip(isPerson: n.entity.isPerson)
                Text(n.entity.name).font(.troveMono(11)).foregroundStyle(Theme.ink2)
            }
            if !n.insights.isEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
                // Backend returns these relevance-ordered (most relevant to the
                // suggestion first), so the "why" leads. (D108)
                ForEach(n.insights.prefix(3)) { ins in
                    Text("• \(ins.text)")
                        .font(.troveMono(12)).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .task(id: n.entity.id) { await resolveLink(n) }
    }

    private func otherCard(_ o: OtherCard, item: Item) -> some View {
        let isConnection = o.type == "connection"
        let person = o.connectionPerson
        let cites = o.connectionCites
        return cardShell {
            Text(o.type.capitalized.uppercased())
                .font(.troveMono(10, .medium)).tracking(0.5).foregroundStyle(Theme.muted)
            // Headline. For a connection with a person side, tapping it texts them
            // (reuses the contact lookup/storage from the person nudges).
            Button { if isConnection, person != nil { startMessage(item) } } label: {
                Text(o.recap ?? o.prompt ?? o.relationship ?? "A thread in your notes")
                    .font(.troveSerif(21)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!(isConnection && person != nil))

            // A connection shows BOTH sides; other cards show their one entity.
            if isConnection, let a = o.entityA, let b = o.entityB {
                HStack(spacing: 8) {
                    entityChip(a)
                    Text("×").font(.troveMono(11)).foregroundStyle(Theme.muted)
                    entityChip(b)
                }
            } else if let entity = o.entity {
                entityChip(entity)
            }

            // The cited insights from BOTH entities (connection) or the card's insights —
            // same "evidence below the nudge" treatment as every other Review card.
            if isConnection, !cites.isEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
                ForEach(cites) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("• \(c.text)").font(.troveMono(12)).foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let name = c.entityName {
                            Text(name).font(.troveMono(10)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            } else if let insights = o.insights, !insights.isEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
                ForEach(insights.prefix(3)) { ins in
                    Text("• \(ins.text)").font(.troveMono(12)).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if isConnection, let p = person {
                Text("Tap to text \(p.name)").font(.troveMono(11)).foregroundStyle(Theme.gold)
            }
            Spacer(minLength: 0)
        }
    }

    private func entityChip(_ e: EntityRef) -> some View {
        HStack(spacing: 6) {
            TypeChip(isPerson: e.isPerson)
            Text(e.name).font(.troveMono(11)).foregroundStyle(Theme.ink2)
        }
    }

    private func cardShell<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))
    }

    // MARK: actions

    private func resolve(_ item: Item, _ direction: String) {
        Haptics.commit()
        sendSwipe(item, direction)
        // Fly the top card off-screen in the swipe direction, then pop it.
        drag = CGSize(width: direction == "right" ? flyOff : -flyOff, height: drag.height)
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                popTop()
                let reverse = direction == "right" ? "left" : "right"
                offerUndo(item, revert: { sendSwipe(item, reverse) })
            }
        }
    }

    /// Fire-and-forget the keep/skip learning signal where the card has an entity.
    private func sendSwipe(_ item: Item, _ direction: String) {
        Task {
            switch item.card {
            case .nudge(let n):
                await session.swipe(entityId: n.entity.id, direction: direction,
                                    nudgeKind: n.pill.kind, eventType: n.pill.eventType)
            case .other(let o):
                if let entity = o.entity {
                    await session.swipe(entityId: entity.id, direction: direction,
                                        nudgeKind: o.type, eventType: nil)
                }
            }
        }
    }

    /// Remove the flown card and reset the drag without animation (the card is
    /// already off-screen, so the next card should simply be there).
    private func popTop() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            if case .loaded(var items) = state, !items.isEmpty {
                items.removeFirst()
                state = .loaded(items)
            }
            drag = .zero
        }
    }

    /// Show a transient Undo for a few seconds after a reversible action.
    private func offerUndo(_ item: Item, revert: @escaping () -> Void) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            undo = Undoable(item: item, revert: revert)
        }
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                await MainActor.run { withAnimation { undo = nil } }
            }
        }
    }

    /// Reverse the action server-side and put the card back on top.
    private func performUndo(_ u: Undoable) {
        Haptics.soft()
        undoTask?.cancel()
        u.revert()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if case .loaded(var items) = state {
                items.insert(u.item, at: 0)
                state = .loaded(items)
            }
            undo = nil
        }
    }

    // MARK: messaging

    /// Tap-to-message (Phase C, slice 5). Resolve a number for this person — a
    /// previously learned link or a confident contact auto-match — and pre-address
    /// the composer. If we can't, show the one-time contact picker first; the pick is
    /// stored on-device so the next message to them is pre-addressed. Phone numbers
    /// and the entity↔contact link never leave the device.
    /// The person to message for a card — a person nudge's entity, or the person
    /// side of a connection card (D143). Other cards have no message target.
    private func messagePerson(of item: Item) -> EntityRef? {
        switch item.card {
        case .nudge(let n): return n.entity.isPerson ? n.entity : nil
        case .other(let o): return o.connectionPerson
        }
    }

    private func startMessage(_ item: Item) {
        guard let person = messagePerson(of: item) else { return }
        guard MFMessageComposeViewController.canSendText() else { showNoMessaging = true; return }
        if let link = resolvedLinks[person.id]
            ?? ContactLinkStore.resolve(entityId: person.id, name: person.name) {
            resolvedLinks[person.id] = link
            sheet = .compose(item, [link.phone])
        } else {
            sheet = .pick(item)
        }
    }

    /// Resolve (once) the contact a person card will message, so the card can name
    /// it before the user taps. Best-effort; a no-match leaves it unresolved (tap →
    /// picker).
    private func resolveLink(_ n: NudgeCard) async {
        guard n.entity.isPerson, resolvedLinks[n.entity.id] == nil else { return }
        if let link = ContactLinkStore.resolve(entityId: n.entity.id, name: n.entity.name) {
            resolvedLinks[n.entity.id] = link
        }
    }

    /// User says the linked contact is wrong — let them re-pick. The new pick
    /// replaces the stored link (and the on-card name) and opens the composer.
    private func relink(_ item: Item) { sheet = .pick(item) }

    /// Present the composer after the picker has dismissed. The brief delay lets the
    /// picker sheet finish dismissing so the composer presents cleanly.
    private func presentCompose(_ item: Item, _ recipients: [String]) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            sheet = .compose(item, recipients)
        }
    }

    /// Starting draft for the text. The pill is phrased as a directive to the
    /// user, so we open an empty composer for now; an AI-drafted message is a
    /// natural follow-up (needs a small backend endpoint).
    private func draftMessage(_ item: Item) -> String { "" }

    /// On a successful send, count it as "Showed up" (same cross-tab effect) and
    /// advance. Cancel/fail just closes the composer.
    private func handleMessageResult(_ item: Item, _ result: MessageComposeResult) {
        sheet = nil
        guard result == .sent else { return }
        showedUp(item)
    }

    /// "Showed up" — the explicit done action, shared with the message-sent path and
    /// standardized across Pulse + Review. Records the action, pops the card, and
    /// offers a transient Undo (the action clears the nudge from BOTH tabs, so a
    /// mis-tap must be reversible).
    private func showedUp(_ item: Item) {
        Haptics.success()
        let revert = doShowUp(item)
        undoTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if case .loaded(var items) = state, !items.isEmpty {
                items.removeFirst()
                state = .loaded(items)
            }
            drag = .zero
        }
        offerUndo(item, revert: revert)
    }

    /// Record showing up: for an event card, mark the event acted (clears it from
    /// Pulse AND the deck via `acted_at`); otherwise log a catch-up (resets the decay
    /// clock). Returns the matching reversal for the Undo pill.
    private func doShowUp(_ item: Item) -> () -> Void {
        guard case .nudge(let n) = item.card else { return {} }
        // The explicit "Showed up" act (button or message-sent) — the headline moat
        // signal. Distinct from a KEEP swipe (action:"kept").
        Analytics.capture("nudge_acted", ["nudge_kind": n.pill.kind ?? "none",
                                          "event_type": n.pill.eventType ?? "none",
                                          "action": "showed_up"])
        Analytics.noteValueMoment()
        if let eid = n.pill.eventId {
            Task { try? await session.actEvent(eid) }
            return { Task { try? await session.unactEvent(eid) } }
        } else {
            Task { try? await session.logContact(entityId: n.entity.id) }
            return { Task { try? await session.undoContact(entityId: n.entity.id) } }
        }
    }

    private func snooze(_ item: Item, _ days: Int) {
        Haptics.soft()
        if case .nudge(let n) = item.card {
            Task { await session.snooze(entityId: n.entity.id, days: days,
                                        nudgeKind: n.pill.kind, eventType: n.pill.eventType) }
        }
        advance()
    }

    /// Pop the top card (button-driven actions: caught-up / snooze / message).
    private func advance() {
        undoTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if case .loaded(var items) = state, !items.isEmpty {
                items.removeFirst()
                state = .loaded(items)
            }
            drag = .zero
            undo = nil
        }
    }

    private func load() async {
        state = .loading
        do {
            let cards = try await session.loadDeck()
            state = .loaded(cards.map { Item(card: $0) })
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
