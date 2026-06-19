import SwiftUI

/// Pick a target to merge the current entity INTO. Same-type, non-archived,
/// excludes self. On success the source is absorbed and gone → onMerged() pops
/// the (now-stale) detail behind us.
struct MergePicker: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let sourceId: Int
    let sourceName: String
    let sourceIsPerson: Bool
    var onMerged: () -> Void

    @State private var state: Loadable<[Entity]> = .idle
    @State private var query = ""
    @State private var target: Entity?
    @State private var error: String?
    @State private var merging = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    Text("Merge **\(sourceName)** into another \(sourceIsPerson ? "person" : "topic"). Its notes move over and \(sourceName) is removed.")
                        .font(.troveMono(12)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)

                    switch state {
                    case .idle, .loading:
                        ProgressView().tint(Theme.ink).padding(.top, 40)
                    case .failed(let m):
                        MessageBlock(title: "Couldn't load entities", detail: m) { Task { await load() } }
                    case .loaded(let entities):
                        let options = candidates(entities)
                        if options.isEmpty {
                            MessageBlock(title: "No targets", detail: "No other \(sourceIsPerson ? "people" : "topics") to merge into.")
                        } else {
                            ForEach(options) { e in
                                Button { target = e } label: { row(e) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Merge into…")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(Theme.ink)
                }
            }
            .task { if case .idle = state { await load() } }
            .confirmationDialog("Merge \(sourceName) into \(target?.name ?? "")?",
                                isPresented: Binding(get: { target != nil && !merging },
                                                     set: { if !$0 { target = nil } }),
                                titleVisibility: .visible, presenting: target) { t in
                Button("Merge", role: .destructive) { Task { await merge(into: t) } }
                Button("Cancel", role: .cancel) {}
            } message: { t in
                Text("\(sourceName)'s notes move into \(t.name). This can't be undone.")
            }
            .alert("Couldn't merge", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func row(_ e: Entity) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                TypeChip(isPerson: e.isPerson)
                Text(e.name).font(.troveSerif(18)).foregroundStyle(Theme.ink)
                Text(e.insightCountText).font(.troveMono(11)).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
    }

    private func candidates(_ entities: [Entity]) -> [Entity] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return entities.filter {
            $0.id != sourceId && !$0.isArchived && $0.isPerson == sourceIsPerson
                && (q.isEmpty || $0.name.lowercased().contains(q))
        }
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await session.loadEntities()) }
        catch { state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription) }
    }

    private func merge(into t: Entity) async {
        merging = true
        do {
            try await session.mergeEntity(sourceId: sourceId, intoId: t.id)
            onMerged()   // pops the stale detail behind the sheet (also closes this sheet)
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            merging = false
            target = nil
        }
    }
}
