# Trove iOS

The native **SwiftUI** client for **Trove** — a private relationship-and-knowledge
second brain. The product idea: instead of another notes app, a private relationship
graph plus proactive, time-aware nudges that help you *show up for the people and
topics you care about*.

This repo is the **iOS client only** — a pure consumer of the Trove REST API. The
backend is a separate private service; this app holds no data model of its own beyond
what the API returns.

> **Status:** working app, built for TestFlight. Auth, capture, library, review nudges,
> and a share extension are implemented against the live API.

---

## What it does

- **Capture** anything — type it, or share into Trove from any app via a **Share
  Extension** — and the backend extracts people, topics, and useful details from it.
- **Library** of the entities that emerge (people, topics) and the notes behind them.
- **Review nudges** — time-aware prompts to reconnect or follow up, so the graph stays
  a tool for action rather than an archive.
- **Sign in** with email/password or Google, with sessions that survive relaunch and
  transient network failures.

## Architecture

The app is deliberately thin and predictable — the interesting logic lives at the
network boundary, not in a sprawl of state.

- **MVVM with `@Observable` view models** and `async/await` throughout.
- **One `APIClient` (URLSession)** is the single choke point for the backend. It
  attaches the `Bearer` token and an `X-Timezone` header, and centralizes the
  **`401 → refresh → retry`** flow so no screen has to think about token expiry.
- **Tokens live in the Keychain**, not `UserDefaults` — and are shared with the Share
  Extension through an app group, with a staleness guard so a token left over from a
  previous account can never post under the wrong user.
- **Online-first** today, with a delta-sync (`GET /api/sync`) cache as a later
  milestone.

### A few decisions worth calling out

- **Refresh is resilient, not brittle.** A transient network failure during token
  refresh keeps the user signed in and retries, rather than bouncing them to the login
  screen — a small thing that makes the app feel trustworthy on a flaky connection.
- **Analytics are content-free by construction.** The app sends ~6 curated funnel
  events (an opaque `u<id>` plus small enum-like properties) straight to PostHog's HTTP
  API — **no SDK dependency**, and no note content, names, or messages ever leave the
  device. The demo account opts out of everything, and analytics is a hard no-op until
  a key is set. GeoIP enrichment is explicitly disabled so the "IP is discarded"
  promise holds.
- **A plain-language consent screen** states exactly what leaves the device and what
  doesn't, before any capture happens.

## Configuration (these values are intentionally in source)

A few constants live in [`Config.swift`](Trove/Trove/Config.swift) and
[`Analytics.swift`](Trove/Trove/Analytics.swift). None of them are secrets — they are
**public client-side values** that ship in every copy of any app:

- **Backend base URL** — a public HTTPS endpoint (and already inside the shipped
  binary). The build auto-selects `localhost:3100` on the simulator and the hosted URL
  on device, so there's no constant to flip.
- **PostHog project API key** (`phc_…`) — a client-side, write-only key that PostHog
  documents as safe to embed in client apps. It can send events; it cannot read data.
- **Google iOS OAuth client ID** — public by design; the backend verifies the ID
  token's audience against it.

What is *not* in the repo, by `.gitignore`: the APNs provider `.p8` key, any
`Secrets.xcconfig`, and the downloaded Google OAuth plist. Set `Config.feedbackEmail`
to your own support inbox before shipping a build.

## Build & run

- **Xcode 16+**, **iOS 17+** deployment target.
- Open the project in `Trove/`, build to the simulator.
- Point at a backend: the simulator reaches a local dev server at `http://localhost:3100`
  automatically; a real device needs the app pointed at a deployed HTTPS backend (a
  phone can't reach your Mac's `localhost`).
- Sign in with the **Demo** account to explore without a real backend account.

## Repository layout

```
Trove/
├── Trove/                 # the app target (SwiftUI views + @Observable view models)
│   ├── APIClient.swift        # single networking choke point (auth, refresh/retry)
│   ├── Session.swift          # auth + session lifecycle
│   ├── TokenStore.swift       # Keychain-backed token storage
│   ├── Config.swift           # public client config (base URL, client IDs)
│   ├── Analytics.swift        # content-free PostHog events
│   └── …                      # feature views (Library, Capture, Review, Profile, …)
├── ShareExtension/        # capture-from-anywhere share target
├── TroveTests/            # unit tests
└── TroveUITests/          # UI tests
```
