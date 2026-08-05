// make_icon.swift
// Renders the Multiterminal app icon (1024x1024 PNG) using AppKit drawing:
// a black terminal canvas with a composed pane frame and a high-contrast prompt mark.
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

// 1) Squircle background with a black / forest gradient.
let corner = CGFloat(size) * 0.2237
let squircle = NSBezierPath(roundedRect: full, xRadius: corner, yRadius: corner)
let forest = NSColor(srgbRed: 0.063, green: 0.102, blue: 0.086, alpha: 1) // #101a16
let green  = NSColor(srgbRed: 0.110, green: 0.290, blue: 0.251, alpha: 1) // #1c4a40
let deep   = NSColor(srgbRed: 0.024, green: 0.039, blue: 0.031, alpha: 1) // #060a08
let bgGradient = NSGradient(colorsAndLocations: (forest, 0.0),
                                            (green, 0.55),
                                            (deep, 1.0))!
bgGradient.draw(in: squircle, angle: -65)

// 2) Quiet glow behind the mark.
let glow = NSBezierPath(ovalIn: NSRect(x: 176, y: 168, width: 672, height: 672))
NSColor(srgbRed: 0.47, green: 0.80, blue: 0.75, alpha: 0.12).setFill()
glow.fill()

// 3) Composed pane frame: one outer boundary, two internal axes, one prompt.
let frame = NSBezierPath(roundedRect: NSRect(x: 196, y: 228, width: 632, height: 568),
                         xRadius: 92, yRadius: 92)
frame.lineWidth = 30
NSColor(white: 1.0, alpha: 0.15).setStroke()
frame.stroke()

let axes = NSBezierPath()
axes.move(to: NSPoint(x: 512, y: 262))
axes.line(to: NSPoint(x: 512, y: 762))
axes.move(to: NSPoint(x: 230, y: 512))
axes.line(to: NSPoint(x: 794, y: 512))
axes.lineWidth = 18
NSColor(white: 1.0, alpha: 0.10).setStroke()
axes.stroke()

let prompt = NSBezierPath()
prompt.move(to: NSPoint(x: 338, y: 434))
prompt.line(to: NSPoint(x: 464, y: 540))
prompt.line(to: NSPoint(x: 338, y: 646))
prompt.lineWidth = 46
prompt.lineCapStyle = .round
prompt.lineJoinStyle = .round
NSColor(white: 1.0, alpha: 0.98).setStroke()
prompt.stroke()

let cursor = NSBezierPath(roundedRect: NSRect(x: 532, y: 620, width: 176, height: 46),
                          xRadius: 23, yRadius: 23)
NSColor(srgbRed: 0.47, green: 0.80, blue: 0.75, alpha: 1.0).setFill()
cursor.fill()

gs.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("no png")
}
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
