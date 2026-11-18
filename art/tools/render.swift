// Rasterizes SVG sources with the native macOS SVG renderer.
// Usage: swift art/tools/render.swift <in.svg> <out.png> <pixels-wide>
import AppKit
let a = CommandLine.arguments
guard a.count == 4, let px = Int(a[3]), let svg = NSImage(contentsOf: URL(fileURLWithPath: a[1])) else {
    FileHandle.standardError.write("usage: render.swift in.svg out.png px\n".data(using: .utf8)!); exit(2)
}
let h = Int((Double(px) * svg.size.height / svg.size.width).rounded())
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: h, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: px, height: h)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.imageInterpolation = .high
svg.draw(in: NSRect(x: 0, y: 0, width: px, height: h))
NSGraphicsContext.current = nil
let srgb = rep.converting(to: .sRGB, renderingIntent: .default)!
try! srgb.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
