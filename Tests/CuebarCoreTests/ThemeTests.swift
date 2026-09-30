import XCTest
@testable import CuebarCore

final class ThemeColorTests: XCTestCase {
    func testClampsComponents() {
        let color = ThemeColor(red: 1.5, green: -0.2, blue: 0.5)
        XCTAssertEqual(color.red, 1)
        XCTAssertEqual(color.green, 0)
        XCTAssertEqual(color.blue, 0.5)
    }

    func testChromaAndBrightness() {
        let grey = ThemeColor(red: 0.5, green: 0.5, blue: 0.5)
        XCTAssertEqual(grey.chroma, 0, accuracy: 0.0001)

        let red = ThemeColor(red: 1, green: 0, blue: 0)
        XCTAssertEqual(red.brightness, 1, accuracy: 0.0001)
        XCTAssertEqual(red.chroma, 1, accuracy: 0.0001)
    }

    func testZeroSaturationGivesGreyAndPreservesLuma() {
        let color = ThemeColor(red: 1, green: 0, blue: 0)
        let grey = color.withSaturation(0)
        XCTAssertEqual(grey.red, grey.green, accuracy: 0.0001)
        XCTAssertEqual(grey.green, grey.blue, accuracy: 0.0001)
        XCTAssertEqual(grey.luma, color.luma, accuracy: 0.0001)
    }

    func testFullSaturationIsUnchanged() {
        let color = ThemeColor(red: 0.8, green: 0.1, blue: 0.3)
        XCTAssertEqual(color.withSaturation(1), color)
    }

    func testBlend() {
        let mixed = ThemeColor(red: 0, green: 0, blue: 0)
            .blended(with: ThemeColor(red: 1, green: 1, blue: 1), amount: 0.5)
        XCTAssertEqual(mixed.red, 0.5, accuracy: 0.0001)
        XCTAssertEqual(mixed.blue, 0.5, accuracy: 0.0001)
    }

    func testScaledToLumaPreservesHue() {
        let colour = ThemeColor(red: 0.9, green: 0.35, blue: 0.5)
        let darker = colour.scaled(toLuma: 0.44)
        XCTAssertEqual(darker.luma, 0.44, accuracy: 0.001)
        // Scaling is uniform, so the channel order (i.e. the hue) is preserved.
        XCTAssertGreaterThan(darker.red, darker.blue)
        XCTAssertGreaterThan(darker.blue, darker.green)
    }

}

final class ThemeStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "cuebar-theme-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultsToTahoe() {
        XCTAssertEqual(ThemeStore(defaults: makeDefaults()).theme, .tahoe)
    }

    func testRoundTrip() {
        let store = ThemeStore(defaults: makeDefaults())
        store.theme = .albumArt
        XCTAssertEqual(store.theme, .albumArt)
    }

    func testUnknownValueFallsBack() {
        let defaults = makeDefaults()
        defaults.set("nonsense", forKey: "themeID")
        XCTAssertEqual(ThemeStore(defaults: defaults).theme, .tahoe)
    }

    func testFollowsSelectionDefaultsOffAndRoundTrips() {
        let store = ThemeStore(defaults: makeDefaults())
        XCTAssertFalse(store.ambientFollowsSelection)
        store.ambientFollowsSelection = true
        XCTAssertTrue(store.ambientFollowsSelection)
    }
}

final class ThemeIDTests: XCTestCase {
    func testEveryThemeIsDescribed() {
        for theme in ThemeID.allCases {
            XCTAssertFalse(theme.title.isEmpty)
            XCTAssertFalse(theme.blurb.isEmpty)
            XCTAssertFalse(theme.symbolName.isEmpty)
            XCTAssertFalse(theme.keywords.isEmpty)
        }
    }

    func testThemeKeywordSurfacesBothThemes() {
        let entries = ThemeID.allCases.map { theme in
            CommandEntry(
                id: "theme.\(theme.rawValue)",
                title: "Theme: \(theme.title)",
                subtitle: theme.blurb,
                symbolName: theme.symbolName,
                action: .setTheme(theme),
                keywords: theme.keywords
            )
        }
        let matches = entries.filter {
            CommandCatalog.score($0, normalizedInput: "theme") != nil
        }
        XCTAssertEqual(matches.count, ThemeID.allCases.count)
    }
}

