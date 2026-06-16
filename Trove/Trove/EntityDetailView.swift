import SwiftUI

struct EntityDetailView: View {
    @Environment(Session.self) private var session
    let entityId: Int
    let name: String
    @State private var state: Loadable<EntityDetail> = .idle

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
                    if detail.insights.isEmpty {
                        MessageBlock(title: "No insights yet",
                                     detail: "Notes you capture about \(detail.name) will show here.")
                    } else {
                        ForEach(detail.insights) { InsightRow(insight: $0) }
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

    private func load() async {
        state = .loading
        do { state = .loaded(try await session.loadEntity(entityId)) }
        catch { state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription) }
    }
}

private struct InsightRow: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insight.text)
                .font(.troveMono(13))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if insight.hasPhoto {
                    Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                Text(metaLine).font(.troveMono(10)).foregroundStyle(Theme.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
    }

    private var metaLine: String {
        let parts = [insight.sourceKind?.capitalized, DateUtils.friendly(insight.createdAt)]
            .compactMap { $0 }
        return parts.joined(separator: " · ")
    }
}
