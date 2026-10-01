import CuebarCore
import SwiftUI

extension Color {
    /// Bridges a Core `ThemeColor` into SwiftUI.
    init(themeColor: ThemeColor) {
        self.init(
            .sRGB,
            red: themeColor.red,
            green: themeColor.green,
            blue: themeColor.blue,
            opacity: 1
        )
    }
}

/// Chooses the glass material for a theme.
enum ThemeGlass {
    /// How strongly Album Art tints the glass itself (0 = untinted). Overridable
    /// at launch with `CUEBAR_GLASS_TINT` for quick A/B.
    ///
    /// This is the main colour lever when the palette changes rarely. It is
    /// deliberately **not** used while the ambient follows the highlighted row:
    /// a `Glass` value is a material parameter and does not animate, so a tint
    /// that changed on every row would snap instead of fading. There, the wash
    /// carries the colour because it *can* crossfade.
    static var tintOpacity: Double = 0.35

    /// How strongly the selected row is tinted with the cover's colour.
    ///
    /// The row keeps the system's translucent selection material underneath, so
    /// the panel glass still shows through — that translucency is what makes it
    /// read as glass rather than a painted slab. Overridable with
    /// `CUEBAR_ROW_TINT`.
    static var rowTintOpacity: Double = 0.55

    static func style(
        theme: ThemeID,
        palette: AlbumPalette?,
        followsSelection: Bool
    ) -> Glass {
        guard theme == .albumArt,
              !followsSelection,
              tintOpacity > 0,
              let palette else {
            return .regular
        }
        return .regular.tint(Color(themeColor: palette.accent).opacity(tintOpacity))
    }
}

/// The wash drawn *behind* the glass: a light (or dark) album-art gradient, or
/// nothing.
///
/// It must sit behind `.glassEffect` so the glass samples it instead of the
/// desktop. Under Tahoe — or with no palette, or when Reduce Transparency is on —
/// it renders nothing, so the panel looks exactly as it always has.
struct ThemeBackground: View {
    let theme: ThemeID
    let palette: AlbumPalette?
    /// True while the ambient colour follows the highlighted row.
    var followsSelection: Bool = false
    /// Whether the wash drifts (music playing). When false it holds still,
    /// keeping its current shape rather than snapping back.
    var isDrifting: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How strongly the wash tints the panel when the palette changes rarely.
    /// Overridable at launch with `CUEBAR_WASH_OPACITY`.
    static var washOpacity: Double = 0.36

    /// …and while following the highlighted row, where the wash is the only
    /// carrier of the colour (the glass is untinted), so it needs more presence.
    static var followWashOpacity: Double = 0.62

    var body: some View {
        if theme == .albumArt, !reduceTransparency, let palette {
            let drifting = isDrifting && !reduceMotion
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !drifting)) { context in
                let time = clock.time(at: context.date, running: drifting)
                // One mesh per palette, so a cover change crossfades as a whole
                // instead of fighting the per-frame point updates.
                ZStack {
                    AmbientMesh(palette: palette, time: time)
                        .id(palette)
                        .transition(.opacity)
                }
            }
            .opacity(followsSelection ? Self.followWashOpacity : Self.washOpacity)
        } else {
            Color.clear
        }
    }

    @State private var clock = DriftClock()
}

/// Time that only advances while the wash is drifting, so pausing freezes the
/// mesh where it is and resuming carries on from there.
@MainActor
final class DriftClock {
    // A random start, so the panel doesn't open on the same shape every time.
    private var elapsed = TimeInterval.random(in: 0 ..< 600)
    private var lastTick: Date?

    func time(at date: Date, running: Bool) -> TimeInterval {
        guard running else {
            lastTick = nil
            return elapsed
        }
        if let lastTick {
            // Clamp, so a hidden panel or a stalled frame doesn't lurch forward.
            elapsed += min(max(date.timeIntervalSince(lastTick), 0), 0.1)
        }
        lastTick = date
        return elapsed
    }
}

/// A 3×3 mesh of the cover's colours whose inner points slowly slide around,
/// like Apple Music's living backdrop.
///
/// Corners stay pinned so the panel edges are always covered; the edge
/// midpoints slide along their edges and the centre wanders on a slow
/// Lissajous path. Periods are slow (≈ 14–22 s) and unrelated, so the motion
/// never visibly loops.
struct AmbientMesh: View {
    let palette: AlbumPalette
    let time: TimeInterval

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: points,
            colors: colors,
            smoothsColors: true
        )
    }

    private func wave(_ period: Double, _ phase: Double) -> Float {
        Float(sin(time * 2 * .pi / period + phase))
    }

    private var points: [SIMD2<Float>] {
        [
            [0, 0], [0.5 + 0.30 * wave(14, 0), 0], [1, 0],
            [0, 0.5 + 0.30 * wave(17, 1.3)],
            [0.5 + 0.28 * wave(22, 2.1), 0.5 + 0.26 * wave(19, 0.4)],
            [1, 0.5 + 0.30 * wave(16, 3.7)],
            [0, 1], [0.5 + 0.30 * wave(20, 5.1), 1], [1, 1]
        ]
    }

    /// The light stops on the outside, the cover's signature colour drifting
    /// through the middle.
    private var colors: [Color] {
        let top = palette.top
        let bottom = palette.bottom
        let accent = palette.accent
        return [
            top, top.blended(with: accent, amount: 0.45), top,
            accent.blended(with: bottom, amount: 0.35), accent, top.blended(with: accent, amount: 0.6),
            bottom, bottom.blended(with: accent, amount: 0.4), bottom
        ].map { Color(themeColor: $0) }
    }
}
