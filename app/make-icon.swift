// Renders the 1024×1024 app icon: an external drive with a pencil badge on a blue squircle.
// Usage: swift make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt body centred in 1024 with a soft shadow.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [NSColor(red: 0.20, green: 0.55, blue: 1.00, alpha: 1),
                    NSColor(red: 0.05, green: 0.27, blue: 0.80, alpha: 1)])!
    .draw(in: shape, angle: -90)

func symbol(_ name: String, points: CGFloat, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: points, weight: .semibold)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

let drive = symbol("externaldrive.fill", points: 430, color: .white)
drive.draw(in: NSRect(x: (size - drive.size.width) / 2, y: (size - drive.size.height) / 2 + 40,
                      width: drive.size.width, height: drive.size.height))

// Pencil badge: "this drive is writable".
let badge = NSRect(x: 590, y: 200, width: 270, height: 270)
NSColor(red: 0.20, green: 0.80, blue: 0.40, alpha: 1).setFill()
NSBezierPath(ovalIn: badge).fill()
let pencil = symbol("pencil", points: 150, color: .white)
pencil.draw(in: NSRect(x: badge.midX - pencil.size.width / 2, y: badge.midY - pencil.size.height / 2,
                       width: pencil.size.width, height: pencil.size.height))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
