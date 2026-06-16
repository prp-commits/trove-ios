import SwiftUI

struct LibraryView: View {
    @Environment(Session.self) private var session
    @State private var state: Loadable<[Entity]> = .idle
    @State private var query = ""
    @State private var showCapture = false
    @State private var showAsk = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    header

                    switch state {
                    case .idle, .loading:
                        ProgressView().tint(Theme.ink)
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    case .failed(let message):
                        MessageBlock(title: "Couldn't load your library", detail: message) {
                            Task { await load() }
                        }
                    case .loaded(let entities):
                        let shown = filter(entities)
                        if entities.isEmpty {
                            MessageBlock(title: "Start your Trove",
                                         detail: "Add the people and topics you want to keep close.")
                        } else if shown.isEmpty {
                            MessageBlock(title: "No matches", detail: "Nothing matches “\(query)”.")
                        } else {
                            ForEach(shown) { entity in
                                NavigationLink(value: entity) { EntityRow(entity: entity) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .navigationBarHidden(true)
            .navigationDestination(for: Entity.self) { entity in
                EntityDetailView(entityId: entity.id, name: entity.name)
            }
        }
        .task { if case .idle = state { await load() } }
        .refreshable { await load() }
        .onChange(of: session.dataVersion) { Task { await load() } }
        .sheet(isPresented: $showCapture) {
            CaptureView(onIngested: { Task { await load() } })
        }
        .sheet(isPresented: $showAsk) {
            AskView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Library")
                    .font(.troveSerif(34))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button { showAsk = true } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 40)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                }
                Button { showCapture = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.accent, in: Circle())
                }
            }
            .padding(.top, 8)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).font(.system(size: 14))
                TextField("Search names", text: $query)
                    .font(.troveMono(14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusField))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusField).stroke(Theme.line, lineWidth: 1))
        }
        .padding(.bottom, 4)
    }

    private func filter(_ entities: [Entity]) -> [Entity] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entities }
        return entities.filter { $0.name.lowercased().contains(q) }
    }

    private func load() async {
        if case .loaded = state {} else { state = .loading }
        do { state = .loaded(try await session.loadEntities()) }
        catch { state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription) }
    }
}

private struct EntityRow: View {
    let entity: Entity

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                TypeChip(isPerson: entity.isPerson)
                Text(entity.name)
                    .font(.troveSerif(19))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(entity.insightCountText)
                    .font(.troveMono(11))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))
    }
}

struct TypeChip: View {
    let isPerson: Bool
    var body: some View {
        Text(isPerson ? "PERSON" : "TOPIC")
            .font(.troveMono(9, .medium))
            .tracking(0.5)
            .foregroundStyle(Theme.ink2)
            .padding(.vertical, 3).padding(.horizontal, 8)
            .background(isPerson ? Theme.accentSoft : Theme.line, in: Capsule())
    }
}

/// Reusable empty / error block with an optional retry.
struct MessageBlock: View {
    let title: String
    let detail: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.troveSerif(20)).foregroundStyle(Theme.ink)
            Text(detail).font(.troveMono(12)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(PillButtonStyle(filled: false))
                    .padding(.top, 4)
                    .frame(maxWidth: 220)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 20)
    }
}
