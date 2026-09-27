import SwiftUI
import AppKit
import CuebarCore

/// Displays album artwork inside a rounded box.
///
/// Paints cached art on the first frame, otherwise shows a music-note
/// placeholder and fades the fetched image in. Always clips to the rounded
/// corner so artwork never spills outside the tile.
struct ArtworkView: View {
    let source: ArtworkSource?
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 7

    @State private var image: NSImage?

    init(source: ArtworkSource?, size: CGFloat = 36, cornerRadius: CGFloat = 7) {
        self.source = source
        self.size = size
        self.cornerRadius = cornerRadius
        // First-frame paint from the synchronous cache.
        _image = State(initialValue: source.flatMap { ArtworkStore.shared.cachedImage(for: $0) })
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: source) {
            guard let source else {
                image = nil
                return
            }
            if let cached = ArtworkStore.shared.cachedImage(for: source) {
                image = cached
                return
            }
            image = nil
            let fetched = await ArtworkStore.shared.image(for: source)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.15)) {
                image = fetched
            }
        }
    }
}
