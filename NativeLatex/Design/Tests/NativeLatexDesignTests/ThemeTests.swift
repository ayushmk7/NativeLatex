import AppKit
import SwiftUI
import XCTest
@testable import NativeLatexDesign

@MainActor
final class ThemeTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "ThemeTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// Default is Use System: no app override, so macOS appearance changes flow through.
    func testStartsOnSystemAndLeavesAppAppearanceUnset() {
        let store = AppearanceStore(defaults: defaults())
        XCTAssertEqual(store.mode, .system)
        XCTAssertNil(NSApp.appearance)
    }

    /// BB-8 picks the opposite of the *effective* appearance, persists it, and Use System clears the override.
    func testToggleOverridesThenSystemRestores() {
        let d = defaults()
        let store = AppearanceStore(defaults: d)

        store.toggle(currentIsDark: false)
        XCTAssertEqual(store.mode, .dark)
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)
        XCTAssertEqual(AppearanceStore(defaults: d).mode, .dark, "override persists across launches")

        store.toggle(currentIsDark: true)
        XCTAssertEqual(store.mode, .light)
        XCTAssertEqual(NSApp.appearance?.name, .aqua)

        store.mode = .system
        XCTAssertNil(NSApp.appearance)
    }

    /// Tokens keep WCAG AA (4.5:1) for text in all four variants, including white on the accent fill,
    /// and the accent matches the shared brand tokens (Art AccentColor, Landing).
    /// `NSAppearance(named:)` can't create high-contrast appearances, so variants are tested via `resolve`.
    func testTokensKeepContrastAndMatchBrand() {
        func color(_ name: String, dark: Bool, hc: Bool) -> NSColor {
            Theme.swatches[name]!.resolve(isDark: dark, highContrast: hc).usingColorSpace(.sRGB)!
        }
        func luminance(_ color: NSColor) -> Double {
            let c = color.usingColorSpace(.sRGB)!
            return [c.redComponent, c.greenComponent, c.blueComponent].map { v -> Double in
                let v = Double(v); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }.enumerated().reduce(0) { $0 + $1.element * [0.2126, 0.7152, 0.0722][$1.offset] }
        }
        func contrast(_ a: NSColor, _ b: NSColor) -> Double {
            let (x, y) = (luminance(a), luminance(b)); return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        func hex(_ v: UInt32) -> NSColor { NSColor.hex(v, 1).usingColorSpace(.sRGB)! }

        // Internship UI palette.
        XCTAssertEqual(color("accent", dark: false, hc: false), hex(0x0066CC))
        XCTAssertEqual(color("accent", dark: true, hc: false), hex(0x0071E3))
        XCTAssertEqual(color("accentText", dark: false, hc: false), hex(0x0066CC))
        XCTAssertEqual(color("accentText", dark: true, hc: false), hex(0x0A84FF))

        for dark in [false, true] {
            for hc in [false, true] {
                let bg = color("background", dark: dark, hc: hc), label = "dark=\(dark) hc=\(hc)"
                for text in ["foreground", "secondary", "accentText", "error"] {
                    XCTAssertGreaterThanOrEqual(contrast(color(text, dark: dark, hc: hc), bg), 4.5, "\(text) on background, \(label)")
                }
                XCTAssertGreaterThanOrEqual(contrast(.white, color("accent", dark: dark, hc: hc)), 4.5, "white on accent, \(label)")
                if hc {
                    XCTAssertGreaterThan(contrast(color("accentText", dark: dark, hc: true), bg),
                                         contrast(color("accentText", dark: dark, hc: false), bg), "HC raises accent text contrast, \(label)")
                }
            }
        }

        // The dynamic color follows the drawing appearance.
        var light = NSColor.clear, darkBG = NSColor.clear
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { light = Theme.swatches["accentText"]!.nsColor.usingColorSpace(.sRGB)! }
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { darkBG = Theme.swatches["background"]!.nsColor.usingColorSpace(.sRGB)! }
        if !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            XCTAssertEqual(light, hex(0x0066CC))
            XCTAssertEqual(darkBG, hex(0x000000))
        }
    }

    /// The day and night BB-8 scenes render and differ.
    func testBB8RendersDistinctDayAndNight() throws {
        func png(_ night: Bool) throws -> Data {
            let renderer = ImageRenderer(content: BB8Artwork(night: night, em: 8))
            let image = try XCTUnwrap(renderer.nsImage)
            return try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:]))
        }
        let day = try png(false), night = try png(true)
        XCTAssertGreaterThan(day.count, 1000)
        XCTAssertNotEqual(day, night)
    }
}
