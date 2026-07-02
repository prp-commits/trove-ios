import SwiftUI

/// "Recent captures" — surfaces async video-summarization jobs (D141, Phase B) so
/// a reel shared while backgrounded, or one that failed, is never silently lost.
/// Pending → done/failed, with a Retry on failures. Reached from Profile.
struct RecentCapturesView: View {
    @Environment(Session.self) private var session
    @State private var state: Loadable<[VideoJob]> = .idle
    @State private var retrying: Set<Int> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch state {
                case .idle, .loading:
                    ProgressView().tint(Theme.ink).frame(maxWidth: .infinity).padding(.top, 60)
                case .failed(let message):
                    MessageBlock(title: "Couldn't load", detail: message) { Task { await load() } }
                case .loaded(let jobs):
                    if jobs.isEmpty {
                        MessageBlock(title: "No video captures yet",
                                     detail: "Share a reel, Short, or TikTok to Trove and it'll show up here while it's summarized.")
                    } else {
                        ForEach(jobs) { row($0) }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .navigationTitle("Recent captures")
        .navigationBarTitleDisplayMode(.inline)
        .task { if case .idle = state { await load() } }
        .refreshable { await load() }
    }

    private func row(_ job: VideoJob) -> some View {
        HStack(spacing: 12) {
            statusIcon(job)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.providerLabel).font(.troveMono(13, .medium)).foregroundStyle(Theme.ink)
                Text(statusLine(job)).font(.troveMono(10)).foregroundStyle(Theme.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if job.isFailed {
                Button(retrying.contains(job.id) ? "…" : "Retry") { retry(job) }
                    .buttonStyle(PillButtonStyle(filled: false))
                    .font(.troveMono(11))
                    .disabled(retrying.contains(job.id))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }

    @ViewBuilder private func statusIcon(_ job: VideoJob) -> some View {
        if job.isPending { ProgressView().tint(Theme.gold) }
        else if job.isFailed { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
        else { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold) }
    }

    private func statusLine(_ job: VideoJob) -> String {
        if job.isPending { return "Summarizing…" }
        if job.isFailed { return job.reason ?? "Couldn't summarize — tap Retry" }
        return "Saved · \(DateUtils.friendly(job.createdAt) ?? "")"
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await session.loadVideoJobs()) }
        catch { state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription) }
    }

    private func retry(_ job: VideoJob) {
        retrying.insert(job.id)
        Task {
            try? await session.retryVideo(url: job.url)
            try? await Task.sleep(for: .seconds(1))
            await load()
            retrying.remove(job.id)
        }
    }
}
