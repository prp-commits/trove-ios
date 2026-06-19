import SwiftUI

struct PulseView: View {
    @Environment(Session.self) private var session
    @State private var state: Loadable<[PulseItem]> = .idle

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

                    switch state {
                    case .idle, .loading:
                        ProgressView().tint(Theme.ink).frame(maxWidth: .infinity).padding(.top, 60)
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
        }
        .task { if case .idle = state { await load() } }
        .onChange(of: session.dataVersion) { Task { await load() } }
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
        .navigationDestination(for: PulseTarget.self) { t in
            EntityDetailView(entityId: t.id, name: t.name)
        }
    }

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
                compactButton("Confirm") { Haptics.success(); try? await session.confirmEvent(eid) }
            } else {
                compactButton("Reached out") { Haptics.success(); try? await session.actEvent(eid) }
            }
        } else {
            compactButton("Caught up") { Haptics.success(); try? await session.logContact(entityId: item.id) }
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

    private func load() async {
        state = .loading
        do { state = .loaded(try await session.loadPulse()) }
        catch { state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription) }
    }
}
