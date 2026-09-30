import Foundation

/// A plain sRGB colour. Core stays SwiftUI-free, so views convert this to a
/// `Color` themselves.
public struct ThemeColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red.clampedUnit
        self.green = green.clampedUnit
        self.blue = blue.clampedUnit
    }

    /// The neutral base used as a fallback when there are no pixels.
    public static let neutral = ThemeColor(red: 0.60, green: 0.60, blue: 0.64)

    public static let white = ThemeColor(red: 1, green: 1, blue: 1)

    /// Brightest channel — a cheap proxy for lightness.
    public var brightness: Double { max(red, green, blue) }

    /// Chroma (`max − min`) in 0…1. Zero means grey.
    public var chroma: Double { max(red, green, blue) - min(red, green, blue) }

    /// Rec. 601 luma, used to desaturate without changing perceived lightness.
    public var luma: Double { 0.299 * red + 0.587 * green + 0.114 * blue }

    /// Scales the colour's chroma toward grey, preserving luma.
    /// `amount` 0 = grey, 1 = unchanged.
    public func withSaturation(_ amount: Double) -> ThemeColor {
        let f = amount.clampedUnit
        let l = luma
        return ThemeColor(
            red: l + (red - l) * f,
            green: l + (green - l) * f,
            blue: l + (blue - l) * f
        )
    }

    /// Mixes toward `other` by `amount` (0 = self, 1 = other).
    public func blended(with other: ThemeColor, amount: Double) -> ThemeColor {
        let a = amount.clampedUnit
        return ThemeColor(
            red: red + (other.red - red) * a,
            green: green + (other.green - green) * a,
            blue: blue + (other.blue - blue) * a
        )
    }

    /// Blends toward white until the luma reaches `minimum`. Never darkens, and
    /// is a no-op once the colour is already light enough.
    public func raised(toLuma minimum: Double) -> ThemeColor {
        let target = minimum.clampedUnit
        guard luma < target, luma < 0.999 else { return self }
        return blended(with: .white, amount: (target - luma) / (1 - luma))
    }

    /// Raises chroma to at least `minimum`, preserving luma. Faint colours are
    /// pushed back toward their hue; already-colourful ones are left alone, and a
    /// perfectly neutral colour has no hue to push toward so it stays put.
    public func withChroma(atLeast minimum: Double) -> ThemeColor {
        let floor = max(0, minimum)
        guard chroma > 0, chroma < floor else { return self }
        return scaledChroma(floor / chroma)
    }

    /// Lowers chroma to at most `maximum`, preserving luma.
    public func withChroma(atMost maximum: Double) -> ThemeColor {
        let ceiling = max(0, maximum)
        guard chroma > ceiling else { return self }
        guard ceiling > 0 else {
            let l = luma
            return ThemeColor(red: l, green: l, blue: l)
        }
        return scaledChroma(ceiling / chroma)
    }

    /// Scales the channels so the luma becomes `target`, preserving hue. Scaling
    /// up can clip a bright channel; scaling down never does.
    public func scaled(toLuma target: Double) -> ThemeColor {
        let t = max(0, target)
        guard luma > 0.001 else { return self }
        let factor = t / luma
        return ThemeColor(red: red * factor, green: green * factor, blue: blue * factor)
    }

    /// WCAG relative luminance (0…1).
    ///
    /// Deliberately *not* `luma`: WCAG linearises the channels, so it weights
    /// blue far less and green far more. That is what a contrast decision needs —
    /// a saturated blue is genuinely dark to the eye, a saturated yellow is not.
    public var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio between this colour and `other`, from 1 to 21.
    public func contrastRatio(against other: ThemeColor) -> Double {
        let mine = relativeLuminance
        let theirs = other.relativeLuminance
        let lighter = Swift.max(mine, theirs)
        let darker = Swift.min(mine, theirs)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Scales chroma by `factor`, preserving luma. Factors above 1 boost.
    ///
    /// Unlike `withSaturation` this is not clamped to 0…1, because brightening a
    /// colour necessarily desaturates it and we need to put the chroma back.
    private func scaledChroma(_ factor: Double) -> ThemeColor {
        let l = luma
        return ThemeColor(
            red: l + (red - l) * factor,
            green: l + (green - l) * factor,
            blue: l + (blue - l) * factor
        )
    }
}

extension Double {
    /// Clamps to 0…1.
    var clampedUnit: Double { Swift.min(Swift.max(self, 0), 1) }
}
