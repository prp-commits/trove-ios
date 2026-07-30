import SwiftUI

/// Ask Trove — grounded Q&A over the library (POST /api/ask). Shows the answer
/// plus the cited notes; citations tap through to the entity.
struct AskView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var question = ""
    @State private var phase: Phase = .idle
    @FocusState private var focused: Bool
    // (D224) Tappable starter questions, seeded from the user's OWN entities so every one is
    // grounded and answerable — the HAX caution: never suggest what Ask can't answer from their
    // notes. An empty box is the classic undiscoverable-NL-feature failure; a real name in a real
    // question is the fix.
    @State private var suggestions: [String] = []

    enum Phase {
        case idle, working, answered(AskResponse), error(String)
    }

    struct EntityLink: Hashable { let id: Int; let name: String }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    askField

                    switch phase {
                    case .idle:
                        idle
                    case .working:
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.ink)
                            Text("Reading your notes…").font(.troveMono(12)).foregroundStyle(Theme.muted)
                        }
                        .padding(.top, 8)
                    case .answered(let res):
                        answer(res)
                    case .error(let message):
                        MessageBlock(title: "Couldn't answer that", detail: message) {
                            Task { await ask() }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.bg)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: EntityLink.self) { link in
                EntityDetailView(entityId: link.id, name: link.name)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Theme.ink)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
        // (D224) NO auto-focus. Raising the keyboard on open shoved the example questions off
        // screen at the exact moment they teach the feature. Let the suggestions sit visible;
        // the user focuses the field by tapping it or a chip.
        .task {
            Analytics.capture("ask_opened")
            await loadSuggestions()
        }
    }

    // MARK: idle — the teaching surface (D224)

    @ViewBuilder private var idle: some View {
        if suggestions.isEmpty {
            Text("Ask anything about the people and topics you've saved — grounded in your own notes, and always cited back to them.")
                .font(.troveMono(12)).foregroundStyle(Theme.muted)
                .padding(.top, 4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("TRY ASKING")
                    .font(.troveMono(10, .medium)).tracking(0.5).foregroundStyle(Theme.muted)
                ForEach(suggestions, id: \.self) { s in
                    Button { Task { await askSuggestion(s) } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Theme.gold)
                            Text(s).font(.troveMono(13)).foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 11).padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }

    /// Build up to four starters from the user's real entities, most-noted first. Every one is a
    /// question about something that EXISTS in their library, so Ask can always ground an answer —
    /// no generic "who has a birthday coming up?" that might return "I don't see that."
    private func loadSuggestions() async {
        guard let entities = try? await session.loadEntities() else { return }
        let active = entities.filter { !$0.isArchived }
        let people = active.filter { $0.isPerson }.sorted { ($0.insightCount ?? 0) > ($1.insightCount ?? 0) }
        let topics = active.filter { !$0.isPerson }.sorted { ($0.insightCount ?? 0) > ($1.insightCount ?? 0) }
        var out: [String] = []
        if let p = people.first {
            out.append("What do I know about \(p.name)?")
            out.append("When did I last see \(p.name)?")
        }
        if people.count > 1 { out.append("What do I know about \(people[1].name)?") }
        if let t = topics.first { out.append("What have I saved about \(t.name)?") }
        suggestions = Array(out.prefix(4))
    }

    private func askSuggestion(_ text: String) async {
        Analytics.capture("ask_suggestion_tapped")
        question = text
        await ask()
    }

    private var askField: some View {
        HStack(spacing: 8) {
            TextField("Ask a question", text: $question, axis: .vertical)
                .font(.troveMono(15))
                .focused($focused)
                .lineLimit(1...4)
                .submitLabel(.search)
                .onSubmit { Task { await ask() } }
            Button { Task { await ask() } } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(canAsk ? Theme.accent : Theme.line)
            }
            .disabled(!canAsk)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusField))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusField).stroke(Theme.line, lineWidth: 1))
    }

    private func answer(_ res: AskResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(res.answer)
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !res.citations.isEmpty {
                Text("FROM YOUR NOTES")
                    .font(.troveMono(10, .medium)).tracking(0.5)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)

                ForEach(res.citations) { c in
                    citationCard(c)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func citationCard(_ c: AskCitation) -> some View {
        let card = VStack(alignment: .leading, spacing: 6) {
            Text(c.text ?? "—")
                .font(.troveMono(13)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if c.isPhoto {
                    Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                if let name = c.entityName {
                    Text(name).font(.troveMono(11)).foregroundStyle(Theme.ink2)
                }
                if let place = c.geoPlace {
                    Text("· \(place)").font(.troveMono(10)).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))

        if let id = c.entityId, let name = c.entityName {
            NavigationLink(value: EntityLink(id: id, name: name)) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    private var canAsk: Bool {
        !session.isWorking && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        focused = false
        phase = .working
        do { phase = .answered(try await session.ask(q)) }
        catch { phase = .error((error as? APIError)?.errorDescription ?? error.localizedDescription) }
    }
}
