import SwiftUI

struct EntityDetailView: View {
    @Environment(Session.self) private var session
    let entityId: Int
    let name: String
    @State private var state: Loadable<EntityDetail> = .idle
    @State private var showAdd = false
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch state {
                case .idle, .loading:
                    ProgressView().tint(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.top, 80)
                case .failed(let message):
                    MessageBlock(title: "Couldn't load this profile", detail: message) {
                        Task { await load() }
                    }
                case .loaded(let detail):
                    header(detail)
                    actions(detail)
                    if detail.insights.isEmpty {
                        MessageBlock(title: "No insights yet",
                                     detail: "Notes you capture about \(detail.name) will show here.")
                    } else {
                        ForEach(detail.insights) { insight in
                            InsightRow(insight: insight) { id in
                                Task { await delete(id) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Theme.bg)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task { if case .idle = state { await load() } }
        .sheet(isPresented: $showAdd) {
            CaptureView(onIngested: { Task { await reload() } },
                        pinnedEntity: (id: entityId, name: name))
        }
    }

    private func header(_ d: EntityDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(d.name).font(.troveSerif(30)).foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                TypeChip(isPerson: d.isPerson)
                Text("\(d.insights.count) insight\(d.insights.count == 1 ? "" : "s")")
                    .font(.troveMono(11)).foregroundStyle(Theme.muted)
            }
            if let aliases = d.aliases, !aliases.isEmpty {
                Text("also: \(aliases.joined(separator: ", "))")
                    .font(.troveMono(11)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actions(_ d: EntityDetail) -> some View {
        HStack(spacing: 10) {
            Button { Task { await catchUp(d.id) } } label: {
                Label(d.isPerson ? "Log catch-up" : "Mark revisited", systemImage: "checkmark.circle")
            }
            .buttonStyle(PillButtonStyle(filled: false))

            Button { showAdd = true } label: {
                Label("Add insight", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle(filled: true))
        }
        .font(.troveMono(13))
        .disabled(working)
        .padding(.bottom, 6)
    }

    // MARK: actions

    private func load() async {
        state = .loading
        do { state = .loaded(try await session.loadEntity(entityId)) }
        catch { state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription) }
    }

    private func reload() async {
        if let detail = try? await session.loadEntity(entityId) { state = .loaded(detail) }
    }

    private func catchUp(_ id: Int) async {
        working = true
        try? await session.logContact(entityId: id)
        await reload()
        working = false
    }

    private func delete(_ id: Int) async {
        try? await session.deleteInsight(id)
        await reload()
    }
}

private struct InsightRow: View {
    let insight: Insight
    var onDelete: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insight.text)
                .font(.troveMono(13))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if insight.hasPhoto, let sid = insight.sourceId {
                RemoteImage(sourceId: sid)
            }
            Text(metaLine).font(.troveMono(10)).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
        .contextMenu {
            Button(role: .destructive) { onDelete(insight.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var metaLine: String {
        [insight.sourceKind?.capitalized, DateUtils.friendly(insight.createdAt)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

