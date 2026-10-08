import XCTest
@testable import CuebarCore

final class SearchScopeTests: XCTestCase {
    func testEveryScopeIsDescribed() {
        for scope in SearchScope.allCases {
            XCTAssertFalse(scope.keyword.isEmpty)
            XCTAssertFalse(scope.title.isEmpty)
            XCTAssertFalse(scope.symbolName.isEmpty)
        }
    }

    /// A theme scope is not a music ranking.
    func testOnlyMusicScopesRank() {
        XCTAssertEqual(SearchScope.albums.rankPreference, .albums)
        XCTAssertEqual(SearchScope.playlists.rankPreference, .playlists)
        XCTAssertNil(SearchScope.themes.rankPreference)
    }

    func testKeywordsCreateScopes() {
        XCTAssertEqual(SearchScope.scope(forToken: "album"), .albums)
        XCTAssertEqual(SearchScope.scope(forToken: "playlist"), .playlists)
        XCTAssertEqual(SearchScope.scope(forToken: "playlists"), .playlists)
        XCTAssertEqual(SearchScope.scope(forToken: "theme"), .themes)
        XCTAssertEqual(SearchScope.scope(forToken: "Themes"), .themes)
        XCTAssertNil(SearchScope.scope(forToken: "the"))
    }
}

final class ThemeScopeQueryTests: XCTestCase {
    func testThemeWithASpaceBecomesAScope() {
        let query = SearchQuery.parse("theme ")
        XCTAssertEqual(query.scope, .themes)
        XCTAssertEqual(query.term, "")
    }

    func testWhatFollowsTheScopeNarrowsTheOptions() {
        let query = SearchQuery.parse("theme art")
        XCTAssertEqual(query.scope, .themes)
        XCTAssertEqual(query.term, "art")
    }

    func testTrailingThemeWins() {
        let query = SearchQuery.parse("art theme")
        XCTAssertEqual(query.scope, .themes)
        XCTAssertEqual(query.term, "art")
    }

    func testBareThemeStaysALiteralSearch() {
        let query = SearchQuery.parse("theme")
        XCTAssertNil(query.scope)
        XCTAssertEqual(query.term, "theme")
    }

    func testMusicScopesStillBehave() {
        XCTAssertEqual(SearchQuery.parse("album ").scope, .albums)
        XCTAssertEqual(SearchQuery.parse("focus playlist").scope, .playlists)
        XCTAssertEqual(SearchQuery.parse("focus playlist").term, "focus")
        XCTAssertEqual(SearchQuery.parse("focus playlist").preference, .playlists)
        XCTAssertEqual(SearchQuery.parse("focus").preference, .songs)
    }
}

final class ThemeScopeMenuTests: XCTestCase {
    func testShowsBothThemesAndTheOption() {
        let entries = ThemeScopeMenu.entries(currentTheme: .tahoe, followsSelection: false)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries.map(\.badge), ["Theme", "Theme", "Theme", "Option"])
        XCTAssertEqual(entries.map(\.title), [
            "Theme: Tahoe",
            "Theme: Album Art",
            "Theme: Album Art v2",
            "Follow the Highlighted Row"
        ])
    }

    func testMarksTheCurrentTheme() {
        let entries = ThemeScopeMenu.entries(currentTheme: .albumArt, followsSelection: false)
        let current = entries.filter { $0.subtitle == "Current theme" }
        XCTAssertEqual(current.count, 1)
        XCTAssertEqual(current.first?.action, .setTheme(.albumArt))
    }

    func testTheOptionRowTogglesBothWays() {
        let off = ThemeScopeMenu.entries(currentTheme: .tahoe, followsSelection: false)
            .first { $0.badge == "Option" }
        XCTAssertEqual(off?.action, .setFollowsSelection(true))

        let on = ThemeScopeMenu.entries(currentTheme: .tahoe, followsSelection: true)
            .first { $0.badge == "Option" }
        XCTAssertEqual(on?.action, .setFollowsSelection(false))
    }

    func testGlobalColoursOptionOnlyAppearsForAlbumArtV2() {
        // Not offered for the other themes.
        XCTAssertNil(
            ThemeScopeMenu.entries(currentTheme: .albumArt, followsSelection: false)
                .first { $0.id == "theme.globalColours" }
        )

        let off = ThemeScopeMenu.entries(
            currentTheme: .albumArtV2,
            followsSelection: false,
            globalColours: false
        )
        XCTAssertEqual(off.count, 5, "3 themes + follow + global")
        let globalOff = off.first { $0.id == "theme.globalColours" }
        XCTAssertEqual(globalOff?.action, .setGlobalColours(true))
        XCTAssertEqual(globalOff?.badge, "Option")

        let on = ThemeScopeMenu.entries(
            currentTheme: .albumArtV2,
            followsSelection: false,
            globalColours: true
        ).first { $0.id == "theme.globalColours" }
        XCTAssertEqual(on?.action, .setGlobalColours(false))
    }

    func testFilterNarrowsTheOptions() {
        let art = ThemeScopeMenu.entries(
            currentTheme: .tahoe, followsSelection: false, filter: "art"
        )
        XCTAssertEqual(art.map(\.title), ["Theme: Album Art", "Theme: Album Art v2"])

        let v2 = ThemeScopeMenu.entries(
            currentTheme: .tahoe, followsSelection: false, filter: "v2"
        )
        XCTAssertEqual(v2.map(\.title), ["Theme: Album Art v2"])

        let follow = ThemeScopeMenu.entries(
            currentTheme: .tahoe, followsSelection: false, filter: "follow"
        )
        XCTAssertEqual(follow.map(\.title), ["Follow the Highlighted Row"])

        let nothing = ThemeScopeMenu.entries(
            currentTheme: .tahoe, followsSelection: false, filter: "zzz"
        )
        XCTAssertTrue(nothing.isEmpty)
    }
}

