import SwiftUI

/// Value-first first-run (P0 #1). Instead of dropping a new tester into an empty
/// Library, we lead with the habit they already have — remembering one small thing
/// about one real person — and let them watch Trove give it a home. The "aha" in
/// under a minute, on their own data, *before* any permission ask.
///
/// Sequencing: RootView shows this for a signed-in user who hasn't onboarded; on
/// completion the flag flips and MainTabView appears (which then runs notification
/// priming). A non-empty library (demo / returning user) short-circuits silently.
struct FirstRunView: View {
    @Environment(Session.self) private var session
    var onComplete: () -> Void

    enum Beat { case intro, capture, build }
    enum Phase { case working, done(IngestResponse), error(String) }

    @State private var beat: Beat = .intro
    @State private var text = ""
    @State private var phase: Phase = .working
    @State private var captureError: String?
    @State private var ready = false           // gates first paint until we know the library is empty
    @State private var checked = false

    // "Filed it" reveal (shared vocabulary with CaptureView #5).
    @State private var revealed = false
    @State private var landed = false

    /// A rotation of example scraps — each names a person, gives context, and
    /// carries a rememberable detail (a date, a preference, a milestone, a worry)
    /// so the user learns by example what's worth capturing. One is chosen at
    /// random per first-run and used for both the placeholder and the fill.
    private static let examples: [String] = [
        "Coffee with Priya today — she just adopted a rescue pup named Biscuit, and her birthday's March 3.",
        "Dinner with Marcus — he started a new job at a design studio and is nervous about the first week.",
        "Caught up with Aunt Rosa — her knee surgery is on the 12th and she's a little anxious about it.",
        "Lunch with Dev — he's training for his first marathon in October and changed up his diet.",
        "Talked to Mom — she's been taking pottery classes on Thursdays and absolutely loving it.",
        "Ran into Sofia — she's expecting a baby girl, due around late May.",
        "Drinks with James — he just moved to Austin and doesn't know many people there yet.",
        "Chatted with Leah — she's allergic to shellfish, good to remember before the dinner party.",
        "Call with Grandpa — he loves old western films, especially anything with John Wayne.",
        "Saw Nina — her thesis defense is next month and she could use some encouragement.",
        "Brunch with Omar — he's deep into specialty coffee and recommended a roaster downtown.",
        "Hung out with Tara — her son Eli just started kindergarten and she's a little emotional about it.",
        "Coffee with Ben — he's switching careers into nursing and just got into a program.",
        "Talked to Maya — she's planning a trip to Japan in the fall and asked for restaurant tips.",
        "Dinner with the Patels — their 10-year anniversary is coming up on the 20th.",
        "Caught up with Chris — he's been carrying his dad's illness and feeling worn down.",
        "Met Aisha — she just published her first short story and was thrilled about it.",
        "Saw Grandma — she's been lonely since the move, said calls mean a lot to her.",
        "Lunch with Theo — he's vegetarian now and into rock climbing on weekends.",
        "Chatted with Hannah — she got promoted to team lead and is celebrating Friday.",
    ]
    @State private var example = FirstRunView.examples.randomElement() ?? FirstRunView.examples[0]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if ready {
                content
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: beat)
        .animation(.easeInOut(duration: 0.3), value: ready)
        .task { await decideEntry() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(); Button("Done") { hideKeyboard() }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch beat {
        case .intro:   intro
        case .capture: capture
        case .build:   build
        }
    }

    // MARK: Beat 1 — frame the habit

