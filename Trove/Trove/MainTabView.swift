import SwiftUI

struct MainTabView: View {
    let user: User
    @Environment(Session.self) private var session
    @Environment(NotificationManager.self) private var notifications
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var showNudgePriming = false
    @State private var showDeviceSyncPriming = false
    @AppStorage("hasPrimedNudges") private var hasPrimedNudges = false
    @AppStorage("hasPrimedDeviceSync") private var hasPrimedDeviceSync = false
    // (D227) The one-time "there's something in Pulse" dot. Review gets discovered contextually
    // (push nudges deep-link to it); Pulse had no such moment. Shown once Review's deck has had
    // cards — the honest proxy for "Pulse has actionable content", set in ReviewView (D224) and
    // shared via @AppStorage — and cleared FOREVER on the first Pulse visit. No modal, no tour.
    @AppStorage("hasSeenDeckCards") private var hasSeenDeckCards = false
    @AppStorage("hasVisitedPulse") private var hasVisitedPulse = false
    private var pulseBadge: Bool { hasSeenDeckCards && !hasVisitedPulse }
    // A shared video that failed to process surfaces as a one-time banner on open
    // (a reel typically fails ~60s after sharing, while the app is backgrounded).
    // `lastSeenFailedVideoJobId` dedups so a given failure is shown once.
    @State private var failedVideo: VideoJob?
    @State private var retryingFailedVideo = false
    @AppStorage("lastSeenFailedVideoJobId") private var lastSeenFailedVideoJobId = 0
    // D169: a tapped capture nudge opens the capture composer (not Review).
    @State private var showCaptureFromPush = false

