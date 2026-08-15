#!/usr/bin/env swift
import AppKit
import Foundation

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

guard CommandLine.arguments.count == 2 else {
    fail("usage: verify_app_icon.swift /path/to/App.app")
}

let appPath = CommandLine.arguments[1]
let workspace = NSWorkspace.shared
workspace.noteFileSystemChanged(appPath)

let appIcon = workspace.icon(forFile: appPath)
let genericIcon = workspace.icon(forFileType: "app")
let appPixels = renderRGBA(appIcon)
let genericPixels = renderRGBA(genericIcon)
let difference = meanAbsoluteDifference(appPixels, genericPixels)

print(String(format: "NSWorkspace icon difference from generic: %.2f", difference))

// A custom app icon should be visibly different from macOS' generic application icon.
// Keeping this threshold deliberately low makes the check resilient to OS rendering changes.
if difference < 3.0 {
    fail("NSWorkspace returned the generic macOS application icon")
}

print("NSWorkspace custom app icon check passed")
