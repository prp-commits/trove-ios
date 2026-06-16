# Trove iOS

The native **SwiftUI** client for **Trove** — a private relationship-and-knowledge second brain. This app is a pure consumer of the Trove REST API; it reuses none of the web UI but targets the full feature set (Library, Capture, Review nudges, Pulse, Ask).

> **The product is the relationship layer, not notes search.** Every screen should help the user *show up for the people and topics they care about* — via the private relationship graph and proactive, time-aware nudges. (See the design doc.)

## Where the source of truth lives

This repo is the iOS client only. The backend, the API contract, and the product/design docs live in the **Trove (Personal Insights)** repo:

- **API contract:** `../Personal Insights/docs/API.md` — the canonical request/response shapes this app builds against. **Read this first.**
- **Build roadmap:** `../Personal Insights/docs/IOS_ROADMAP.md` — setup, milestones M0–M8, deploy + TestFlight.
- **Product/design:** `../Personal Insights/docs/DESIGN.md` (positioning, the "Monad" visual system, principles).
- **Backend/architecture:** `../Personal Insights/docs/ARCHITECTURE.md`.

## Requirements

- macOS with **Xcode 16+**
- **iOS 17.0+** deployment target
- A running Trove backend (see "Backend" below)

## Getting started

1. Create the Xcode project per **IOS_ROADMAP §4** (`Trove`, SwiftUI, Storage: None) **inside this folder**, and let it use this existing git repo (uncheck "Create Git repository" in the Xcode dialog).
2. Point the app at a backend (see below).
3. Build & run on the simulator. Sign in with the **Demo** account to explore.

## Backend

The app talks to the Trove API over HTTPS/JSON with a Bearer token.

- **Simulator:** can reach your Mac's local server at `http://localhost:3100`.
- **Real device / TestFlight:** a phone *cannot* reach `localhost` — the backend must be deployed to a **public HTTPS URL** first (see IOS_ROADMAP §3 + §8).

The base URL is configured locally (e.g. a `Secrets.xcconfig`, gitignored) — never hard-code a deployed URL or any key into tracked source.

## Architecture (target)

MVVM with `@Observable` view models, `async/await`, a single `APIClient` (URLSession) that attaches the bearer + `X-Timezone` and handles 401→refresh→retry, tokens in the **Keychain**, online-first now with a delta-sync (`GET /api/sync`) cache added in M7. Folder layout and conventions: IOS_ROADMAP §5.

## Status

🚧 Scaffolding. Xcode project to be created (roadmap §4); first code milestone is **M0** (design system + networking + auth).
