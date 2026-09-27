import Foundation

/// Normalizes human text into a canonical, comparable form.
///
/// Used by the ranking engine so that "Take On Me", "take on me" and
/// "TAKE ON ME!" all compare equal.
public enum TextNormalizer {
    /// Lowercases, strips diacritics/punctuation and collapses whitespace.
    public static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )

        var scalars = String.UnicodeScalarView()
        var lastWasSpace = true // trims leading space
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                scalars.append(" ")
                lastWasSpace = true
            }
        }
        return String(scalars).trimmingCharacters(in: .whitespaces)
    }

    /// Normalized whitespace-separated tokens.
    public static func tokens(_ value: String) -> [String] {
        normalize(value)
            .split(separator: " ")
            .map(String.init)
    }
}
