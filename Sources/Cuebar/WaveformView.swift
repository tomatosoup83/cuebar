import SwiftUI

/// Spotify-style "now playing" equalizer.
///
/// Bar heights follow a phase-shifted sine of the current time, producing a
/// travelling wave. When not animating (paused/stopped, or Reduce Motion) it
/// renders a fixed pattern so the row still reads as an equalizer.
struct WaveformView: View {
    let isAnimating: Bool

    private let barCount: Int
    private let barWidth: CGFloat
    private let spacing: CGFloat
    private let minHeight: CGFloat
    private let maxHeight: CGFloat

    /// Height fractions for the static (paused) pattern.
    private static let staticFractions: [CGFloat] = [0.45, 0.9, 0.3, 0.7]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isAnimating: Bool, compact: Bool = false) {
        self.isAnimating = isAnimating
        self.barCount = compact ? 3 : 4
        self.barWidth = compact ? 2.5 : 3
        self.spacing = compact ? 2.5 : 3
        self.minHeight = compact ? 4 : 5
        self.maxHeight = compact ? 12 : 17
    }

    var body: some View {
        Group {
            if isAnimating, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    bars { index in
                        let time = context.date.timeIntervalSinceReferenceDate
                        let wave = (sin(time * 4.2 + Double(index) * 1.1) + 1) / 2
                        return minHeight + wave * (maxHeight - minHeight)
                    }
                }
            } else {
                bars { index in
                    let fraction = Self.staticFractions[index % Self.staticFractions.count]
                    return minHeight + fraction * (maxHeight - minHeight)
                }
            }
        }
        .frame(width: totalWidth, height: maxHeight)
    }

    private var totalWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
    }

    private func bars(height: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(Color(nsColor: .secondaryLabelColor))
                    .frame(width: barWidth, height: height(index))
            }
        }
    }
}