final class PaletteExtractorTests: XCTestCase {
    private func solid(_ red: Double, _ green: Double, _ blue: Double, side: Int = 9) -> PixelGrid {
        let value = [UInt8(red * 255), UInt8(green * 255), UInt8(blue * 255)]
        var rgb: [UInt8] = []
        for _ in 0 ..< (side * side) { rgb.append(contentsOf: value) }
        return PixelGrid(width: side, height: side, rgb: rgb)
    }

    func testColourlessArtworkIsNotUsable() {
        XCTAssertEqual(PaletteExtractor.palette(from: solid(0, 0, 0))?.isUsable, false)
        XCTAssertEqual(PaletteExtractor.palette(from: solid(1, 1, 1))?.isUsable, false)
        XCTAssertEqual(PaletteExtractor.palette(from: solid(0.5, 0.5, 0.5))?.isUsable, false)
    }

    func testFaintlyColouredArtworkFallsBack() {
        // A washed-out pale blue, the kind of near-monochrome photo that used to
        // produce a muddy tint. It should fall back to plain glass instead.
        XCTAssertEqual(PaletteExtractor.palette(from: solid(0.64, 0.67, 0.71))?.isUsable, false)
    }

    func testColourArtworkStaysColourfulAndLight() {
        guard let palette = PaletteExtractor.palette(from: solid(1, 0, 0)) else {
            return XCTFail("expected a palette")
        }
        let tuning = PaletteExtractor.Tuning.default
        XCTAssertTrue(palette.isUsable)
        for stop in [palette.top, palette.bottom] {
            XCTAssertGreaterThanOrEqual(stop.luma, tuning.minimumLuma - 0.02)
            XCTAssertGreaterThanOrEqual(stop.chroma, tuning.washChromaMinimum - 0.02)
            XCTAssertLessThanOrEqual(stop.chroma, tuning.washChromaMaximum + 0.02)
        }
        XCTAssertGreaterThanOrEqual(palette.accent.chroma, tuning.accentChromaMinimum - 0.02)
    }

    /// A dark but *colourful* cover keeps the light treatment it always had — only
    /// colourless dark covers get the darker panel.
    func testDarkButColourfulCoverKeepsTheLightTreatment() {
        guard let palette = PaletteExtractor.palette(from: solid(0.25, 0.05, 0.10)) else {
            return XCTFail("expected a palette")
        }
        XCTAssertTrue(palette.isUsable)
        XCTAssertGreaterThanOrEqual(
            palette.top.luma,
            PaletteExtractor.Tuning.default.minimumLuma - 0.02
        )
        // Hue still points at the cover (red-dominant).
        XCTAssertGreaterThan(palette.top.red, palette.top.green)
        XCTAssertGreaterThan(palette.top.red, palette.top.blue)
    }

    /// A black sleeve carrying large white type: the *mean* is mid grey (which is
    /// how it used to render as a near-white panel), but the lower quantiles are
    /// black, so it must produce a distinctly darker panel.
    func testBlackSleeveWithWhiteTypeGivesADarkerPanel() {
        let side = 10
        var rgb: [UInt8] = []
        for row in 0 ..< side {
            // 70% black, 30% white type.
            let value: [UInt8] = row < 7 ? [12, 12, 12] : [245, 245, 245]
            for _ in 0 ..< side { rgb.append(contentsOf: value) }
        }
        let grid = PixelGrid(width: side, height: side, rgb: rgb)
        let tuning = PaletteExtractor.Tuning.default

        XCTAssertLessThan(
            PaletteExtractor.lowerQuantileBrightness(in: grid, quantile: 0.35),
            0.45,
            "the lower quantile must see the black, not the averaged grey"
        )
        guard let palette = PaletteExtractor.palette(from: grid) else {
            return XCTFail("expected a palette")
        }
        XCTAssertFalse(palette.isUsable, "a colourless cover is not usable for a row tint")
        // Darker than a light cover's panel, and darker than the old near-white.
        XCTAssertLessThan(palette.top.luma, tuning.darkPanelLuma + 0.05)
        XCTAssertLessThan(palette.top.luma, tuning.minimumLuma - 0.2)
    }

