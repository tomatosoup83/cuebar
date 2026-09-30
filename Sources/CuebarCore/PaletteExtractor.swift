import AppKit
import CoreGraphics
import Foundation

/// A small sRGB pixel buffer: row-major RGB triplets, 3 bytes per pixel.
public struct PixelGrid: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgb: [UInt8]

    public init(width: Int, height: Int, rgb: [UInt8]) {
        self.width = width
        self.height = height
        self.rgb = rgb
    }

    public var pixelCount: Int { width * height }
}

/// Turns artwork pixels into a light, legible `AlbumPalette`.
///
/// The extraction is pure and deterministic so it can be unit-tested with
/// synthetic grids; only `grid(from:)` touches ImageIO/CoreGraphics.
public enum PaletteExtractor {
    /// Tunables for the legibility transform.
    public struct Tuning: Sendable {
        /// Every *light* stop is lifted to at least this luma, so bright covers
        /// stay airy.
        public var minimumLuma: Double = 0.70
        /// Covers whose *lower-quantile* brightness is below this — and which are
        /// colourless — produce a **dark** panel instead of being lifted light.
        public var darkCoverThreshold: Double = 0.45
        /// Which percentile of per-pixel brightness to test against the threshold.
        /// A low quantile ignores bright highlights such as large white type.
        public var darkCoverQuantile: Double = 0.35
        /// Luma a dark cover's stops are pulled to. Deliberately *not* very dark:
        /// the panel's content stays light-on-dark-free in one scheme, because an
        /// instant light/dark flip is what made the change between a light and a
        /// dark album feel so abrupt. Dark covers read as clearly darker without
        /// the whole panel inverting.
        public var darkPanelLuma: Double = 0.44
        /// The chroma band the two background stops are pulled into.
        public var washChromaMinimum: Double = 0.16
        public var washChromaMaximum: Double = 0.40
        /// The chroma band for the accent (selected row + glass tint).
        public var accentChromaMinimum: Double = 0.28
        public var accentChromaMaximum: Double = 0.70
        /// The selected row's fill: darkened to this luma so it clearly separates
        /// from the light wash behind it, then saturated so it reflects the cover.
        /// `contrastingForeground` handles readability at whatever this produces.
        public var selectionLuma: Double = 0.44
        public var selectionChromaMinimum: Double = 0.45
        public var selectionChromaMaximum: Double = 0.72
        /// How much of each stop's colour is borrowed from the cover's signature
        /// colour. Averaging a third of a *photograph* mixes hues and greys out,
        /// so the stops lean on the vivid bucket instead of the average.
        public var topFromAccent: Double = 0.45
        public var bottomFromAccent: Double = 0.45
        /// Artwork below this chroma counts as colourless, and the panel falls
        /// back to plain glass rather than fabricating a tint from noise.
        public var minimumChroma: Double = 0.08

        public init() {}

        public static let `default` = Tuning()
    }

    /// Returns nil only when there are no usable pixels.
    public static func palette(from grid: PixelGrid, tuning: Tuning = .default) -> AlbumPalette? {        guard grid.pixelCount > 0, grid.rgb.count >= grid.pixelCount * 3 else { return nil }

        let top = average(grid, rows: 0 ..< max(1, grid.height / 3))
        let bottom = average(grid, rows: (grid.height * 2 / 3) ..< grid.height)
        let accent = vibrant(in: grid) ?? top

        // Judged on the *raw* colours, before the legibility transform.
        let coverChroma = max(top.chroma, max(bottom.chroma, accent.chroma))
        let isUsable = coverChroma > tuning.minimumChroma

        // A *colourless, dark* cover gives a dark panel. Both conditions matter:
        //
        //  · "colourless" keeps IGOR-style covers — black, but with a strong
        //    colour in them — on the coloured treatment they already had.
        //  · darkness is measured from the distribution, not the mean. Averaging
        //    a black sleeve with big white type lands on mid grey, which is how a
        //    black cover ended up as a near-white panel.
        let panelIsDark = forcedDarkPanel()
            ?? (!isUsable
                && lowerQuantileBrightness(in: grid, quantile: tuning.darkCoverQuantile)
                    < tuning.darkCoverThreshold)

        return AlbumPalette(
            top: stop(
                top,
                leaningOn: accent,
                amount: tuning.topFromAccent,
                chroma: tuning.washChromaMinimum ... tuning.washChromaMaximum,
                panelIsDark: panelIsDark,
                tuning: tuning
            ),
            bottom: stop(
                bottom,
                leaningOn: accent,
                amount: tuning.bottomFromAccent,
                chroma: tuning.washChromaMinimum ... tuning.washChromaMaximum,
                panelIsDark: panelIsDark,
                tuning: tuning
            ),
            accent: stop(
                accent,
                leaningOn: accent,
                amount: 0,
                chroma: tuning.accentChromaMinimum ... tuning.accentChromaMaximum,
                panelIsDark: panelIsDark,
                tuning: tuning
            ),
            selection: accent
                .scaled(toLuma: tuning.selectionLuma)
                .withChroma(atLeast: tuning.selectionChromaMinimum)
                .withChroma(atMost: tuning.selectionChromaMaximum),
            isUsable: isUsable
        )
    }