    var body: some View {
        TabView(selection: Binding(
            get: { tab },
            set: { newTab in
                // (D224) The funnel was blind to which tabs anyone visits — no way to tell if
                // Pulse is ever opened, or whether Review gets reached other than via a push
                // deep-link. Content-free: the tab index only. Fires on real changes, not the
                // initial paint.
                if newTab != tab {
                    let names = ["library", "review", "pulse", "profile"]
                    let name = names.indices.contains(newTab) ? names[newTab] : "unknown"
                    Analytics.capture("tab_selected", ["tab": name])
                    // (D227) First visit to Pulse retires the badge. If it was showing, record the
                    // conversion so we can tell whether the dot actually drove the visit.
                    if newTab == 2 {
                        if pulseBadge { Analytics.capture("pulse_badge_tapped") }
                        hasVisitedPulse = true
                    }
                }
                tab = newTab
            }
        )) {
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(0)

            ReviewView()
                .tabItem { Label("Review", systemImage: "rectangle.portrait.on.rectangle.portrait") }
                .tag(1)

            PulseView()
                .tabItem { Label("Pulse", systemImage: "waveform.path.ecg") }
                .badge(pulseBadge ? " " : nil)   // (D227) native dot; empty string collapses to a dot
                .tag(2)

            ProfileView(user: user)
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(3)
        }
        .tint(Theme.ink)
        // Failed-video banner — shown on open for a video that couldn't be processed
        // (mirrors the transactional failure push, but works on the current build
        // without remote APNs). Dismiss or Retry; never re-shown for the same job.
        .overlay(alignment: .top) {
            if let job = failedVideo {
                videoFailedBanner(job)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .task { await checkFailedVideos() }                 // initial open
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await checkFailedVideos() } }   // every foreground
        }
        // Push / right-time delivery (D115): prime BEFORE the system prompt. Only
        // show the warm explainer when status is undetermined and we haven't asked;
        // otherwise just (re)register — already-determined states never re-prompt.
        .task {
            notifications.configure(session: session)
            let status = await notifications.authorizationStatus()
            if status == .notDetermined && !hasPrimedNudges {
                showNudgePriming = true
            } else {
                await notifications.requestAuthorizationAndRegister()
                considerDeviceSyncPriming()   // nudges already handled → consider calendar
            }
        }
        .sheet(isPresented: $showNudgePriming) {
            NudgePrimingView(
                onEnable: {
                    hasPrimedNudges = true
                    showNudgePriming = false
                    Task { await notifications.requestAuthorizationAndRegister() }
                    considerDeviceSyncPriming()
                },
                onSkip: {
                    hasPrimedNudges = true
                    showNudgePriming = false
                    considerDeviceSyncPriming()
                }
            )
        }
        .sheet(isPresented: $showDeviceSyncPriming) {
            DeviceSyncPrimingView(
                deniedMode: CalendarSync.shared.isDenied,
                onConnect: {
                    hasPrimedDeviceSync = true
                    showDeviceSyncPriming = false
                    if CalendarSync.shared.isDenied {
                        // Can't re-prompt — remember the intent so a return-after-enable
                        // auto-syncs, and send them to Settings.
                        UserDefaults.standard.set(true, forKey: DeviceSync.enabledKey)
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } else {
                        Task { await DeviceSync.connect(session) }
                    }
                },
                onSkip: {
                    hasPrimedDeviceSync = true
                    showDeviceSyncPriming = false
                }
            )
        }
        // D169: a capture nudge opens the capture COMPOSER. Present it at tab-level so it opens from
        // any tab; onDismiss clears the scenario tag.
        .sheet(isPresented: $showCaptureFromPush, onDismiss: { notifications.pendingCaptureScenario = nil }) {
            CaptureView(onIngested: {})   // ingest success emits capture_after_nudge via the tracker
        }
        // Tap routing. A capture nudge → the composer (+ capture_nudge_opened, and stamp the tap so
        // the next ingest emits capture_after_nudge). A transactional video_failed push isn't a nudge
        // (just opens the app). Everything else (moat nudges) → Review.
        .onChange(of: notifications.pendingDeepLink) { _, ref in
            guard let ref else { return }
            // Unified tap/open signal for every real nudge — the open-rate numerator (nudge_shown is
            // the deck-side denominator). Content-free: nudge_ref is "<kind>:<id>" (db.js), so we send
            // ONLY the kind prefix ("together"/"reconnect"/"connect"/"capture") and drop the id.
            // video_failed is transactional, not a nudge, so it's excluded. A capture tap fires this
            // AND capture_nudge_opened (which adds the scenario dimension).
            if !ref.hasPrefix("video_failed") {
                let kind = ref.split(separator: ":").first.map(String.init) ?? ref
                Analytics.capture("nudge_opened", ["nudge_kind": kind])
            }
            if ref == "capture" {
                let scenario = notifications.pendingCaptureScenario
                Analytics.capture("capture_nudge_opened", ["scenario": scenario ?? "unknown"])
                CaptureNudgeTracker.noteTap(scenario: scenario)
                showCaptureFromPush = true
            } else if !ref.hasPrefix("video_failed") {
                tab = 1
            }
            notifications.pendingDeepLink = nil
        }
    }

    // MARK: failed-video banner

    @ViewBuilder private func videoFailedBanner(_ job: VideoJob) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn't save that \(job.providerLabel) video")
                    .font(.troveMono(12, .medium)).foregroundStyle(Theme.ink)
                Text(job.reason ?? "We couldn't process that video.")
                    .font(.troveMono(10)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Button(retryingFailedVideo ? "Retrying…" : "Retry") { retryFailedVideo() }
                        .disabled(retryingFailedVideo)
                    Button("Dismiss") { ackFailedVideo() }
                }
                .font(.troveMono(11, .medium)).foregroundStyle(Theme.gold).padding(.top, 2)
            }
            Spacer(minLength: 0)
            Button { ackFailedVideo() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }

    /// Look for the newest FAILED video job we haven't shown yet (jobs are newest-first).
    private func checkFailedVideos() async {
        guard let jobs = try? await session.loadVideoJobs() else { return }
        if let f = jobs.first(where: { $0.isFailed && $0.id > lastSeenFailedVideoJobId }) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { failedVideo = f }
        }
    }

    /// Mark the shown failure (and any older ones) as seen, and hide the banner.
    private func ackFailedVideo() {
        if let f = failedVideo { lastSeenFailedVideoJobId = max(lastSeenFailedVideoJobId, f.id) }
        withAnimation { failedVideo = nil }
    }

    private func retryFailedVideo() {
        guard let f = failedVideo else { return }
        retryingFailedVideo = true
        Task {
            try? await session.retryVideo(url: f.url)
            ackFailedVideo()
            retryingFailedVideo = false
        }
    }

    /// Offer the calendar/contacts primer once per onboarding, whenever we're not
    /// already actively connected — including the *denied* case (there we route to
    /// Settings, since iOS won't let us re-prompt). A small delay lets the
    /// notification sheet finish dismissing before this one presents.
    private func considerDeviceSyncPriming() {
        guard !hasPrimedDeviceSync, !DeviceSync.isConnected else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            showDeviceSyncPriming = true
        }
    }
}
