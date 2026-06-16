import SwiftUI

/// In-memory cache of fetched attachment images, keyed by source id.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private var store: [Int: UIImage] = [:]
    func get(_ id: Int) -> UIImage? { store[id] }
    func set(_ id: Int, _ image: UIImage) { store[id] = image }
}

/// Loads a Bearer-gated attachment image (GET /api/sources/:id/image) into an
/// Image. A plain `<img>`/AsyncImage can't send the token, so we fetch the bytes
/// via the APIClient and build a UIImage. Tap → full-screen.
struct RemoteImage: View {
    @Environment(Session.self) private var session
    let sourceId: Int
    var maxWidth: CGFloat = 220
    var maxHeight: CGFloat = 160

    @State private var image: UIImage?
    @State private var showFull = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { showFull = true }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.line)
                    .frame(width: 120, height: 90)
                    .overlay(ProgressView().tint(Theme.muted))
            }
        }
        .task { await load() }
        .fullScreenCover(isPresented: $showFull) {
            if let image { ImageLightbox(image: image) { showFull = false } }
        }
    }

    private func load() async {
        if image != nil { return }
        if let cached = ImageCache.shared.get(sourceId) { image = cached; return }
        if let data = try? await session.image(sourceId: sourceId), let ui = UIImage(data: data) {
            ImageCache.shared.set(sourceId, ui)
            image = ui
        }
    }
}

struct ImageLightbox: View {
    let image: UIImage
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(16)
        }
        .onTapGesture { onClose() }
    }
}
