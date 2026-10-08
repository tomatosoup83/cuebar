import Foundation

/// A command sent to Cuebar from outside the palette — currently through the
/// `cuebar://` URL scheme, so a launcher such as Raycast can drive Cuebar.
public enum CuebarRequest: Equatable, Sendable {
    /// A palette-style input string: `pause`, `shuffle off`, `take on me`,
    /// `album swag ii`, `rebuild`.
    case run(input: String)
    /// Re-scan the Music library, for the input-free `cuebar://rebuild` form.
    case rebuildLibraryIndex

    /// The headless action this request performs.
    public func action() throws -> HeadlessAction {
        switch self {
        case .run(let input):
            return try HeadlessCommandParser.parse(input)
        case .rebuildLibraryIndex:
            return .rebuildLibraryIndex
        }
    }
}

/// Parses `cuebar://` URLs into a `CuebarRequest`.
///
/// Three equivalent forms, in decreasing explicitness:
///
/// ```
/// cuebar://run?command=next            // the documented form
/// cuebar://run?command=album%20swag%20ii
/// cuebar://rebuild                     // re-index the library
/// cuebar://pause                       // the host is the input
/// cuebar://album/SWAG%20II             // …and the path joins it
/// ```
public enum CuebarURL {
    public static let scheme = "cuebar"

    /// The documented parameter, plus the friendly aliases.
    static let inputKeys = ["command", "input", "q"]
    /// The documented host for a command-carrying URL.
    static let runHosts: Set<String> = ["run"]
    /// Hosts that mean "re-index the library" when no input is given.
    static let rebuildHosts: Set<String> = ["rebuild", "reindex", "rescan", "refresh"]

    public static func parse(_ string: String) -> CuebarRequest? {
        guard let url = URL(string: string) else { return nil }
        return parse(url)
    }

    public static func parse(_ url: URL) -> CuebarRequest? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        // An input parameter wins whatever the host is, so a mistyped host
        // can't silently turn a command into a song search.
        if let input = input(in: url) {
            return .run(input: input)
        }

        let host = url.host ?? ""
        let lowered = host.lowercased()
        if rebuildHosts.contains(lowered) {
            return .rebuildLibraryIndex
        }
        // `cuebar://run` with no usable command is malformed — not a search for
        // the word "run".
        if runHosts.contains(lowered) {
            return nil
        }

        // `cuebar://pause`, `cuebar://album/SWAG%20II`: the host is the input.
        // Not lowercased — the host can be a song name.
        let pieces = [host] + url.pathComponents.filter { $0 != "/" }
        let input = pieces
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return input.isEmpty ? nil : .run(input: input)
    }

    /// The `command` parameter (or an alias), trimmed.
    private static func input(in url: URL) -> String? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }

        for key in inputKeys {
            guard let value = items.first(where: { $0.name.lowercased() == key })?.value
            else { continue }
            let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !input.isEmpty { return input }
        }
        return nil
    }
}
