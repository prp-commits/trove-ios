import Foundation
import Observation

/// App-wide auth state + the shared APIClient. Injected into the view tree via
/// `.environment(...)` and read with `@Environment(Session.self)`.
@MainActor
@Observable
final class Session {
    enum State {
        case loading
        case signedOut
        case signedIn(User)
    }

    private(set) var state: State = .loading
    var authError: String?
    var isWorking = false

    private let tokens = TokenStore()
    let api: APIClient

    init() {
        api = APIClient(tokenStore: tokens)
    }

    /// On launch: if we have a stored session, validate it via /auth/me.
    func bootstrap() async {
        guard tokens.hasSession else { state = .signedOut; return }
        do {
            let me: MeResponse = try await api.request("/auth/me")
            state = .signedIn(me.user)
        } catch {
            state = .signedOut
        }
    }

    func signInDemo() async {
        await authenticate { try await self.api.request("/auth/demo", .post) }
    }

    func signIn(email: String, password: String) async {
        await authenticate {
            try await self.api.request("/auth/signin", .post, body: SignInRequest(email: email, password: password))
        }
    }

    func signUp(email: String, password: String, firstName: String, lastName: String) async {
        await authenticate {
            try await self.api.request(
                "/auth/signup", .post,
                body: SignUpRequest(email: email, password: password, firstName: firstName, lastName: lastName)
            )
        }
    }

    func signOut() async {
        if let refresh = tokens.refreshToken {
            _ = try? await api.request("/auth/logout", .post, body: LogoutRequest(refreshToken: refresh)) as OKResponse
        }
        tokens.clear()
        authError = nil
        state = .signedOut
    }

    // MARK: - Data (M1)

    func loadEntities() async throws -> [Entity] {
        try await api.request("/api/entities")
    }

    func loadEntity(_ id: Int) async throws -> EntityDetail {
        try await api.request("/api/entities/\(id)")
    }

    private func authenticate(_ op: @escaping () async throws -> AuthResponse) async {
        isWorking = true
        authError = nil
        do {
            let auth = try await op()
            tokens.save(access: auth.accessToken, refresh: auth.refreshToken)
            state = .signedIn(auth.user)
        } catch {
            authError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isWorking = false
    }
}
