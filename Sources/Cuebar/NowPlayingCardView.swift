import SwiftUI
import CuebarCore

/// The larger "now playing" card shown at the top of an empty palette.
struct NowPlayingCardView: View {
    let track: NowPlayingTrack
    let isSelected: Bool
    let lastPollDate: Date?
    let onSelect: () -> Void
    let onTogglePlay: () -> Void
    let onToggleShuffle: () -> Void
    let onToggleRepeat: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            header
            progress
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onSelect)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ArtworkView(
                source: .nowPlaying(
                    persistentID: track.persistentID,
                    artist: track.artist,
                    album: track.album,
                    title: track.title
                ),
                size: PaletteMetrics.nowPlayingArtwork,
                cornerRadius: 9
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    WaveformView(isAnimating: track.isPlaying, compact: true)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                controlButton(
                    track.isPlaying ? "pause.fill" : "play.fill",
                    active: false,
                    help: track.isPlaying ? "Pause" : "Play",
                    action: onTogglePlay
                )
                controlButton(
                    "shuffle",
                    active: track.shuffleEnabled,
                    help: "Shuffle",
                    action: onToggleShuffle
                )
                controlButton(
                    track.repeatMode == .one ? "repeat.1" : "repeat",
                    active: track.repeatMode != .off,
                    help: "Repeat",
                    action: onToggleRepeat
                )
            }
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = NowPlayingProgress.position(
                reported: track.position ?? 0,
                duration: track.duration,
                isPlaying: track.isPlaying,
                lastPoll: lastPollDate,
                now: context.date
            )
            let fraction = NowPlayingProgress.fraction(position: position, duration: track.duration) ?? 0

            HStack(spacing: 8) {
                Text(Self.timeString(position))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * fraction)
                    }
                }
                .frame(height: PaletteMetrics.nowPlayingProgressHeight)

                Text(Self.timeString(track.duration ?? 0))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
            }
        }
    }

    private func controlButton(
        _ symbol: String,
        active: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    active
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color(nsColor: .labelColor))
                )
                .frame(width: 32, height: 28)
                .background(
                    active
                        ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                        : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var subtitle: String {
        if !track.subtitle.isEmpty { return track.subtitle }
        return track.isPlaying ? "Playing" : "Paused"
    }

    private static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
