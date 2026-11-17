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

    /// Tokens resolve per appearance and keep WCAG AA (4.5:1) for text, including white text on the accent fill.
    func testTokensResolvePerAppearanceWithReadableContrast() {
        func resolve(_ name: String, _ appearance: NSAppearance.Name) -> NSColor {
            var out = NSColor.clear
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                out = Theme.swatches[name]!.nsColor.usingColorSpace(.sRGB)!
            }
            return out
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

        XCTAssertEqual(resolve("background", .aqua), NSColor.hex(0xFFFFFF, 1).usingColorSpace(.sRGB))
        XCTAssertEqual(resolve("background", .darkAqua), NSColor.hex(0x000000, 1).usingColorSpace(.sRGB))

        for appearance in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            let bg = resolve("background", appearance)
            for text in ["foreground", "secondary", "accentText", "error"] {
                XCTAssertGreaterThanOrEqual(contrast(resolve(text, appearance), bg), 4.5, "\(text) on background, \(appearance.rawValue)")
            }
            XCTAssertGreaterThanOrEqual(contrast(.white, resolve("accent", appearance)), 4.5, "white on accent, \(appearance.rawValue)")
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
