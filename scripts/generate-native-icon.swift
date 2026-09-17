import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { exit(2) }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(3) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 230, yRadius: 230)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.32)
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
tile.fill()
NSGraphicsContext.current?.restoreGraphicsState()

let gradient = NSGradient(colors: [
    NSColor(calibratedWhite: 0.22, alpha: 1),
    NSColor(calibratedWhite: 0.08, alpha: 1),
    NSColor(calibratedWhite: 0.00, alpha: 1)
])!
gradient.draw(in: tile, angle: -45)

NSColor(calibratedWhite: 1, alpha: 0.98).setFill()
let heights: [CGFloat] = [160, 270, 390, 520, 390, 270, 160]
let barWidth: CGFloat = 38
let gap: CGFloat = 38
let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
for (index, height) in heights.enumerated() {
    let x = (CGFloat(size) - totalWidth) / 2 + CGFloat(index) * (barWidth + gap)
    let y = (CGFloat(size) - height) / 2
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidth, height: height), xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
}

NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(4) }
try data.write(to: output, options: .atomic)
