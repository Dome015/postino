import AppKit
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let rect = NSRect(x: 64, y: 64, width: 896, height: 896)
let square = NSBezierPath(roundedRect: rect, xRadius: 202, yRadius: 202)
NSGradient(colors: [NSColor(calibratedRed: 0.43, green: 0.39, blue: 0.98, alpha: 1), NSColor(calibratedRed: 0.19, green: 0.27, blue: 0.72, alpha: 1)])!.draw(in: square, angle: -70)
NSColor.white.withAlphaComponent(0.18).setStroke(); square.lineWidth = 3; square.stroke()
let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 310, y: 310)); arrow.line(to: NSPoint(x: 710, y: 710)); arrow.move(to: NSPoint(x: 395, y: 710)); arrow.line(to: NSPoint(x: 710, y: 710)); arrow.line(to: NSPoint(x: 710, y: 395)); arrow.lineWidth = 78; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor.white.setStroke(); arrow.stroke()
let dot = NSBezierPath(ovalIn: NSRect(x: 270, y: 584, width: 90, height: 90)); NSColor.white.withAlphaComponent(0.4).setFill(); dot.fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