final class SettingsRowTests: XCTestCase {
    func testAlbumArtShowsTheFollowOption() {
        XCTAssertEqual(SettingsRow.visibleRows(theme: .albumArt), [
            .hotKey, .theme, .followSelection, .update, .whatsNew, .onboarding
        ])
    }

    func testTahoeHidesTheFollowOption() {
        XCTAssertEqual(SettingsRow.visibleRows(theme: .tahoe), [
            .hotKey, .theme, .update, .whatsNew, .onboarding
        ])
    }

    func testAlbumArtV2ShowsTheFollowAndGlobalOptions() {
        XCTAssertEqual(SettingsRow.visibleRows(theme: .albumArtV2), [
            .hotKey, .theme, .followSelection, .globalColours, .update, .whatsNew, .onboarding
        ])
    }

    /// The global-colours option only means something for Album Art v2.
    func testAlbumArtHidesTheGlobalOption() {
        XCTAssertFalse(SettingsRow.visibleRows(theme: .albumArt).contains(.globalColours))
    }

    func testEveryRowIsReachable() {
        let rows = Set(
            SettingsRow.visibleRows(theme: .albumArt)
                + SettingsRow.visibleRows(theme: .albumArtV2)
        )
        for row in SettingsRow.allCases {
            XCTAssertTrue(rows.contains(row), "\(row) is never shown")
        }
    }
}

final class WhatsNewTests: XCTestCase {
    func testTheReleaseAnnouncesExactlyThreeHighlights() {
        guard let note = WhatsNew.notes.first else {
            return XCTFail("expected a note")
        }
        XCTAssertEqual(note.entries.count, 3, "the screen shows the three most important changes")
        for entry in note.entries {
            XCTAssertFalse(entry.symbolName.isEmpty)
            XCTAssertFalse(entry.title.isEmpty)
            XCTAssertFalse(entry.detail.isEmpty)
        }
    }

    func testLatestNoteIsTheVersionBeingReleased() {
        XCTAssertEqual(WhatsNew.notes.first?.version, "0.8.0")
    }

    func testUnknownVersionHasNoHighlights() {
        XCTAssertTrue(WhatsNew.highlights(for: "0.5.0").isEmpty)
        XCTAssertTrue(WhatsNew.highlights(for: "9.9.9").isEmpty)
    }
}

final class WhatsNewStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "cuebar-whatsnew-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Upgrading to the first release that has this screen leaves no stored
    /// version, and must still announce.
    func testAnnouncesWhenNothingWasSeenBefore() {
        XCTAssertTrue(WhatsNewStore(defaults: makeDefaults()).shouldShow(for: "0.6.0"))
    }

    func testAnnouncesOncePerVersion() {
        let store = WhatsNewStore(defaults: makeDefaults())
        store.lastSeenVersion = "0.6.0"
        XCTAssertFalse(store.shouldShow(for: "0.6.0"))
        XCTAssertTrue(store.shouldShow(for: "0.7.0"))
    }

    func testRoundTrips() {
        let store = WhatsNewStore(defaults: makeDefaults())
        XCTAssertNil(store.lastSeenVersion)
        store.lastSeenVersion = "0.6.0"
        XCTAssertEqual(store.lastSeenVersion, "0.6.0")
    }
}