    func testNearBlackArtworkGivesADarkPanelRatherThanALightGrey() {
        guard let palette = PaletteExtractor.palette(from: solid(0.02, 0.02, 0.02)) else {
            return XCTFail("expected a palette")
        }
        // Almost no colour, so it is not "usable" for a row tint…
        XCTAssertFalse(palette.isUsable)
        // …but the panel is still darker than a light cover's, not near-white.
        XCTAssertLessThan(palette.top.luma, 0.55)
        XCTAssertLessThan(palette.top.luma, PaletteExtractor.Tuning.default.minimumLuma - 0.1)
    }

    func testVividRedCoverKeepsTheLightTreatment() {
        // Pure red has a *low* Rec.601 luma but is perceptually bright, so panel
        // darkness must not be decided by luma.
        guard let palette = PaletteExtractor.palette(from: solid(1, 0, 0)) else {
            return XCTFail("expected a palette")
        }
        XCTAssertGreaterThanOrEqual(
            palette.top.luma,
            PaletteExtractor.Tuning.default.minimumLuma - 0.02
        )
    }

    func testTwoToneKeepsTopAndBottomDistinct() {
        let side = 9
        var rgb: [UInt8] = []
        for row in 0 ..< side {
            let value: [UInt8] = row < side / 3 ? [220, 40, 40] : [40, 60, 220]
            for _ in 0 ..< side { rgb.append(contentsOf: value) }
        }

        guard let palette = PaletteExtractor.palette(
            from: PixelGrid(width: side, height: side, rgb: rgb)
        ) else {
            return XCTFail("expected a palette")
        }
        // The top third is red, the bottom is blue — the gradient must follow,
        // measured relative to each stop's own blue channel.
        XCTAssertGreaterThan(
            palette.top.red - palette.top.blue,
            palette.bottom.red - palette.bottom.blue
        )
    }

    func testChromaBandHelpers() {
        // A faintly tinted colour is pushed up to the floor, keeping its luma.
        let faint = ThemeColor(red: 0.72, green: 0.70, blue: 0.70)
        let boosted = faint.withChroma(atLeast: 0.2)
        XCTAssertEqual(boosted.chroma, 0.2, accuracy: 0.001)
        XCTAssertEqual(boosted.luma, faint.luma, accuracy: 0.001)

        // A perfectly neutral colour has no hue to push toward, so it stays put.
        let neutral = ThemeColor(red: 0.7, green: 0.7, blue: 0.7)
        XCTAssertEqual(neutral.withChroma(atLeast: 0.2), neutral)

        let vivid = ThemeColor(red: 1, green: 0, blue: 0)
        XCTAssertEqual(vivid.withChroma(atMost: 0.3).chroma, 0.3, accuracy: 0.001)
        XCTAssertEqual(vivid.withChroma(atMost: 0.3).luma, vivid.luma, accuracy: 0.001)

        // Already inside the band: untouched.
        let mid = ThemeColor(red: 0.7, green: 0.6, blue: 0.6)
        XCTAssertEqual(mid.withChroma(atLeast: 0.05), mid)
        XCTAssertEqual(mid.withChroma(atMost: 0.5), mid)
    }

    func testRaisedToLumaNeverDarkens() {
        let light = ThemeColor(red: 0.9, green: 0.9, blue: 0.9)
        XCTAssertEqual(light.raised(toLuma: 0.48), light)

        let dark = ThemeColor(red: 0.1, green: 0.1, blue: 0.1)
        XCTAssertGreaterThanOrEqual(dark.raised(toLuma: 0.48).luma, 0.4799)
    }

    /// The user-facing ask: the selected row should be *more* colourful than the
    /// wash behind it, and reflect the cover.
    func testSelectionTintIsMoreColourfulThanTheWash() {
        guard let palette = PaletteExtractor.palette(from: solid(0.9, 0.35, 0.5)) else {
            return XCTFail("expected a palette")
        }
        let tuning = PaletteExtractor.Tuning.default
        let tint = palette.selection

        // By construction the selected row's colour is always more colourful than
        // the wash: the wash is *capped* at `washChromaMaximum` and the row is
        // *floored* above it, so this holds for every cover.
        XCTAssertGreaterThan(tuning.selectionChromaMinimum, tuning.washChromaMaximum)
        XCTAssertGreaterThan(tint.chroma, palette.top.chroma)
        XCTAssertGreaterThanOrEqual(tint.chroma, tuning.selectionChromaMinimum - 0.05)

        // Darker than the light wash, so the row reads as selected.
        XCTAssertLessThan(tint.luma, palette.top.luma - 0.1)

        // Hue still points at the cover's colour (red-dominant here).
        XCTAssertGreaterThan(tint.red, tint.green)
        XCTAssertGreaterThan(tint.red, tint.blue)
    }

