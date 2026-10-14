#!/usr/bin/env swift
// Generates Resources/AppIcon.icns. Run from the repository root: swift scripts/make-icon.swift
import AppKit

let root = FileManager.default.currentDirectoryPath
let iconset = "\(root)/.build/AppIcon.iconset"
let output = "\(root)/Resources/AppIcon.icns"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let ctx = graphics.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.32).cgColor)
    color(0x6C58CC).setFill()
    shape.fill()
    ctx.restoreGState()

    ctx.saveGState()
    shape.addClip()
    NSGradient(starting: color(0x9A88F0), ending: color(0x5642B8))!.draw(in: tile, angle: -90)
    NSGradient(starting: NSColor.white.withAlphaComponent(0.18), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
    ctx.restoreGState()

    // Three linked notes: the knowledge-graph mark.
    let center = CGPoint(x: 500, y: 520)
    let nodes: [(CGPoint, CGFloat)] = [(CGPoint(x: 330, y: 340), 56), (CGPoint(x: 705, y: 380), 56), (CGPoint(x: 610, y: 735), 50)]
    NSColor.white.withAlphaComponent(0.92).setStroke()
    for (point, _) in nodes {
        let line = NSBezierPath()
        line.move(to: center)
        line.line(to: point)
        line.lineWidth = 30
        line.lineCapStyle = .round
        line.stroke()
    }
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 92, y: center.y - 92, width: 184, height: 184)).fill()
    for (point, radius) in nodes {
        NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).fill()
    }
    color(0xF5B88D).setFill()
    NSBezierPath(ovalIn: NSRect(x: 705 - 30, y: 380 - 30, width: 60, height: 60)).fill()
    color(0x6C58CC).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(atPath: "\(root)/Resources", withIntermediateDirectories: true)
for (name, pixels) in entries {
    try render(pixels: pixels).write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset, "-o", output]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output)")
