#!/usr/bin/env swift
import AppKit
import Foundation
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func renderRGBA(_ image: NSImage, size: Int = 128) -> [UInt8] {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fail("Could not allocate bitmap for icon verification")
    }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fail("Could not create graphics context for icon verification")
    }
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    image.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero,
        operation: .copy,
        fraction: 1.0,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let bitmap = rep.bitmapData else {
        fail("Could not read rendered icon pixels")
    }
    return Array(UnsafeBufferPointer(start: bitmap, count: rep.bytesPerRow * rep.pixelsHigh))
}

func meanAbsoluteDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, !a.isEmpty else {
        fail("Icon buffers are not comparable")
    }
    var total: UInt64 = 0
    for i in 0..<a.count {
        total += UInt64(abs(Int(a[i]) - Int(b[i])))
    }
    return Double(total) / Double(a.count)
}

func sourceImageLooksUsable(_ pixels: [UInt8]) -> Bool {
    guard pixels.count >= 4 else { return false }
    var luminanceTotal = 0.0
    var minimumLuminance = 255.0
    var maximumLuminance = 0.0
    var chromaTotal = 0.0
    var pixelCount = 0

    for index in stride(from: 0, to: pixels.count - 3, by: 4) {
        let red = Double(pixels[index])
        let green = Double(pixels[index + 1])
        let blue = Double(pixels[index + 2])
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        luminanceTotal += luminance
        minimumLuminance = min(minimumLuminance, luminance)
        maximumLuminance = max(maximumLuminance, luminance)
        chromaTotal += max(red, green, blue) - min(red, green, blue)
        pixelCount += 1
    }

    let meanLuminance = luminanceTotal / Double(pixelCount)
    let meanChroma = chromaTotal / Double(pixelCount)
    print(String(format: "Source icon mean luminance: %.2f, range: %.2f, chroma: %.2f", meanLuminance, maximumLuminance - minimumLuminance, meanChroma))
    return meanLuminance > 8.0 && maximumLuminance - minimumLuminance > 40.0 && meanChroma > 1.0
}

func exportPNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fail("Could not encode NSWorkspace icon as PNG")
    }
    do {
        try png.write(to: URL(fileURLWithPath: path), options: .atomic)
    } catch {
        fail("Could not export NSWorkspace icon to \(path): \(error)")
    }
}

guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 else {
    fail("usage: verify_app_icon.swift /path/to/App.app /path/to/source.png [/tmp/export.png]")
}

let appPath = CommandLine.arguments[1]
let sourcePath = CommandLine.arguments[2]
let workspace = NSWorkspace.shared
workspace.noteFileSystemChanged(appPath)

let appIcon = workspace.icon(forFile: appPath)
let genericIcon = workspace.icon(for: .application)
guard let sourceIcon = NSImage(contentsOfFile: sourcePath) else {
    fail("Could not decode the source icon: \(sourcePath)")
}
let appPixels = renderRGBA(appIcon)
let genericPixels = renderRGBA(genericIcon)
let sourcePixels = renderRGBA(sourceIcon)
let genericDifference = meanAbsoluteDifference(appPixels, genericPixels)
let sourceDifference = meanAbsoluteDifference(appPixels, sourcePixels)

print(String(format: "NSWorkspace icon difference from generic: %.2f", genericDifference))
print(String(format: "NSWorkspace icon difference from source: %.2f", sourceDifference))

// A custom app icon should be visibly different from macOS' generic application icon.
// Keeping this threshold deliberately low makes the check resilient to OS rendering changes.
if genericDifference < 3.0 {
    fail("NSWorkspace returned the generic macOS application icon")
}

if !sourceImageLooksUsable(sourcePixels) {
    fail("The source icon decoded as blank, black, low-contrast, or colorless")
}

// This catches a valid-but-wrong ICNS, including a stale icon from LaunchServices.
if sourceDifference > 20.0 {
    fail("NSWorkspace did not return the icon derived from assets/GPT-Gateway.png")
}

if CommandLine.arguments.count == 4 {
    exportPNG(appIcon, to: CommandLine.arguments[3])
    print("NSWorkspace icon exported to: \(CommandLine.arguments[3])")
}

print("NSWorkspace custom app icon check passed")
