import SwiftUI
import MessageUI

struct ReviewView: View {
    @Environment(Session.self) private var session
    @State private var state: Loadable<[Item]> = .idle
    @State private var drag: CGSize = .zero
    @State private var composing: Item?
    @State private var showNoMessaging = false

    // Undo for the easy-to-misfire swipe (keep/skip is a local learning signal,
    // so restoring the card is fully honest — no server effect to reverse).
    @State private var undo: Undoable?
    @State private var undoTask: Task<Void, Never>?

    struct Item: Identifiable { let id = UUID(); let card: DeckCard }
    struct Undoable { let item: Item; let direction: String }

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
            .overlay(alignment: .bottom) { undoPill }

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
                Button { catchUp(items[0]) } label: { actionLabel("Caught up", system: "checkmark.circle") }
                    .buttonStyle(PillButtonStyle(filled: true))
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .sheet(item: $composing) { item in
            MessageComposer(body: draftMessage(item)) { result in
                handleMessageResult(item, result)
            }
            .ignoresSafeArea()
        }
        .alert("Messaging unavailable", isPresented: $showNoMessaging) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device can't send texts (the Simulator can't). Try on a real device, or use Caught up.")
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
            Button { undoResolve(undo) } label: {
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
        case .other(let o): otherCard(o)
        }
    }

    private func nudgeCard(_ n: NudgeCard, item: Item) -> some View {
        let label = NudgeStyle.label(kind: n.pill.kind, eventType: n.pill.eventType)
        let color = NudgeStyle.color(kind: n.pill.kind, eventType: n.pill.eventType)
        let timing = NudgeStyle.timing(daysUntil: n.pill.daysUntil, daysSince: n.pill.daysSince)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text(n.pill.text)
                        .font(.troveSerif(22))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if n.entity.isPerson {
                        Label("Tap to message", systemImage: "message")
                            .font(.troveMono(11, .medium))
                            .foregroundStyle(color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!n.entity.isPerson)

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
    }

    private func otherCard(_ o: OtherCard) -> some View {
        cardShell {
            Text(o.type.capitalized.uppercased())
                .font(.troveMono(10, .medium)).tracking(0.5).foregroundStyle(Theme.muted)
            Text(o.recap ?? o.prompt ?? o.relationship ?? "A thread in your notes")
                .font(.troveSerif(21)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let entity = o.entity {
                HStack(spacing: 6) {
                    TypeChip(isPerson: entity.isPerson)
                    Text(entity.name).font(.troveMono(11)).foregroundStyle(Theme.ink2)
                }
            }
            if let insights = o.insights, !insights.isEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
                ForEach(insights.prefix(3)) { ins in
                    Text("• \(ins.text)").font(.troveMono(12)).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
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
                offerUndo(item, direction)
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

    /// Show a transient Undo for a few seconds after a swipe.
    private func offerUndo(_ item: Item, _ direction: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            undo = Undoable(item: item, direction: direction)
        }
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                await MainActor.run { withAnimation { undo = nil } }
            }
        }
    }

    /// Put the card back on top and reverse the learning signal.
    private func undoResolve(_ u: Undoable) {
        Haptics.soft()
        undoTask?.cancel()
        sendSwipe(u.item, u.direction == "right" ? "left" : "right")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if case .loaded(var items) = state {
                items.insert(u.item, at: 0)
                state = .loaded(items)
            }
            undo = nil
        }
    }

    // MARK: messaging

    private func startMessage(_ item: Item) {
        if MFMessageComposeViewController.canSendText() {
            composing = item
        } else {
            showNoMessaging = true
        }
    }

    /// Starting draft for the text. The pill is phrased as a directive to the
    /// user, so we open an empty composer for now; an AI-drafted message is a
    /// natural follow-up (needs a small backend endpoint).
    private func draftMessage(_ item: Item) -> String { "" }

    /// On a successful send, auto-track the outreach (logs the catch-up, which
    /// suppresses the nudge) and advance. Cancel/fail just closes the composer.
    private func handleMessageResult(_ item: Item, _ result: MessageComposeResult) {
        composing = nil
        guard result == .sent else { return }
        if case .nudge(let n) = item.card {
            Task { try? await session.logContact(entityId: n.entity.id) }
        }
        advance()
    }

    private func catchUp(_ item: Item) {
        Haptics.success()
        if case .nudge(let n) = item.card {
            Task { try? await session.logContact(entityId: n.entity.id) }
        }
        advance()
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
