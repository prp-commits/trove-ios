import SwiftUI

/// Ask Trove — grounded Q&A over the library (POST /api/ask). Shows the answer
/// plus the cited notes; citations tap through to the entity.
struct AskView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var question = ""
    @State private var phase: Phase = .idle
    @FocusState private var focused: Bool

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
                        Text("Ask anything about the people and topics you've saved — “When did I last see Addie?”, “Who's into watches?”")
                            .font(.troveMono(12)).foregroundStyle(Theme.muted)
                            .padding(.top, 4)
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
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: EntityLink.self) { link in
                EntityDetailView(entityId: link.id, name: link.name)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Theme.ink)
                }
            }
        }
        .onAppear { focused = true }
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