    private var intro: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(Theme.gold)
            Text("You already remember\nthe little things.")
                .font(.troveSerif(30)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("A new job. A baby on the way. The restaurant they loved. Trove just gives them a home — and brings them back when they matter.")
                .font(.troveMono(14)).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center).lineSpacing(3)
                .padding(.horizontal, 6)
            Spacer()
            Button("Try it with someone real") {
                beat = .capture
            }
            .buttonStyle(PillButtonStyle(filled: true))
            Button("Skip for now") { skip() }
                .font(.troveMono(13)).foregroundStyle(Theme.muted).padding(.top, 2)
        }
        .padding(.horizontal, 32).padding(.vertical, 44)
    }

    // MARK: Beat 2 — capture one scrap (their input)

    private var capture: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 12)
                Text("Think of one person\nyou saw recently.")
                    .font(.troveSerif(28)).foregroundStyle(Theme.ink)
                Text("What's something you'd want to remember about them?")
                    .font(.troveMono(14)).foregroundStyle(Theme.ink2).lineSpacing(2)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("e.g. \(example)")
                            .font(.troveMono(14)).foregroundStyle(Theme.muted)
                            .padding(.top, 14).padding(.horizontal, 12)
                    }
                    TextEditor(text: $text)
                        .font(.troveMono(14))
                        .frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusField))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusField).stroke(Theme.line, lineWidth: 1))

                Text("Write it like you'd text a friend. Trove sorts out the details.")
                    .font(.troveMono(11)).foregroundStyle(Theme.muted)

                Button("Not sure? Use an example") {
                    text = example; captureError = nil
                }
                .font(.troveMono(12, .medium)).foregroundStyle(Theme.gold)

                if let captureError {
                    Text(captureError)
                        .font(.troveMono(12)).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Watch Trove file it") { submit() }
                    .buttonStyle(PillButtonStyle(filled: true))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, 4)
                Button("Skip for now") { skip() }
                    .font(.troveMono(13)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 28).padding(.vertical, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Beat 3 — the build (aha)

    @ViewBuilder private var build: some View {
        switch phase {
        case .working:
            VStack(spacing: 16) {
                Spacer(minLength: 12)
                profileSkeleton
                Text("Reading what matters…")
                    .font(.troveMono(12)).foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(.horizontal, 28).padding(.vertical, 28)

        case .done(let res):
            doneView(res)

        case .error(let message):
            VStack(spacing: 14) {
                Spacer()
                MessageBlock(title: "That didn't go through", detail: message) {
                    beat = .capture; phase = .working
                }
                Button("Skip for now") { skip() }
                    .font(.troveMono(13)).foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(.horizontal, 28)
        }
    }

    private func doneView(_ res: IngestResponse) -> some View {
        let primary = res.insights.first?.entity
        let bullets = res.insights.filter { $0.entity.id == primary?.id }
        return ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 12)
                FiledMark(revealed: revealed)
                Text("Filed it").font(.troveSerif(26)).foregroundStyle(Theme.ink)

                if let primary {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(primary.name).font(.troveSerif(24)).foregroundStyle(Theme.ink)
                        TypeChip(isPerson: primary.type == "person")
                        if !bullets.isEmpty {
                            Rectangle().fill(Theme.line).frame(height: 1)
                            ForEach(Array(bullets.enumerated()), id: \.element.id) { i, ins in
                                Text("• \(ins.text)")
                                    .font(.troveMono(13)).foregroundStyle(Theme.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .opacity(landed ? 1 : 0)
                                    .offset(y: landed ? 0 : 10)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.8)
                                        .delay(0.2 + Double(i) * 0.08), value: landed)
                            }
                        }
                        Label("I'll remind you when it's time to reach out", systemImage: "sparkles")
                            .font(.troveMono(11, .medium)).foregroundStyle(Theme.gold)
                            .padding(.top, 2)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))
                }

                Text(primary.map { "Everything you save about \($0.name) lives here — and Trove brings them back when it counts." }
                     ?? "Everything you save lives here — and Trove brings it back when it counts.")
                    .font(.troveMono(12)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center).lineSpacing(2)
                    .padding(.horizontal, 8)

                Button("Open my Trove") { complete() }
                    .buttonStyle(PillButtonStyle(filled: true))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 28).padding(.vertical, 28)
        }
    }

    private var profileSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(height: 24, width: 160)
            SkeletonBlock(height: 12, width: 58, cornerRadius: 6)
            Rectangle().fill(Theme.line).frame(height: 1)
            SkeletonBlock(height: 13)
            SkeletonBlock(height: 13, width: 220, cornerRadius: 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))
    }

    // MARK: flow

    /// A non-empty library means demo or a returning user — skip onboarding silently.
    private func decideEntry() async {
        guard !checked else { return }
        checked = true
        if let entities = try? await session.loadEntities(), !entities.isEmpty {
            onComplete()
            return
        }
        Analytics.capture("onboarding_started")
        ready = true
    }

    private func submit() {
        let scrap = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scrap.isEmpty else { return }
        hideKeyboard()
        captureError = nil
        beat = .build
        phase = .working
        Task {
            do {
                let res = try await session.ingestText(scrap)
                guard !res.insights.isEmpty else {
                    captureError = "I couldn't spot a person or topic in that. Try again, or tap the example."
                    beat = .capture
                    return
                }
                Haptics.success()
                Analytics.capture("onboarding_captured", ["count": res.count])
                phase = .done(res)
                playReveal()
            } catch {
                phase = .error((error as? APIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func playReveal() {
        revealed = false; landed = false
        withAnimation { revealed = true }
        landed = true
    }

    private func skip() {
        Analytics.capture("onboarding_skipped")
        onComplete()
    }

    private func complete() {
        Analytics.capture("onboarding_completed")
        onComplete()
    }
}
