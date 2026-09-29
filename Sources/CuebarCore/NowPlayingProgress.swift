import Foundation

/// Computes the position shown on a progress bar, interpolated between the
/// (relatively infrequent) now-playing polls so the bar advances smoothly.
public enum NowPlayingProgress {
    /// The displayed position: advances by the time since the last poll while
    /// playing, and clamps to `[0, duration]`.
    public static func position(
        reported: Double,
        duration: Double?,
        isPlaying: Bool,
        lastPoll: Date?,
        now: Date
    ) -> Double {
        var value = reported
        if isPlaying, let lastPoll {
            value += max(0, now.timeIntervalSince(lastPoll))
        }
        value = max(value, 0)
        if let duration, duration > 0 {
            value = min(value, duration)
        }
        return value
    }

    /// Fraction 0...1 for the bar, or nil when the duration is unknown.
    public static func fraction(position: Double, duration: Double?) -> Double? {
        guard let duration, duration > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }
}
