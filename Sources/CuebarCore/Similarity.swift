import Foundation

/// Damerau–Levenshtein helpers used for typo-tolerant fuzzy matching.
public enum Similarity {
    /// Returns a 0...1 similarity ratio between two normalized strings.
    public static func ratio(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let maxLength = max(a.count, b.count)
        guard maxLength > 0 else { return 1 }
        let distance = damerauLevenshtein(Array(a), Array(b))
        return 1.0 - Double(distance) / Double(maxLength)
    }

    /// Damerau–Levenshtein distance with an early-out once the distance
    /// exceeds `maximum`.
    public static func damerauLevenshtein(
        _ a: [Character],
        _ b: [Character],
        maximum: Int = Int.max
    ) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previousPrevious = Array(repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)

        for i in 1...a.count {
            var current = Array(repeating: 0, count: b.count + 1)
            current[0] = i
            var rowMinimum = current[0]

            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(
                    previous[j] + 1,        // deletion
                    current[j - 1] + 1,     // insertion
                    previous[j - 1] + cost  // substitution
                )
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, previousPrevious[j - 2] + 1) // transposition
                }
                current[j] = value
                rowMinimum = min(rowMinimum, value)
            }

            if rowMinimum > maximum { return rowMinimum }
            previousPrevious = previous
            previous = current
        }

        return previous[b.count]
    }
}
