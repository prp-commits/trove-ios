import SwiftUI

struct EntityDetailView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let entityId: Int
    let name: String
    @State private var state: Loadable<EntityDetail> = .idle
    @State private var showAdd = false
    @State private var working = false
    @State private var showDelete = false
    @State private var showMerge = false

    // Last-insight delete → cascades to the entity, so confirm.
    @State private var pendingInsightDelete: Insight?
    @State private var showInsightDelete = false

    private var isArchivedNow: Bool {
        if case .loaded(let d) = state { return d.isArchived }
        return false
    }

    private var insightCount: Int {
        if case .loaded(let d) = state { return d.insights.count }
        return 0
    }

    private var isPersonNow: Bool {
        if case .loaded(let d) = state { return d.isPerson }
        return true
    }

    // Rename
    @State private var showRename = false
    @State private var renameDraft = ""
    @State private var actionError: String?

    // Edit insight
    @State private var editing: Insight?

    private var titleName: String {
        if case .loaded(let d) = state { return d.name }
        return name
    }

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
                            InsightRow(insight: insight,
                                       onEdit: { editing = insight },
                                       onDelete: { requestDelete(insight) })
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Theme.bg)
        .navigationTitle(titleName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { renameDraft = titleName; showRename = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button { showMerge = true } label: {
                        Label("Merge into…", systemImage: "arrow.triangle.merge")
                    }
                    if isArchivedNow {
                        Button { Task { await restore() } } label: {
                            Label("Restore", systemImage: "tray.and.arrow.up")
                        }
                    } else {
                        Button { Task { await archive() } } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                    }
                    Divider()
                    Button(role: .destructive) { showDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").tint(Theme.ink)
                }
            }
        }
        .task { if case .idle = state { await load() } }
        .sheet(isPresented: $showAdd) {
            CaptureView(onIngested: { Task { await reload() } },
                        pinnedEntity: (id: entityId, name: titleName))
        }
        .sheet(item: $editing) { insight in
            TextEditSheet(title: "Edit insight", initial: insight.text) { newText in
                await edit(insight.id, newText)
            }
        }
        .sheet(isPresented: $showMerge) {
            MergePicker(sourceId: entityId, sourceName: titleName, sourceIsPerson: isPersonNow,
                        onMerged: { dismiss() })
        }
        .alert("Rename", isPresented: $showRename) {
            TextField("Name", text: $renameDraft)
            Button("Save") { Task { await rename() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't rename", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .confirmationDialog("Delete \(titleName)?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteEntity() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the entity and all of its insights.")
        }
        .confirmationDialog("Delete the only insight?", isPresented: $showInsightDelete,
                            titleVisibility: .visible, presenting: pendingInsightDelete) { ins in
            Button("Delete insight & \(titleName)", role: .destructive) {
                Task { await deleteAndDismiss(ins.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This is \(titleName)'s only insight, so deleting it also removes \(titleName).")
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

    private func requestDelete(_ insight: Insight) {
        if insightCount <= 1 {
            pendingInsightDelete = insight
            showInsightDelete = true       // confirm: this removes the entity too
        } else {
            Task { await delete(insight.id) }
        }
    }

    private func delete(_ id: Int) async {
        try? await session.deleteInsight(id)
        await reload()
    }

    private func deleteAndDismiss(_ id: Int) async {
        try? await session.deleteInsight(id)
        dismiss()   // the entity is gone with its last insight; Library refreshes via dataVersion
    }

    private func edit(_ id: Int, _ text: String) async {
        try? await session.editInsight(id, text: text)
        await reload()
    }

    private func rename() async {
        let next = renameDraft.trimmingCharacters(in: .whitespaces)
        guard !next.isEmpty else { return }
        do {
            try await session.renameEntity(entityId, name: next)
            await reload()
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func archive() async {
        try? await session.archiveEntity(entityId)
        dismiss()   // leaves the default Library view; visible under "Archived"
    }

    private func restore() async {
        try? await session.restoreEntity(entityId)
        await reload()
    }

    private func deleteEntity() async {
        try? await session.deleteEntity(entityId)
        dismiss()
    }
}

private struct InsightRow: View {
    let insight: Insight
    var onEdit: () -> Void
    var onDelete: () -> Void

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
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { onDelete() } label: {
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

/// Reusable single-field text editor sheet (edit insight, etc.).
struct TextEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let initial: String
    var onSave: (String) async -> Void

    @State private var text: String
    @State private var saving = false

    init(title: String, initial: String, onSave: @escaping (String) async -> Void) {
        self.title = title
        self.initial = initial
        self.onSave = onSave
        _text = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                TextEditor(text: $text)
                    .font(.troveMono(14))
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusField))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusField).stroke(Theme.line, lineWidth: 1))
                    .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(Theme.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task { await onSave(text.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                    }
                    .tint(Theme.ink)
                    .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
