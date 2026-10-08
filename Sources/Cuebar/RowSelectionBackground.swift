import SwiftUI
import CuebarCore

/// The selected-row treatment shared by every list row.
///
/// Extracted so the extended album view's track rows and the search result rows
/// can't drift: the system's translucent selection material with the cover's
/// colour laid *through* it, plus the specular edge that reads as glass.
struct RowSelectionBackground: View {
    let isSelected: Bool
    var accent: AlbumPalette?
    var cornerRadius: CGFloat = 10

    var body: some View {
        if isSelected {
            let shape = RoundedRectangle(cornerRadius: cornerRadius)
            shape
                .fill(.selection)
                .overlay {
                    if let accent {
                        shape.fill(
                            Color(themeColor: accent.selection)
                                .opacity(ThemeGlass.rowTintOpacity)
                        )
                    }
                }
                .overlay {
                    if accent != nil {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.34), .white.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                    }
                }
        } else {
            Color.clear
        }
    }
}
