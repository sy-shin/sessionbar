import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),
    ("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),
    ("icon_512x512",512),("icon_512x512@2x",1024)]
for (name, size) in sizes {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 194, yRadius: 194)
    NSGradient(starting: NSColor(calibratedRed: 0.06, green: 0.1, blue: 0.17, alpha: 1),
               ending: NSColor(calibratedRed: 0.09, green: 0.17, blue: 0.23, alpha: 1))!.draw(in: background, angle: 45)
    let terminal = NSBezierPath(roundedRect: NSRect(x: 220, y: 282, width: 580, height: 462), xRadius: 64, yRadius: 64)
    NSColor(calibratedRed: 0.80, green: 0.86, blue: 0.92, alpha: 1).setStroke(); terminal.lineWidth = 24; terminal.stroke()
    let prompt = NSBezierPath(); prompt.move(to: NSPoint(x: 330, y: 610)); prompt.line(to: NSPoint(x: 442, y: 510)); prompt.line(to: NSPoint(x: 330, y: 410))
    prompt.lineWidth = 44; prompt.lineCapStyle = .round; prompt.lineJoinStyle = .round
    NSColor(calibratedRed: 0.38, green: 0.65, blue: 0.98, alpha: 1).setStroke(); prompt.stroke()
    let underscore = NSBezierPath(); underscore.move(to: NSPoint(x: 545, y: 410)); underscore.line(to: NSPoint(x: 690, y: 410))
    underscore.lineWidth = 44; underscore.lineCapStyle = .round
    NSColor(calibratedRed: 0.20, green: 0.83, blue: 0.60, alpha: 1).setStroke(); underscore.stroke()
    let badge = NSBezierPath(ovalIn: NSRect(x: 730, y: 680, width: 124, height: 124))
    NSColor(calibratedRed: 0.98, green: 0.75, blue: 0.14, alpha: 1).setFill(); badge.fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appending(path: name + ".png"))
}
