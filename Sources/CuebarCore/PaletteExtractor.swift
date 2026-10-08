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

/// One colour cluster from median-cut quantization: the mean colour of the
/// pixels it holds, how many pixels those are, and their average row (0 = top).
///
/// The mean row lets the palette keep its vertical gradient even though the
/// clusters themselves ignore position.
public struct ColorCluster: Equatable, Sendable {
    public let color: ThemeColor
    public let population: Int
    public let meanRow: Double

    public init(color: ThemeColor, population: Int, meanRow: Double) {
        self.color = color
        self.population = population
        self.meanRow = meanRow
    }
}

/// Turns artwork pixels into a light, legible `AlbumPalette`.
///
/// The extraction is pure and deterministic so it can be unit-tested with
/// synthetic grids; only `grid(from:)` touches ImageIO/CoreGraphics.
public enum PaletteExtractor {
    /// How the three raw base colours are chosen from the artwork.
    ///
    /// `classic` averages the top and bottom thirds and picks the most vivid
    /// 4-bit histogram bucket. `clustered` runs median-cut quantization and
    /// draws the stops from distinct clusters, which separates multi-hue covers
    /// that would otherwise collapse into a single accent.
    ///
    /// Both feed the same legibility transform (`stop`), so the two modes differ
    /// only in *which* colour each role starts from.
    public enum Algorithm: String, CaseIterable, Sendable {
        case classic
        case clustered
    }

    /// How the `clustered` algorithm arranges its two background stops.
    ///
    /// Only meaningful for `.clustered`; the classic path always keeps the
    /// top/bottom-thirds gradient.
    public enum ClusterLayout: String, CaseIterable, Sendable {
        /// Upper clusters feed the top stop, lower ones the bottom, so the wash
        /// follows the cover's vertical structure.
        case gradient
        /// Every cluster feeds both stops, ignoring position — a pywal-style
        /// global colour. The two stops come out identical, so the panel is a
        /// flat wash rather than a gradient.
        case global
    }

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
        /// How many median-cut clusters the `clustered` algorithm extracts.
        /// Eight is enough to separate the few colours a cover is usually
        /// "about" without a 24×24 grid over-fragmenting.
        public var clusterBudget: Int = 8

        public init() {}

