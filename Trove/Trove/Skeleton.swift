import SwiftUI

// Content-shaped loading placeholders (#7). A calm shimmer — never a spinner —
// so a cold fetch (e.g. Render cold-start) reads as "the content is coming",
// not "this is broken". Skeletons mirror each surface's real card layout so the
// transition to loaded content is a settle, not a jump.

/// A gentle highlight sweeping across a placeholder block. Honors Reduce Motion
/// (static block, no sweep) — calm by default.
private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: phase * geo.size.width * 1.6)
                            .blendMode(.plusLighter)
                    }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

/// One rounded placeholder bar. `width == nil` fills the available width.
struct SkeletonBlock: View {
    var height: CGFloat
    var width: CGFloat? = nil
    var cornerRadius: CGFloat = 7

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        shape.fill(Theme.line)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .modifier(Shimmer())
            .clipShape(shape)
    }
}

// MARK: - Per-surface skeletons (mirror the real layouts)

/// Library: a stack of entity-row cards (chip · name · count).
struct LibrarySkeleton: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock(height: 12, width: 58, cornerRadius: 6)
                    SkeletonBlock(height: 18, width: 150)
                    SkeletonBlock(height: 11, width: 76, cornerRadius: 6)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))
            }
        }
        .padding(.top, 4)
    }
}

/// Pulse: the four warmth tiles.
struct PulseSkeleton: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock(height: 20, width: 110)
                    SkeletonBlock(height: 11, width: 180, cornerRadius: 6)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.radiusCard))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))
            }
        }
        .padding(.top, 4)
    }
}

/// Review: a single deck card filling the play area.
struct ReviewSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(height: 18, width: 88, cornerRadius: 8)
            SkeletonBlock(height: 24)
            SkeletonBlock(height: 24, width: 210)
            SkeletonBlock(height: 13, width: 120, cornerRadius: 6)
            Spacer(minLength: 24)
            SkeletonBlock(height: 12)
            SkeletonBlock(height: 12, width: 240, cornerRadius: 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.line, lineWidth: 1))
        .padding(.top, 12)
    }
}
