// Asks macOS for a built app's icon under Aqua and Dark Aqua and prints the sheet colour each time.
// Same colour in both = one universal icon (expected: .appiconset has no macOS dark slot).
// Usage: swift art/tools/appearance-check.swift path/to/LibreLeaf.app
import AppKit
let path = CommandLine.arguments[1]
for name in [NSAppearance.Name.aqua, .darkAqua] {
    NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
        let px = 256
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: px, height: px)
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSWorkspace.shared.icon(forFile: path).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.current = nil
        let c = rep.colorAt(x: px * 16 / 100, y: px / 2)!  // on the sheet, left of the weave
        print(name.rawValue, String(format: "sheet rgb %.2f %.2f %.2f", c.redComponent, c.greenComponent, c.blueComponent))
    }
}