        public static let `default` = Tuning()
    }

    /// Returns nil only when there are no usable pixels.
    public static func palette(
        from grid: PixelGrid,
        tuning: Tuning = .default,
        algorithm: Algorithm = .classic,
        layout: ClusterLayout = .gradient
    ) -> AlbumPalette? {
        guard grid.pixelCount > 0, grid.rgb.count >= grid.pixelCount * 3 else { return nil }

        let base = baseColors(from: grid, algorithm: algorithm, layout: layout, tuning: tuning)
        let top = base.top
        let bottom = base.bottom
        let accent = base.accent

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

    // MARK: - Base colours

    /// The three raw colours the legibility transform works from.
    ///
    /// Kept separate from `palette(from:)` so each algorithm can be checked
    /// directly, without the transform on top.
    static func baseColors(
        from grid: PixelGrid,
        algorithm: Algorithm,
        layout: ClusterLayout = .gradient,
        tuning: Tuning = .default
    ) -> (top: ThemeColor, bottom: ThemeColor, accent: ThemeColor) {
        switch algorithm {
        case .classic:
            let top = average(grid, rows: 0 ..< max(1, grid.height / 3))
            let bottom = average(grid, rows: (grid.height * 2 / 3) ..< grid.height)
            return (top, bottom, vibrant(in: grid) ?? top)

        case .clustered:
            let clusters = clusters(in: grid, budget: tuning.clusterBudget)
            guard !clusters.isEmpty else {
                let top = average(grid, rows: 0 ..< max(1, grid.height / 3))
                let bottom = average(grid, rows: (grid.height * 2 / 3) ..< grid.height)
                return (top, bottom, top)
            }

            let top: ThemeColor
            let bottom: ThemeColor
            switch layout {
            case .gradient:
                // Keep the vertical structure: upper clusters feed the top stop,
                // lower ones the bottom. A cluster that straddles the midline (or
                // a solid cover with a single cluster) falls back to every cluster.
                let midRow = Double(grid.height) / 2
                let upper = clusters.filter { $0.meanRow < midRow }
                let lower = clusters.filter { $0.meanRow >= midRow }
                top = weightedAverage(upper.isEmpty ? clusters : upper)
                bottom = weightedAverage(lower.isEmpty ? clusters : lower)
            case .global:
                // pywal-style: ignore position, mix every cluster into one colour
                // used for both stops.
                let all = weightedAverage(clusters)
                top = all
                bottom = all
            }

            let accent = clusters
                .max(by: { accentScore($0) < accentScore($1) })?
                .color ?? top
            return (top, bottom, accent)
        }
    }

    /// Population-weighted mean of a set of clusters.
    private static func weightedAverage(_ clusters: [ColorCluster]) -> ThemeColor {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var total = 0
        for cluster in clusters {
            let weight = Double(cluster.population)
            red += cluster.color.red * weight
            green += cluster.color.green * weight
            blue += cluster.color.blue * weight
            total += cluster.population
        }
        guard total > 0 else { return .neutral }
        let divisor = Double(total)
        return ThemeColor(red: red / divisor, green: green / divisor, blue: blue / divisor)
    }

    /// The accent prefers the colour the cover is "about": vivid and well
    /// populated — the same trade-off `vibrant(in:)` makes for the classic path.
    private static func accentScore(_ cluster: ColorCluster) -> Double {
        cluster.color.chroma * Double(cluster.population)
    }

    // MARK: - Median cut

    /// Median-cut quantization of the grid into at most `budget` clusters.
    ///
    /// Deterministic and dependency-free: repeatedly split the box with the
    /// widest channel range at its median. That is ample for a 24×24 cover and a
    /// handful of clusters, and it separates distinct hues that a single
    /// histogram bucket would merge.
    static func clusters(in grid: PixelGrid, budget: Int = 8) -> [ColorCluster] {
        let pixelCount = grid.pixelCount
        guard pixelCount > 0, budget > 0, grid.rgb.count >= pixelCount * 3 else { return [] }

        // Indices, not colours, so a partition can reorder a sub-range in place.
        var indices = Array(0 ..< pixelCount)

        func value(_ index: Int, _ channel: Int) -> UInt8 {
            grid.rgb[index * 3 + channel]
        }

        func channelSpans(_ start: Int, _ end: Int) -> (red: Int, green: Int, blue: Int) {
            var low = (r: UInt8.max, g: UInt8.max, b: UInt8.max)
            var high = (r: UInt8.min, g: UInt8.min, b: UInt8.min)
            for i in start ..< end {
                let r = value(i, 0)
                let g = value(i, 1)
                let b = value(i, 2)
                low.r = min(low.r, r)
                high.r = max(high.r, r)
                low.g = min(low.g, g)
                high.g = max(high.g, g)
                low.b = min(low.b, b)
                high.b = max(high.b, b)
            }
            return (
                Int(high.r) - Int(low.r),
                Int(high.g) - Int(low.g),
                Int(high.b) - Int(low.b)
            )
        }

        var boxes: [(start: Int, end: Int)] = [(0, pixelCount)]

        while boxes.count < budget {
            var chosen = -1
            var chosenChannel = 0
            var chosenSpan = 0
            for (index, box) in boxes.enumerated() where box.end - box.start > 1 {
                let spans = channelSpans(box.start, box.end)
                // First widest channel wins, so ties are deterministic.
                var span = spans.red
                var channel = 0
                if spans.green > span { span = spans.green; channel = 1 }
                if spans.blue > span { span = spans.blue; channel = 2 }
                if span > chosenSpan {
                    chosenSpan = span
                    chosen = index
                    chosenChannel = channel
                }
            }
            guard chosen >= 0, chosenSpan > 0 else { break }

            let box = boxes[chosen]
            indices[box.start ..< box.end].sort {
                value($0, chosenChannel) < value($1, chosenChannel)
            }
            let mid = box.start + (box.end - box.start) / 2
            boxes[chosen] = (box.start, mid)
            boxes.append((mid, box.end))
        }

        return boxes.compactMap { box in
            let count = box.end - box.start
            guard count > 0 else { return nil }
            var red = 0.0
            var green = 0.0
            var blue = 0.0
            var rowSum = 0.0
            for position in box.start ..< box.end {
                let index = indices[position]
                red += Double(value(index, 0)) / 255
                green += Double(value(index, 1)) / 255
                blue += Double(value(index, 2)) / 255
                rowSum += Double(index / grid.width)
            }
            let divisor = Double(count)
            return ColorCluster(
                color: ThemeColor(red: red / divisor, green: green / divisor, blue: blue / divisor),
                population: count,
                meanRow: rowSum / divisor
            )
        }
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

/// A complete extraction recipe: which algorithm, and how the clustered one lays
/// out its stops.
///
/// `Hashable` so it can key the palette cache and stand in for the ambient
/// coordinator's identity check — switching either part must re-resolve the
/// same artwork.
public struct PaletteStyle: Hashable, Sendable {
    public let algorithm: PaletteExtractor.Algorithm
    public let clusterLayout: PaletteExtractor.ClusterLayout

    public init(
        algorithm: PaletteExtractor.Algorithm,
        clusterLayout: PaletteExtractor.ClusterLayout = .gradient
    ) {
        self.algorithm = algorithm
        self.clusterLayout = clusterLayout
    }

    /// The original Album Art extraction.
    public static let classic = PaletteStyle(algorithm: .classic)
    /// Clustered, keeping the vertical gradient.
    public static let clustered = PaletteStyle(algorithm: .clustered)
    /// Clustered, pywal-style global colour (no gradient).
    public static let clusteredGlobal = PaletteStyle(algorithm: .clustered, clusterLayout: .global)

    /// Stable identity for caches and comparisons.
    public var key: String { "\(algorithm.rawValue):\(clusterLayout.rawValue)" }
}

extension NSImage {
    /// A `CGImage` for this image, if one can be produced.
    public var cgImageRepresentation: CGImage? {
        var rect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
