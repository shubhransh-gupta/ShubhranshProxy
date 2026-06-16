#!/usr/bin/env swift
import AppKit

/// Resizes Scripts/icon_source.png into macOS AppIcon.appiconset PNGs.
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = repoRoot.appendingPathComponent("Scripts/icon_source.png")
let appIconDir = repoRoot.appendingPathComponent("ShubhranshProxy/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

guard let source = NSImage(contentsOf: sourceURL),
      let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Missing or invalid Scripts/icon_source.png\n", stderr)
    exit(1)
}

func resizedPNG(from image: CGImage, side: Int) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    guard let rep else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let specs: [(name: String, side: Int)] = [
    ("icon_16.png", 16),
    ("icon_16@2x.png", 32),
    ("icon_32.png", 32),
    ("icon_32@2x.png", 64),
    ("icon_128.png", 128),
    ("icon_128@2x.png", 256),
    ("icon_256.png", 256),
    ("icon_256@2x.png", 512),
    ("icon_512.png", 512),
    ("icon_512@2x.png", 1024),
]

for spec in specs {
    guard let data = resizedPNG(from: cgImage, side: spec.side) else {
        fputs("Failed to generate \(spec.name)\n", stderr)
        exit(1)
    }
    let url = appIconDir.appendingPathComponent(spec.name)
    try data.write(to: url)
    print("Wrote \(spec.name) (\(spec.side) px)")
}
