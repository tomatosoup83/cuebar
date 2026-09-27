#!/usr/bin/env swift
//
// Generates Cuebar app-icon candidates and the final .icns.
//
//   swift Scripts/make-icon.swift preview <outDir>
//   swift Scripts/make-icon.swift icns <designId> <out.icns>
//
import AppKit
import CoreGraphics
import Foundation

// MARK: - Designs

struct Design {
    let id: String
    let name: String
    let colors: [CGColor]
    let symbol: String
    let symbolScale: CGFloat
    /// Draw five rounded equalizer bars instead of an SF Symbol.
    var customBars: Bool = false
}

func hex(_ value: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((value >> 16) & 0xff) / 255,
        green: CGFloat((value >> 8) & 0xff) / 255,
        blue: CGFloat(value & 0xff) / 255,
        alpha: 1
    )
}

let designs: [Design] = [
    Design(id: "waveform", name: "Waveform",
           colors: [hex(0xFF6A8A), hex(0xA44BFF)], symbol: "waveform", symbolScale: 0.60),
    Design(id: "equalizer", name: "Equalizer bars",
           colors: [hex(0xFF6A8A), hex(0xA44BFF)], symbol: "", symbolScale: 0, customBars: true),
    Design(id: "command", name: "Command key",
           colors: [hex(0x4A4A52), hex(0x1B1B1F)], symbol: "command", symbolScale: 0.46),
    Design(id: "search", name: "Search",
           colors: [hex(0x4FA2FF), hex(0x1C55F0)], symbol: "magnifyingglass", symbolScale: 0.52),
    Design(id: "note", name: "Music note",
           colors: [hex(0xFF5B7A), hex(0xFA2E55)], symbol: "music.note", symbolScale: 0.50)
]

let canvas: CGFloat = 1024
let bodyInset: CGFloat = 100
let bodySize = canvas - bodyInset * 2
let bodyRadius: CGFloat = 190

// MARK: - Drawing

func makeContext() -> CGContext {
    CGContext(
        data: nil,
        width: Int(canvas),
        height: Int(canvas),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func drawIcon(_ design: Design) -> CGImage {
    let context = makeContext()
    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsContext

    let bodyRect = CGRect(x: bodyInset, y: bodyInset, width: bodySize, height: bodySize)
    let bodyPath = CGPath(
        roundedRect: bodyRect,
        cornerWidth: bodyRadius,
        cornerHeight: bodyRadius,
        transform: nil
    )

    // Drop shadow.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -14),
        blur: 34,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.32)
    )
    context.addPath(bodyPath)
    context.setFillColor(design.colors[0])
    context.fillPath()
    context.restoreGState()

    // Gradient body.
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: design.colors as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
        end: CGPoint(x: bodyRect.maxX, y: bodyRect.minY),
        options: []
    )
    // Soft top highlight.
    let highlight = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
                 CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        highlight,
        start: CGPoint(x: bodyRect.midX, y: bodyRect.maxY),
        end: CGPoint(x: bodyRect.midX, y: bodyRect.midY),
        options: []
    )
    context.restoreGState()

    if design.customBars {
        drawBars(context, bodyRect: bodyRect)
    } else {
        drawSymbol(design, bodyRect: bodyRect, clipPath: bodyPath)
    }

    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()!
}

func drawSymbol(_ design: Design, bodyRect: CGRect, clipPath: CGPath) {
    guard let base = NSImage(systemSymbolName: design.symbol, accessibilityDescription: nil) else { return }
    let configuration = NSImage.SymbolConfiguration(pointSize: bodyRect.height * 0.7, weight: .semibold)
    guard let symbol = base.withSymbolConfiguration(configuration),
          let cgSymbol = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

    // Fit the glyph inside a square box so wide symbols don't overflow.
    let maxSide = bodyRect.width * design.symbolScale
    let scale = min(maxSide / CGFloat(cgSymbol.width), maxSide / CGFloat(cgSymbol.height))
    let size = CGSize(width: CGFloat(cgSymbol.width) * scale, height: CGFloat(cgSymbol.height) * scale)
    let target = CGRect(
        x: bodyRect.midX - size.width / 2,
        y: bodyRect.midY - size.height / 2,
        width: size.width,
        height: size.height
    )

    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    context.addPath(clipPath)
    context.clip()
    context.clip(to: target, mask: cgSymbol)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(target)
    context.restoreGState()
}

func drawBars(_ context: CGContext, bodyRect: CGRect) {
    let heights: [CGFloat] = [0.34, 0.62, 0.86, 0.5, 0.72]
    let barWidth = bodyRect.width * 0.085
    let spacing = bodyRect.width * 0.055
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * spacing
    var x = bodyRect.midX - totalWidth / 2
    let maxHeight = bodyRect.height * 0.52

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    for fraction in heights {
        let height = maxHeight * fraction
        let rect = CGRect(
            x: x,
            y: bodyRect.midY - height / 2,
            width: barWidth,
            height: height
        )
        context.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        context.fillPath()
        x += barWidth + spacing
    }
}

func downscale(_ image: CGImage, to size: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

// MARK: - Commands

let arguments = CommandLine.arguments

func design(with id: String) -> Design? {
    designs.first { $0.id == id }
}

switch arguments.count >= 2 ? arguments[1] : "" {
case "preview":
    let outDir = URL(fileURLWithPath: arguments.count >= 3 ? arguments[2] : "build/icons")
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    for design in designs {
        let image = drawIcon(design)
        let preview = downscale(image, to: 256)
        writePNG(preview, to: outDir.appendingPathComponent("\(design.id).png"))
        print("wrote \(design.id).png  (\(design.name))")
    }

case "icns":
    guard arguments.count >= 4, let design = design(with: arguments[2]) else {
        FileHandle.standardError.write(Data("usage: icns <designId> <out.icns>\n".utf8))
        exit(1)
    }
    let outURL = URL(fileURLWithPath: arguments[3])
    let master = drawIcon(design)

    let iconsetName = "AppIcon.iconset"
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent(iconsetName)
    try? FileManager.default.removeItem(at: iconset)
    try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    let variants: [(String, Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
    ]
    for (name, size) in variants {
        let image = size == 1024 ? master : downscale(master, to: size)
        writePNG(image, to: iconset.appendingPathComponent(name))
    }

    try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", outURL.path]
    try? process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        FileHandle.standardError.write(Data("iconutil failed\n".utf8))
        exit(1)
    }
    print("wrote \(outURL.path)  (design: \(design.name))")

default:
    FileHandle.standardError.write(Data("usage: make-icon.swift preview <outDir> | icns <designId> <out.icns>\n".utf8))
    exit(1)
}
