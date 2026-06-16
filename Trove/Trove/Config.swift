import Foundation

/// App-wide configuration. The backend base URL lives here.
///
/// - Simulator can reach your Mac's local server at `http://localhost:3100`.
/// - A real device / TestFlight build CANNOT reach localhost — point this at the
///   deployed public HTTPS URL (see IOS_ROADMAP §8). Keep real URLs/keys out of
///   tracked source; prefer a gitignored xcconfig when we deploy.
enum Config {
    /// No trailing slash. Paths passed to APIClient start with "/".
    static let baseURL = "http://localhost:3100"
}