    func testDeterministic() {
        let grid = solid(0.8, 0.2, 0.4)
        XCTAssertEqual(
            PaletteExtractor.palette(from: grid),
            PaletteExtractor.palette(from: grid)
        )
    }

    func testEmptyGridReturnsNil() {
        XCTAssertNil(PaletteExtractor.palette(from: PixelGrid(width: 0, height: 0, rgb: [])))
    }
}

final class PaletteItemTintPolicyTests: XCTestCase {
    private let track = NowPlayingTrack(
        state: .playing,
        title: "Take On Me",
        artist: "a-ha",
        album: "Hunting High and Low",
        persistentID: "PID"
    )

    private func commandItem(id: String = "settings") -> PaletteItem {
        .command(
            CommandEntry(
                id: id,
                title: "Settings",
                subtitle: "Change Cuebar's launch hotkey",
                symbolName: "gearshape",
                action: .openSettings,
                keywords: ["settings"]
            )
        )
    }

    private func musicCandidate(
        id: String,
        kind: MusicKind = .song,
        artworkTrackID: String? = nil
    ) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: kind,
            source: .library,
            title: "Title \(id)",
            artist: "Artist",
            album: "Album",
            persistentID: id,
            artworkTrackID: artworkTrackID
        )
    }

    private func musicItem(
        id: String,
        kind: MusicKind = .song,
        artworkTrackID: String? = nil
    ) -> PaletteItem {
        .music(musicCandidate(id: id, kind: kind, artworkTrackID: artworkTrackID))
    }

    func testOnlyTheNowPlayingRowCarriesTheTintByDefault() {
        let follows = false
        XCTAssertTrue(RowTintPolicy.allowsTint(for: .nowPlaying(track), followsSelection: follows))
        XCTAssertFalse(RowTintPolicy.allowsTint(for: commandItem(), followsSelection: follows))
        XCTAssertFalse(RowTintPolicy.allowsTint(for: musicItem(id: "s1"), followsSelection: follows))
        XCTAssertFalse(RowTintPolicy.allowsTint(
            for: musicItem(id: "al1", kind: .album, artworkTrackID: "t1"),
            followsSelection: follows
        ))
        XCTAssertFalse(RowTintPolicy.allowsTint(
            for: musicItem(id: "pl1", kind: .playlist, artworkTrackID: "t1"),
            followsSelection: follows
        ))
    }

    /// With the option on, the highlighted row is tinted too, so it matches the
    /// ambient background that is now following it.
    func testAnyRowMayCarryTheTintWhenFollowingTheSelection() {
        let follows = true
        XCTAssertTrue(RowTintPolicy.allowsTint(for: .nowPlaying(track), followsSelection: follows))
        XCTAssertTrue(RowTintPolicy.allowsTint(for: commandItem(), followsSelection: follows))
        XCTAssertTrue(RowTintPolicy.allowsTint(for: musicItem(id: "s1"), followsSelection: follows))
        XCTAssertTrue(RowTintPolicy.allowsTint(
            for: musicItem(id: "al1", kind: .album, artworkTrackID: "t1"),
            followsSelection: follows
        ))
        // Commands are allowed, but still resolve to no artwork, so they end up
        // untinted in practice.
        XCTAssertNil(commandItem().artworkSource)
    }

    /// On the default screen (empty box) the *only* tinted row is the one the
    /// palette selects by default, so the album colour shows up straight away.
    func testDefaultScreenPutsTheTintedRowFirst() {
        let items = PaletteListComposer.compose(
            query: "",
            nowPlaying: track,
            commands: CommandCatalog.matches(for: ""),
            music: []
        )

        let tinted = items.enumerated().filter {
            RowTintPolicy.allowsTint(for: $0.element, followsSelection: false)
        }
        XCTAssertEqual(tinted.count, 1, "exactly one row should be tinted")
        XCTAssertEqual(tinted.first?.offset, 0, "and it must be the default selection")
        XCTAssertFalse(items.isEmpty, "the default screen still lists commands")
    }

    /// As soon as the user types, no row is tinted by default: search results stay
    /// neutral. (With the option on, the highlighted result would be tinted.)
    func testSearchResultsCarryNoTintByDefault() {
        let items = PaletteListComposer.compose(
            query: "igor",
            nowPlaying: track,
            commands: CommandCatalog.matches(for: "igor"),
            music: [musicCandidate(id: "s1"), musicCandidate(id: "s2")]
        )

        XCTAssertFalse(items.isEmpty)
        XCTAssertFalse(items.contains { RowTintPolicy.allowsTint(for: $0, followsSelection: false) })
        // …but they may when the option is on.
        XCTAssertTrue(items.contains { RowTintPolicy.allowsTint(for: $0, followsSelection: true) })
    }

    /// Browse mode deliberately omits the now-playing row, so nothing is tinted.
    func testBrowseModeHasNoTintedRow() {
        let items = PaletteListComposer.compose(
            query: "album ",
            nowPlaying: nil,
            commands: [],
            music: [musicCandidate(id: "al1", kind: .album, artworkTrackID: "t1")]
        )

        XCTAssertFalse(items.isEmpty)
        XCTAssertFalse(items.contains { RowTintPolicy.allowsTint(for: $0, followsSelection: false) })
    }

    /// Nothing playing → nothing tinted, the panel is just the wash.
    func testNoTintedRowWhenNothingIsPlaying() {
        let items = PaletteListComposer.compose(
            query: "",
            nowPlaying: nil,
            commands: CommandCatalog.matches(for: ""),
            music: []
        )

        XCTAssertFalse(items.isEmpty)
        XCTAssertFalse(items.contains { RowTintPolicy.allowsTint(for: $0, followsSelection: false) })
    }

    /// The tinted row is the one whose artwork drives the ambient wash, so the
    /// card and the backdrop always agree.
    func testTintedRowSharesItsArtworkWithTheWash() {
        guard let source = PaletteItem.nowPlaying(track).artworkSource else {
            return XCTFail("expected the now-playing row to have artwork")
        }
        guard case .nowPlaying(let id, _, _, _) = source else {
            return XCTFail("expected a now-playing artwork source")
        }
        XCTAssertEqual(id, "PID")
    }
}

