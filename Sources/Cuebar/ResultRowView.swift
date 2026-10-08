import SwiftUI
import AppKit
import CuebarCore

struct ResultRowView: View {
    let item: PaletteItem
    let isSelected: Bool
    /// The row's own album palette, when the theme follows the highlighted row.
    var accent: AlbumPalette?

    var body: some View {
        HStack(spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background { selectionBackground }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.3), value: accent)
    }

    /// The selected row: the system's translucent selection material with the
    /// cover's colour laid *through* it, plus the specular edge that reads as
    /// glass. Identical to the now-playing card's treatment.
    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            let shape = RoundedRectangle(cornerRadius: 10)
            shape
                .fill(.selection)
                .overlay {
                    if let accent {
                        shape.fill(
                            Color(themeColor: accent.selection)
                                .opacity(ThemeGlass.rowTintOpacity)
                        )
                    }
                }
                .overlay {
                    if accent != nil {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.34), .white.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                    }
                }
        } else {
            Color.clear
        }
    }

    // MARK: - Content

    private var title: String {
        switch item {
        case .nowPlaying(let track): return track.title
        case .command(let entry): return entry.title
        case .music(let candidate): return candidate.title
        case .recent(let track): return track.candidate.title
        }
    }

    private var subtitle: String {
        switch item {
        case .nowPlaying(let track): return track.subtitle
        case .command(let entry): return entry.subtitle
        case .music(let candidate): return candidate.subtitle
        case .recent(let track): return track.candidate.subtitle
        }
    }

    private var badge: String? {
        switch item {
        case .nowPlaying: return nil // rendered together with the waveform
        case .recent: return nil // shows when it was played instead
        case .command(let entry): return entry.badge
        case .music(let candidate):
            guard candidate.source == .library else { return "Catalog" }
            switch candidate.kind {
            case .album: return "Album"
            case .playlist: return "Playlist"
            case .artist: return "Artist"
            default: return "Library"
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if case .nowPlaying(let track) = item {
            HStack(spacing: 6) {
                WaveformView(isAnimating: track.isPlaying, compact: true)
                Text(track.isPlaying ? "Now Playing" : "Paused")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
        } else if case .recent(let track) = item {
            Text(RecentlyPlayed.relativeLabel(for: track.playedAt))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
        } else if let badge {
            Text(badge)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .nowPlaying(let track):
            ArtworkView(
                source: .nowPlaying(
                    persistentID: track.persistentID,
                    artist: track.artist,
                    album: track.album,
                    title: track.title
                )
            )

        case .command(let entry):
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(.quaternary)
                Image(systemName: entry.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .frame(width: 36, height: 36)

        case .music, .recent:
            ArtworkView(source: item.artworkSource)
        }
    }
}
