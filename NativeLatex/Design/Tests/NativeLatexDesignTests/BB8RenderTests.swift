import AppKit
import SwiftUI
import XCTest
@testable import NativeLatexDesign

/// Renders the real BB-8 button style and checks its unframed edge and focus ring pixel by pixel.
@MainActor
final class BB8RenderTests: XCTestCase {
    private let em: CGFloat = 4.5, scale: CGFloat = 2
    private var inset: CGFloat { BB8ButtonStyle.ringInset }
    private var pillWidth: CGFloat { BB8Artwork.width * em }
    private var pillHeight: CGFloat { BB8Artwork.height * em }
    /// Drawn height in points; the bitmap rounds up, leaving a sub-pixel empty row at the bottom.
    private var contentHeight: CGFloat { BB8Artwork.headroom * em + pillHeight + inset }

    private func render(night: Bool, focused: Bool, dark: Bool) -> NSBitmapImageRep {
        let view = Button {} label: { EmptyView() }
            .buttonStyle(BB8ButtonStyle(night: night, em: em, focused: focused))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        var image: CGImage?
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance { image = renderer.cgImage }
        let rep = NSBitmapImageRep(cgImage: image!)
        if let dir = ProcessInfo.processInfo.environment["BB8_RENDER_DIR"] {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/bb8-\(dark ? "dark" : "light")-\(night ? "night" : "day")\(focused ? "-focus" : "").png"))
        }
        return rep
    }

    /// Pixel at a point in view coordinates (top-left origin).
    private func pixel(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> NSColor {
        rep.colorAt(x: Int(x * scale), y: Int(y * scale))!.usingColorSpace(.sRGB)!
    }

    /// Size in points.
    private func size(_ rep: NSBitmapImageRep) -> CGSize { CGSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale) }

    private func isBlue(_ c: NSColor) -> Bool { c.alphaComponent > 0.5 && c.blueComponent - c.redComponent > 0.25 }

    func testFocusRingIsCleanCapsuleInsideBoundsAndDoesNotShiftLayout() {
        for dark in [false, true] {
            for night in [false, true] {
                let label = "dark=\(dark) night=\(night)"
                let idle = render(night: night, focused: false, dark: dark)
                let focused = render(night: night, focused: true, dark: dark)
                XCTAssertEqual(size(idle), size(focused), "focus must not change layout, \(label)")
                // Toolbar items are 52pt tall; keep the control within that budget.
                XCTAssertLessThanOrEqual(size(focused).width, 60, label)
                XCTAssertLessThanOrEqual(size(focused).height, 52, label)

                let w = size(focused).width, h = contentHeight
                let ringTop = h - (pillHeight + 2 * inset), midY = h - inset - pillHeight / 2
                // Ring present at its leftmost/rightmost points and bottom, fully inside the bounds.
                XCTAssertTrue(isBlue(pixel(focused, 0.5, midY)), "ring left edge, \(label)")
                XCTAssertTrue(isBlue(pixel(focused, w - 0.5, midY)), "ring right edge, \(label)")
                XCTAssertTrue(isBlue(pixel(focused, w / 2, h - BB8ButtonStyle.ringWidth / 2)), "ring bottom edge, \(label)")
                // A capsule leaves its bounding-box corners empty (the old ring had square stubs).
                XCTAssertLessThan(pixel(focused, 0.5, ringTop + 1).alphaComponent, 0.1, "ring corner empty, \(label)")
                XCTAssertLessThan(pixel(focused, 0.5, h - 0.5).alphaComponent, 0.1, "ring corner empty, \(label)")
                // Unfocused: no ring at all.
                XCTAssertLessThan(pixel(idle, 0.5, midY).alphaComponent, 0.1, "no ring when idle, \(label)")
            }
        }
    }

    /// No outline: the pill's edge is the artwork itself, not a dark ring on light windows or a light one on dark.
    func testPillHasNoOutline() {
        for dark in [false, true] {
            for night in [false, true] {
                let rep = render(night: night, focused: false, dark: dark)
                let edge = pixel(rep, inset + 1, contentHeight - inset - pillHeight / 2)
                let brightness = (edge.redComponent + edge.greenComponent + edge.blueComponent) / 3
                XCTAssertGreaterThan(edge.alphaComponent, 0.5, "artwork reaches the edge, dark=\(dark) night=\(night)")
                XCTAssertTrue(brightness > 0.15 && brightness < 0.85 || edge.blueComponent - edge.redComponent > 0.1,
                              "edge is sky, not a black or white ring, dark=\(dark) night=\(night): \(edge)")
            }
        }
    }
}