final class PaletteItemArtworkTests: XCTestCase {
    func testCommandRowsHaveNoArtwork() {
        let entry = CommandEntry(
            id: "settings",
            title: "Settings",
            subtitle: "",
            symbolName: "gearshape",
            action: .openSettings,
            keywords: ["settings"]
        )
        XCTAssertNil(PaletteItem.command(entry).artworkSource)
    }

    func testLibrarySongUsesItsTrack() {
        let candidate = MusicCandidate(
            id: "song:1",
            kind: .song,
            source: .library,
            title: "Take On Me",
            artist: "a-ha",
            album: "Hunting High and Low",
            persistentID: "ABC"
        )
        guard case .library(let persistentID, _, _)? = PaletteItem.music(candidate).artworkSource else {
            return XCTFail("expected library artwork")
        }
        XCTAssertEqual(persistentID, "ABC")
    }

    func testPlaylistPrefersItsRepresentativeTrack() {
        let candidate = MusicCandidate(
            id: "playlist:1",
            kind: .playlist,
            source: .library,
            title: "Road Trip",
            artist: "",
            album: "",
            persistentID: "PLAYLIST",
            artworkTrackID: "TRACK"
        )
        guard case .library(let persistentID, _, _)? = PaletteItem.music(candidate).artworkSource else {
            return XCTFail("expected library artwork")
        }
        XCTAssertEqual(persistentID, "TRACK")
    }

    func testCatalogUsesRemoteURL() {
        let url = URL(string: "https://example.com/art.jpg")!
        let candidate = MusicCandidate(
            id: "song:2",
            kind: .song,
            source: .catalog,
            title: "Song",
            artist: "Artist",
            album: "Album",
            artworkURL: url
        )
        guard case .remote(let remote)? = PaletteItem.music(candidate).artworkSource else {
            return XCTFail("expected remote artwork")
        }
        XCTAssertEqual(remote, url)
    }
}
