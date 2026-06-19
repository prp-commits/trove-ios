import SwiftUI

struct LibraryView: View {
    @Environment(Session.self) private var session
    @State private var state: Loadable<[Entity]> = .idle
    @State private var query = ""
    @State private var showCapture = false
    @State private var showAsk = false
    @State private var scope: Scope = .all
    @FocusState private var searchFocused: Bool

    enum Scope: String, CaseIterable, Identifiable {
        case all = "All", people = "People", topics = "Topics", archived = "Archived"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    header

                    switch state {
                    case .idle, .loading:
                        LibrarySkeleton()
                    case .failed(let message):
                        MessageBlock(title: "Couldn't load your library", detail: message) {
                            Task { await load() }
                        }
                    case .loaded(let entities):
                        let shown = visible(entities)
                        if entities.isEmpty {
                            MessageBlock(title: "Start your Trove",
                                         detail: "Add the people and topics you want to keep close.",
                                         actionTitle: "Add your first note",
                                         action: { showCapture = true })
                        } else if shown.isEmpty {
                            MessageBlock(title: scope == .archived ? "Nothing archived" : "No matches",
                                         detail: query.isEmpty ? "Nothing in this view yet." : "Nothing matches “\(query)”.")
                        } else {
                            ForEach(shown) { entity in
                                NavigationLink(value: entity) { EntityRow(entity: entity) }
                                    .buttonStyle(.plain)
                                    // Drop the keyboard when opening a profile.
                                    .simultaneousGesture(TapGesture().onEnded { searchFocused = false })
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .scrollDismissesKeyboard(.immediately)   // drag the list down → keyboard drops
            .navigationBarHidden(true)
            .navigationDestination(for: Entity.self) { entity in
                EntityDetailView(entityId: entity.id, name: entity.name)
            }
            .toolbar {
                // Always-available way out of the search field.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { searchFocused = false }
                }
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
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { searchFocused = false }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusField))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusField).stroke(Theme.line, lineWidth: 1))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Scope.allCases) { s in
                        let selected = s == scope
                        Button { scope = s } label: {
                            Text(s.rawValue)
                                .font(.troveMono(12, selected ? .medium : .regular))
                                .foregroundStyle(selected ? .white : Theme.ink2)
                                .padding(.vertical, 7).padding(.horizontal, 14)
                                .background(selected ? Theme.accent : Theme.surface, in: Capsule())
                                .overlay(Capsule().stroke(Theme.line, lineWidth: selected ? 0 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func visible(_ entities: [Entity]) -> [Entity] {
        var list: [Entity]
        switch scope {
        case .all: list = entities.filter { !$0.isArchived }
        case .people: list = entities.filter { !$0.isArchived && $0.isPerson }
        case .topics: list = entities.filter { !$0.isArchived && !$0.isPerson }
        case .archived: list = entities.filter { $0.isArchived }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { list = list.filter { $0.name.lowercased().contains(q) } }
        return list
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

/// Reusable empty / error block with an optional primary action and/or retry.
struct MessageBlock: View {
    let title: String
    let detail: String
    var retry: (() -> Void)? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.troveSerif(20)).foregroundStyle(Theme.ink)
            Text(detail).font(.troveMono(12)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PillButtonStyle(filled: true))
                    .padding(.top, 4)
                    .frame(maxWidth: 220)
            }
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
