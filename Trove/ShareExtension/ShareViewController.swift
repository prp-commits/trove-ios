import UIKit
import Social
import UniformTypeIdentifiers

/// Trove Share Extension — capture a URL, selected text, or photo from any app's
/// share sheet straight into `/api/ingest`. Reuses the app's session via the
/// shared keychain (SharedKeychain).
///
/// Functional-first cut: the system compose box hosts the optional note; a themed
/// SwiftUI sheet + success toast is a later UX refinement (per "functionality
/// first"). On failure we surface an alert so a capture never fails silently.
class ShareViewController: SLComposeServiceViewController {

    override func presentationAnimationDidFinish() {
        placeholder = "Add a note (optional)"
    }

    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        let note = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task {
            do {
                try await Self.handle(items: items, note: note)
                await MainActor.run { self.complete() }
            } catch {
                await MainActor.run { self.fail(error) }
            }
        }
    }

    override func configurationItems() -> [Any]! { [] }

    // MARK: - Completion

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func fail(_ error: Error) {
        let message = (error as? ShareIngest.IngestError)?.errorDescription ?? error.localizedDescription
        let alert = UIAlertController(title: "Couldn't save to Trove", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.extensionContext?.cancelRequest(withError: error)
        })
        present(alert, animated: true)
    }

    // MARK: - Extraction + dispatch (priority: image > url > text)

    private static func handle(items: [NSExtensionItem], note: String) async throws {
        let providers = items.flatMap { $0.attachments ?? [] }

        if let p = providers.first(where: { $0.hasImage }) {
            let (data, mediaType) = try await p.loadImage()
            try await ShareIngest.ingestImage(base64: data.base64EncodedString(),
                                              mediaType: mediaType,
                                              title: note.isEmpty ? nil : note)
            return
        }
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            let url = try await p.loadURL()
            try await ShareIngest.ingestURL(url.absoluteString)
            return
        }
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            let text = try await p.loadText()
            let combined = note.isEmpty ? text : text + "\n\n" + note
            try await ShareIngest.ingestText(combined, title: nil)
            return
        }
        // Nothing recognized but the user typed a note → capture it as text.
        if !note.isEmpty {
            try await ShareIngest.ingestText(note, title: nil)
            return
        }
        throw ShareIngest.IngestError.badResponse
    }
}

// MARK: - NSItemProvider async helpers

private extension NSItemProvider {
    var hasImage: Bool { hasItemConformingToTypeIdentifier(UTType.image.identifier) }

    /// Original image bytes + media type — preferring the source format so the
    /// backend can read EXIF (capture date / GPS, which anchor event dates).
    func loadImage() async throws -> (Data, String) {
        let preferred: [(UTType, String)] = [
            (.jpeg, "image/jpeg"), (.heic, "image/heic"),
            (.heif, "image/heif"), (.png, "image/png"),
        ]
        for (type, media) in preferred where hasItemConformingToTypeIdentifier(type.identifier) {
            if let data = try? await resolveData(type) { return (data, media) }
        }
        // Generic image fallback (often a file URL or a UIImage).
        let item = try await resolveItem(UTType.image.identifier)
        if let url = item as? URL, let data = try? Data(contentsOf: url) {
            return (data, mediaType(forExtension: url.pathExtension))
        }
        if let image = item as? UIImage, let jpeg = image.jpegData(compressionQuality: 0.9) {
            return (jpeg, "image/jpeg")
        }
        if let data = item as? Data { return (data, "image/jpeg") }
        throw ShareIngest.IngestError.badResponse
    }

    func loadURL() async throws -> URL {
        let item = try await resolveItem(UTType.url.identifier)
        if let url = item as? URL { return url }
        if let data = item as? Data, let s = String(data: data, encoding: .utf8), let url = URL(string: s) { return url }
        if let s = item as? String, let url = URL(string: s) { return url }
        throw ShareIngest.IngestError.badResponse
    }

    func loadText() async throws -> String {
        let item = try await resolveItem(UTType.plainText.identifier)
        if let s = item as? String { return s }
        if let data = item as? Data, let s = String(data: data, encoding: .utf8) { return s }
        throw ShareIngest.IngestError.badResponse
    }

    private func mediaType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }

    func resolveData(_ type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            _ = loadDataRepresentation(for: type) { data, err in
                if let err { cont.resume(throwing: err) }
                else if let data { cont.resume(returning: data) }
                else { cont.resume(throwing: ShareIngest.IngestError.badResponse) }
            }
        }
    }

    func resolveItem(_ identifier: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { cont in
            loadItem(forTypeIdentifier: identifier, options: nil) { item, err in
                if let err { cont.resume(throwing: err) }
                else if let item { cont.resume(returning: item) }
                else { cont.resume(throwing: ShareIngest.IngestError.badResponse) }
            }
        }
    }
}
