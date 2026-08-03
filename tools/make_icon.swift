// make_icon.swift
// Renders the Multiterminal app icon (1024x1024 PNG) using AppKit drawing:
// an indigo→violet squircle with an abstract overlapping "layered panes" monogram.
//
// Usage: swift tools/make_icon.swift <output.png>
import AppKit

let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else {
    fatalError("no bitmap rep")
}
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
let gs = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gs

let full = NSRect(x: 0, y: 0, width: size, height: size)

// 1) Squircle background with indigo→violet gradient.
let corner = CGFloat(size) * 0.2237
let squircle = NSBezierPath(roundedRect: full, xRadius: corner, yRadius: corner)
let indigo = NSColor(srgbRed: 0.396, green: 0.420, blue: 0.902, alpha: 1) // #6557e6
let violet = NSColor(srgbRed: 0.580, green: 0.400, blue: 0.918, alpha: 1) // #9466ea
let deep   = NSColor(srgbRed: 0.208, green: 0.153, blue: 0.490, alpha: 1)
let bgGradient = NSGradient(colorsAndLocations: (indigo, 0.0),
                                            (violet, 0.55),
                                            (deep, 1.0))!
bgGradient.draw(in: squircle, angle: -65)

// 2) Abstract monogram: three overlapping rounded "panes", rotated diagonally.
func drawPane(center: NSPoint, side: CGFloat, alpha: CGFloat, angle: CGFloat) {
    let half = side / 2
    let paneRect = NSRect(x: center.x - half, y: center.y - half, width: side, height: side)
    let path = NSBezierPath(roundedRect: paneRect, xRadius: side * 0.26, yRadius: side * 0.26)

    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: center.x, yBy: center.y)
    t.rotate(byDegrees: angle)
    t.translateX(by: -center.x, yBy: -center.y)
    t.concat()
    NSColor(white: 1.0, alpha: alpha).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
}

// Soft outer glow behind the mark for depth.
let glowRect = NSRect(x: 200, y: 150, width: 624, height: 624)
let glow = NSBezierPath(roundedRect: glowRect, xRadius: 160, yRadius: 160)
NSColor(white: 1.0, alpha: 0.06).setFill()
glow.fill()

// Top (back) pane — large, mostly transparent, upper-left.
drawPane(center: NSPoint(x: 460, y: 600), side: 470, alpha: 0.28, angle: -12)
// Middle pane — solid.
drawPane(center: NSPoint(x: 515, y: 500), side: 400, alpha: 0.92, angle: -12)
// Front pane — solid, lower-right.
drawPane(center: NSPoint(x: 590, y: 392), side: 300, alpha: 1.0, angle: -12)

gs.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("no png")
}
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
