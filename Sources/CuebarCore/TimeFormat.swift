import Foundation

/// Formatting helpers for durations.
public enum TimeFormat {
    /// `3:57` — minutes, then zero-padded seconds.
    ///
    /// Non-finite or negative input reads as `0:00`; callers that want to show
    /// *nothing* for a missing duration should `map` over the optional first.
    public static func mmss(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
