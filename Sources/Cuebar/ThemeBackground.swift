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

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// How strongly the wash tints the panel when the palette changes rarely.
    /// Overridable at launch with `CUEBAR_WASH_OPACITY`.
    static var washOpacity: Double = 0.30

    /// …and while following the highlighted row, where the wash is the only
    /// carrier of the colour (the glass is untinted), so it needs more presence.
    static var followWashOpacity: Double = 0.62

    var body: some View {
        if theme == .albumArt, !reduceTransparency, let palette {
            LinearGradient(
                colors: [
                    Color(themeColor: palette.top),
                    Color(themeColor: palette.bottom)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(followsSelection ? Self.followWashOpacity : Self.washOpacity)
        } else {
            Color.clear
        }
    }
}
