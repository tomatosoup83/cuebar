import Combine
import Foundation

/// Decides which palette the whole panel shows, and when it changes.
///
/// Owns the two rules that would otherwise be buried in the shell:
///
///  * **which** artwork drives the ambient colour — the now-playing track, or the
///    highlighted row when the user opts in, and
///  * **when** it changes — a pause before each transition, so cycling through
///    results doesn't strobe the whole panel.
///
/// Resolution is injected, so the rules and the timing are unit-testable without
/// a UI, a clock, or Music.
@MainActor
public final class AmbientPaletteCoordinator: ObservableObject {
    @Published public private(set) var palette: AlbumPalette?

    private let resolve: (ArtworkSource, PaletteStyle) async -> AlbumPalette?
    private let sleep: (Duration) async throws -> Void
    private let delay: Duration

    private var isEnabled = false
    private var followsSelection: Bool
    private var style: PaletteStyle = .classic
    private var nowPlaying: NowPlayingTrack?
    private var selection: PaletteItem?

    /// What the panel *should* be showing.
    private var desired: ArtworkSource?
    /// What it currently *is* showing. Tracking this separately is what makes a
    /// burst that ends always land on the row the user stopped on, instead of
    /// leaving whichever colour happened to be resolved last.
    private var published: ArtworkSource?
    /// The style that produced `published`, so switching theme or an option
    /// (same artwork, different extraction) forces a fresh resolve.
    private var publishedStyle: PaletteStyle?
    private var loop: Task<Void, Never>?
    /// Bumped whenever a loop is invalidated, so a superseded loop can never
    /// clear the handle belonging to a newer one.
    private var generation = 0
    /// Whether the leading pause has already been paid in the current burst.
    private var hasPausedThisBurst = false

    public init(
        followsSelection: Bool = false,
        delay: Duration = .milliseconds(350),
        resolve: @escaping (ArtworkSource, PaletteStyle) async -> AlbumPalette?,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.followsSelection = followsSelection
        self.delay = delay
        self.resolve = resolve
        self.sleep = sleep
    }

    // MARK: - Inputs

    /// Enables or disables ambient tinting (driven by the selected theme).
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        refresh()
    }

    /// Whether the ambient colour follows the highlighted row instead of the track.
    public func setFollowsSelection(_ follows: Bool) {
        guard follows != followsSelection else { return }
        followsSelection = follows
        refresh()
    }

    /// Chooses the extraction style. Changing it re-resolves even when the
    /// artwork is unchanged, so an A/B between the Album Art themes — or the
    /// global-colours option — updates the colour immediately.
    public func setStyle(_ style: PaletteStyle) {
        guard style != self.style else { return }
        self.style = style
        refresh()
    }

    /// Called after every now-playing poll.
    public func update(nowPlaying: NowPlayingTrack?) {
        guard nowPlaying != self.nowPlaying else { return }
        self.nowPlaying = nowPlaying
        refresh()
    }

    /// Called whenever the highlighted row changes.
    public func update(selection: PaletteItem?) {
        guard selection != self.selection else { return }
        self.selection = selection
        refresh()
    }

    /// Awaits the in-flight transition. Used by tests to assert on the result
    /// without racing the loop.
    func settle() async {
        // Start any loop the last refresh asked for, then wait it out.
        startLoopIfNeeded()
        while true {
            guard let running = loop else { return }
            await running.value
            if loop == nil { return }
        }
    }

#if DEBUG
    /// Development accessors, so a scripted cycle test can assert that what is
    /// shown matches what was asked for.
    public var debugDesiredKey: String? { desired?.cacheKey }
    public var debugPublishedKey: String? { published?.cacheKey }
#endif

    // MARK: - Internals

    private func refresh() {
        let target = isEnabled ? targetSource() : nil
        desired = target

        // Nothing to show: invalidate any running loop and clear.
        guard let target else {
            generation += 1
            loop?.cancel()
            loop = nil
            hasPausedThisBurst = false
            published = nil
            publishedStyle = nil
            palette = nil
            return
        }
        guard target != published || style != publishedStyle else { return }

        // Restart the loop rather than letting a resolve for a target the user has
        // already left run to completion first. Resolving an *uncached* album can
        // take seconds (it scans the whole Music library), so queueing behind one
        // is what made the colour arrive late — and land on the wrong album.
        // The abandoned fetch keeps running inside `PaletteCache` (it is shared
        // with the row's artwork), so nothing is wasted.
        generation += 1
        loop?.cancel()
        loop = nil
        startLoopIfNeeded()
    }

    private func startLoopIfNeeded() {
        guard loop == nil else { return }

        // The pause is leading: only the first change of a burst waits, so a burst
        // never becomes a long stall and never strobes.
        let shouldPause = !hasPausedThisBurst && palette != nil
        hasPausedThisBurst = true

        generation += 1
        let myGeneration = generation

        loop = Task { [weak self] in
            guard let self else { return }

            if shouldPause {
                try? await self.sleep(self.delay)
            }

            // Keep going until what is shown matches what is wanted, so a burst that
            // ends always settles on the row the user stopped on.
            while !Task.isCancelled {
                guard let want = self.desired else { break }
                let wantStyle = self.style
                guard want != self.published
                    || wantStyle != self.publishedStyle else { break }
                let started = Date()
                let resolved = await self.resolve(want, wantStyle)
#if DEBUG
                NSLog("Cuebar: resolve \(want.cacheKey) took "
                      + String(format: "%.2fs", Date().timeIntervalSince(started)))
#endif
                // Superseded by a newer loop, which owns the state from here.
                guard !Task.isCancelled else { return }
                // The selection or the theme/option moved on while we were
                // resolving: drop this result rather than pairing it with the
                // wrong row.
                guard self.desired == want, self.style == wantStyle else { continue }
                self.palette = resolved
                self.published = want
                self.publishedStyle = wantStyle
#if DEBUG
                NSLog("Cuebar: published \(want.cacheKey)")
#endif
            }

            if self.generation == myGeneration {
                self.loop = nil
                self.hasPausedThisBurst = false
            }
        }
    }

    /// The artwork the ambient colour should follow.
    private func targetSource() -> ArtworkSource? {
        guard followsSelection, let selected = selection?.artworkSource else {
            return nowPlayingSource()
        }
        return selected
    }

    private func nowPlayingSource() -> ArtworkSource? {
        Self.artworkSource(for: nowPlaying)
    }

    private static func artworkSource(for track: NowPlayingTrack?) -> ArtworkSource? {
        // Nothing playing, or a track with no album metadata to look up.
        guard let track, !(track.artist.isEmpty && track.album.isEmpty) else { return nil }
        return .nowPlaying(
            persistentID: track.persistentID,
            artist: track.artist,
            album: track.album,
            title: track.title
        )
    }
}