    /// Downscales a `CGImage` to a `side`×`side` grid. Thin; not unit-tested.
    ///
    /// The bitmap is stored top-row-first, so row 0 is the visual top — which is
    /// what the gradient stops assume.
    public static func grid(from image: CGImage, side: Int = 24) -> PixelGrid? {
        let dimension = max(1, side)
        let bytesPerRow = dimension * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * dimension)

        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let context = CGContext(
            data: &bytes,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))

        var rgb = [UInt8](repeating: 0, count: dimension * dimension * 3)
        for index in 0 ..< (dimension * dimension) {
            rgb[index * 3] = bytes[index * 4]
            rgb[index * 3 + 1] = bytes[index * 4 + 1]
            rgb[index * 3 + 2] = bytes[index * 4 + 2]
        }
        return PixelGrid(width: dimension, height: dimension, rgb: rgb)
    }

    // MARK: - Internals

    /// A development override that forces the dark-panel path so it can be
    /// eyeballed on a machine whose library has no black cover
    /// (`CUEBAR_DARK_COVER=1`).
    static func forcedDarkPanel() -> Bool? {
        #if DEBUG
        if debugForceDarkPanel { return true }
        #endif
        return nil
    }

    #if DEBUG
    /// Development override: force the dark-panel path regardless of the cover.
    nonisolated(unsafe) public static var debugForceDarkPanel = false
    #endif

    /// Turns a raw colour into a usable stop: borrow the cover's signature colour
    /// so photographic averages don't grey out, lift it to either the light or the
    /// dark target depending on the cover, then pull its chroma into the given
    /// band so it is never muddy or garish.
    private static func stop(
        _ color: ThemeColor,
        leaningOn accent: ThemeColor,
        amount: Double,
        chroma: ClosedRange<Double>,
        panelIsDark: Bool,
        tuning: Tuning
    ) -> ThemeColor {
        let targetLuma = panelIsDark ? tuning.darkPanelLuma : tuning.minimumLuma
        return color.blended(with: accent, amount: amount)
            .raised(toLuma: targetLuma)
            .withChroma(atLeast: chroma.lowerBound)
            .withChroma(atMost: chroma.upperBound)
    }

    /// The per-pixel brightness at `quantile` (0…1) across the grid.
    ///
    /// Robust where a mean is not: a black cover carrying large white lettering
    /// averages to mid grey, but its lower quantiles are still black, which is
    /// what "this cover is dark" actually means.
    static func lowerQuantileBrightness(in grid: PixelGrid, quantile: Double) -> Double {
        var values: [Double] = []
        values.reserveCapacity(grid.pixelCount)
        for index in stride(from: 0, to: grid.rgb.count - 2, by: 3) {
            let red = Double(grid.rgb[index]) / 255
            let green = Double(grid.rgb[index + 1]) / 255
            let blue = Double(grid.rgb[index + 2]) / 255
            values.append(max(red, max(green, blue)))
        }
        guard !values.isEmpty else { return 1 }
        values.sort()
        let position = Int(Double(values.count - 1) * quantile.clampedUnit)
        return values[position]
    }

    private static func average(_ grid: PixelGrid, rows: Range<Int>) -> ThemeColor {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0

        for row in rows where row >= 0 && row < grid.height {
            for column in 0 ..< grid.width {
                let index = (row * grid.width + column) * 3
                guard index + 2 < grid.rgb.count else { continue }
                red += Double(grid.rgb[index]) / 255
                green += Double(grid.rgb[index + 1]) / 255
                blue += Double(grid.rgb[index + 2]) / 255
                count += 1
            }
        }

        guard count > 0 else { return .neutral }
        let divisor = Double(count)
        return ThemeColor(red: red / divisor, green: green / divisor, blue: blue / divisor)
    }

    /// The most saturated, well-populated 4-bit colour bucket.
    ///
    /// Frequency alone picks muddy browns; weighting by chroma prefers the
    /// colour the cover is "about".
    private static func vibrant(in grid: PixelGrid) -> ThemeColor? {
        let bucketCount = 16 * 16 * 16
        var sums = [(red: Double, green: Double, blue: Double)](repeating: (0, 0, 0), count: bucketCount)
        var counts = [Int](repeating: 0, count: bucketCount)

        for index in stride(from: 0, to: grid.rgb.count - 2, by: 3) {
            let red = Double(grid.rgb[index]) / 255
            let green = Double(grid.rgb[index + 1]) / 255
            let blue = Double(grid.rgb[index + 2]) / 255
            let key = (Int(red * 15) << 8) | (Int(green * 15) << 4) | Int(blue * 15)
            sums[key].red += red
            sums[key].green += green
            sums[key].blue += blue
            counts[key] += 1
        }

        var best: ThemeColor?
        var bestScore = 0.0

        for key in 0 ..< bucketCount where counts[key] > 0 {
            let count = Double(counts[key])
            let color = ThemeColor(
                red: sums[key].red / count,
                green: sums[key].green / count,
                blue: sums[key].blue / count
            )
            let score = color.chroma * count
            if score > bestScore {
                bestScore = score
                best = color
            }
        }

        return best
    }
}

extension NSImage {
    /// A `CGImage` for this image, if one can be produced.
    public var cgImageRepresentation: CGImage? {
        var rect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
