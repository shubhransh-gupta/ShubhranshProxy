#!/usr/bin/env swift
import AppKit

/// Generates macOS AppIcon.appiconset PNGs (proxy-themed: indigo tile + "SP").
func drawIcon(side: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
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
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded rect background
    let corner = CGFloat(side) * 0.22
    let rect = CGRect(x: 0, y: 0, width: side, height: side)
    let path = CGPath(roundedRect: rect.insetBy(dx: CGFloat(side) * 0.06, dy: CGFloat(side) * 0.06), cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 0.18, green: 0.32, blue: 0.82, alpha: 1))
    ctx.fillPath()

    // Accent bar (suggests "traffic / pipe")
    ctx.setFillColor(CGColor(red: 0.35, green: 0.75, blue: 1, alpha: 0.95))
    let barH = CGFloat(side) * 0.08
    ctx.fill(CGRect(x: CGFloat(side) * 0.12, y: CGFloat(side) * 0.78, width: CGFloat(side) * 0.76, height: barH))

    let fontSize = CGFloat(side) * 0.34
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let text = "SP" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let sz = text.size(withAttributes: attrs)
    let origin = NSPoint(
        x: (CGFloat(side) - sz.width) / 2,
        y: (CGFloat(side) - sz.height) / 2 - CGFloat(side) * 0.04
    )
    text.draw(at: origin, withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let appIconDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

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
    guard let rep = drawIcon(side: spec.side),
          let data = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to generate \(spec.name)\n", stderr)
        exit(1)
    }
    let url = appIconDir.appendingPathComponent(spec.name)
    try data.write(to: url)
    print("Wrote \(spec.name) (\(spec.side) px)")
}
