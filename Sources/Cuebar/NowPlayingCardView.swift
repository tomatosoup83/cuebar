import SwiftUI
import CuebarCore

/// The larger "now playing" card shown at the top of an empty palette.
struct NowPlayingCardView: View {
    let track: NowPlayingTrack
    let isSelected: Bool
    let lastPollDate: Date?
    /// The card's own album palette, when the Album Art theme is active.
    var accent: AlbumPalette?
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
        .background { selectionBackground }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onSelect)
    }

    /// The same translucent treatment as an ordinary row, so the card still reads
    /// as glass when it is the selected item.
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

    private var header: some View {
        HStack(spacing: 12) {
            ArtworkView(
                source: artworkSource,
                size: PaletteMetrics.nowPlayingArtwork,
                cornerRadius: 9
            )
            .background { ArtworkGlow(source: artworkSource, isPlaying: track.isPlaying) }

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

    private var artworkSource: ArtworkSource {
        .nowPlaying(
            persistentID: track.persistentID,
            artist: track.artist,
            album: track.album,
            title: track.title
        )
    }

    private var subtitle: String {
        if !track.subtitle.isEmpty { return track.subtitle }
        return track.isPlaying ? "Playing" : "Paused"
    }

    private static func timeString(_ seconds: Double) -> String {
        TimeFormat.mmss(seconds)
    }
}

/// A soft, blurred copy of the cover behind the artwork, so the art seems to
/// light the card. It breathes gently while playing and dims when paused.
private struct ArtworkGlow: View {
    let source: ArtworkSource
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var breathes: Bool { isPlaying && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !breathes)) { context in
            // A slow ~4 s swell; held at its midpoint when not breathing.
            let pulse = breathes
                ? (sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / 4) + 1) / 2
                : 0.5
            ArtworkView(
                source: source,
                size: PaletteMetrics.nowPlayingArtwork,
                cornerRadius: 9
            )
            .saturation(1.6)
            .scaleEffect(1.22 + 0.10 * pulse)
            .blur(radius: 16)
            .opacity(isPlaying ? 0.55 + 0.35 * pulse : 0.4)
            .offset(y: 4)
            // Added as light rather than painted on, so the glow still reads when
            // the cover is the same colour as the card behind it.
            .blendMode(.plusLighter)
        }
        .animation(.easeInOut(duration: 0.6), value: isPlaying)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
