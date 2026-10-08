import SwiftUI
import CuebarCore

/// A row in the extended album view: track number, title, duration.
///
/// Deliberately unlike `ResultRowView`: every row here is the *same* album, so
/// repeating its cover would be noise, and "Library" would be meaningless. The
/// leading number is what makes the running order legible, and the trailing
/// duration is what you actually want to know.
struct AlbumTrackRowView: View {
    let track: MusicCandidate
    /// `1`, or `1-3` on a multi-disc album.
    let number: String
    let isSelected: Bool
    var accent: AlbumPalette?
    let onSelect: () -> Void
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)

            Text(track.title)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let duration = track.durationSeconds {
                Text(TimeFormat.mmss(duration))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RowSelectionBackground(isSelected: isSelected, accent: accent)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onPlay)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number). \(track.title)")
    }
}
