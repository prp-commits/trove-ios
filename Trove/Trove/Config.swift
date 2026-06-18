import Foundation

/// App-wide configuration. The backend base URL lives here.
///
/// Resolves automatically by build target so there's no constant to flip:
/// - **Simulator** → your Mac's local dev server (`http://localhost:3100`) for fast
///   iteration against local changes.
/// - **Real device / TestFlight** → the deployed public HTTPS API. A phone can't
///   reach your laptop's localhost, so device builds use the hosted URL.
///
/// The URL isn't a secret (it's a public API endpoint). If you ever want
/// per-environment overrides without editing code, back this with a gitignored
/// xcconfig + Info.plist key later.
enum Config {
    /// No trailing slash. Paths passed to APIClient start with "/".
    #if targetEnvironment(simulator)
    static let baseURL = "http://localhost:3100"
    #else
    static let baseURL = "https://trove-api-wewx.onrender.com"
    #endif
}
