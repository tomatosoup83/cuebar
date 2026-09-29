import SwiftUI
import AppKit
import CuebarCore

struct ResultRowView: View {
    let item: PaletteItem
    let isSelected: Bool

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
        .background(
            isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var title: String {
        switch item {
        case .nowPlaying(let track): return track.title
        case .command(let entry): return entry.title
        case .music(let candidate): return candidate.title
        }
    }

    private var subtitle: String {
        switch item {
        case .nowPlaying(let track): return track.subtitle
        case .command(let entry): return entry.subtitle
        case .music(let candidate): return candidate.subtitle
        }
    }

    private var badge: String? {
        switch item {
        case .nowPlaying: return nil // rendered together with the waveform
        case .command: return "Command"
        case .music(let candidate):
            guard candidate.source == .library else { return "Catalog" }
            switch candidate.kind {
            case .album: return "Album"
            case .playlist: return "Playlist"
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

        case .music(let candidate):
            ArtworkView(source: artworkSource(for: candidate))
        }
    }

    private func artworkSource(for candidate: MusicCandidate) -> ArtworkSource? {
        switch candidate.source {
        case .library:
            // A playlist's `persistentID` is the playlist itself, not a track,
            // so use its representative track for artwork.
            let trackID = candidate.kind == .playlist
                ? candidate.artworkTrackID
                : (candidate.persistentID ?? candidate.artworkTrackID)
            guard let trackID else { return nil }
            return .library(
                persistentID: trackID,
                artist: candidate.artist,
                album: candidate.album
            )
        case .catalog:
            guard let url = candidate.artworkURL else { return nil }
            return .remote(url)
        }
    }
}
