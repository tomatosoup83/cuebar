import Foundation

/// One highlight on the What's New screen.
public struct WhatsNewEntry: Equatable, Sendable {
    public let symbolName: String
    public let title: String
    public let detail: String

    public init(symbolName: String, title: String, detail: String) {
        self.symbolName = symbolName
        self.title = title
        self.detail = detail
    }
}

/// Curated release highlights, newest first.
///
/// Deliberately in code rather than fetched: it works offline, is deterministic and
/// is unit-tested, and the release itself is one click away from the screen.
public enum WhatsNew {
    public struct Note: Equatable, Sendable {
        public let version: String
        public let entries: [WhatsNewEntry]

        public init(version: String, entries: [WhatsNewEntry]) {
            self.version = version
            self.entries = entries
        }
    }

    public static let notes: [Note] = [
        Note(
            version: "0.7.1",
            entries: [
                WhatsNewEntry(
                    symbolName: "paintpalette",
                    title: "A New Default Look",
                    detail: "Album Art is now the default, following the row you "
                        + "highlight. Your theme was switched once — undo with "
                        + "“theme ”."
                ),
                WhatsNewEntry(
                    symbolName: "clock.arrow.circlepath",
                    title: "Home Screen",
                    detail: "The now-playing track and a Recently Played shelf meet "
                        + "you when Cuebar opens."
                ),
                WhatsNewEntry(
                    symbolName: "command",
                    title: "Quick Actions",
                    detail: "Press ⌘K on any row to play, Like, add to a playlist, or "
                        + "open it in Music."
                )
            ]
        ),
        Note(
            version: "0.6.0",
            entries: [
                WhatsNewEntry(
                    symbolName: "paintpalette",
                    title: "Themes",
                    detail: "Tahoe keeps Apple's Liquid Glass. Album Art tints the whole "
                        + "panel with the cover you're playing."
                ),
                WhatsNewEntry(
                    symbolName: "wand.and.stars",
                    title: "Follow the Highlighted Row",
                    detail: "Turn it on and the panel's colour follows whatever you "
                        + "highlight, fading from album to album as you move."
                ),
                WhatsNewEntry(
                    symbolName: "magnifyingglass",
                    title: "Switch themes by typing",
                    detail: "Type “theme ” for a Theme filter, and change themes — or the "
                        + "follow option — without leaving the keyboard."
                )
            ]
        )
    ]

    /// The highlights for a version, or none when there is nothing to announce.
    public static func highlights(for version: String) -> [WhatsNewEntry] {
        notes.first { $0.version == version }?.entries ?? []
    }
}
