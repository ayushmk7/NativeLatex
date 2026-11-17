import AppKit
import SwiftUI

/// Design tokens: paper-white / near-black with one royal-blue accent.
/// Every color is a dynamic `NSColor`, so it follows the window's effective
/// appearance (including Increase Contrast) without SwiftUI environment plumbing.
public enum Theme {
    /// Hex values per appearance: (light, dark, light high contrast, dark high contrast).
    struct Swatch: Sendable {
        let light: UInt32, dark: UInt32, lightHC: UInt32, darkHC: UInt32
        var lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1

        init(_ light: UInt32, _ dark: UInt32, hc: (UInt32, UInt32)? = nil, alpha: (CGFloat, CGFloat) = (1, 1)) {
            self.light = light; self.dark = dark
            lightHC = hc?.0 ?? light; darkHC = hc?.1 ?? dark
            lightAlpha = alpha.0; darkAlpha = alpha.1
        }

        var nsColor: NSColor {
            NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
                return switch match {
                case .darkAqua?: .hex(dark, darkAlpha)
                case .accessibilityHighContrastAqua?: .hex(lightHC, 1)
                case .accessibilityHighContrastDarkAqua?: .hex(darkHC, 1)
                default: .hex(light, lightAlpha)
                }
            }
        }
    }

    static let swatches: [String: Swatch] = [
        "background": Swatch(0xFFFFFF, 0x000000),
        "surface": Swatch(0xF5F5F7, 0x141416, hc: (0xEDEDF0, 0x1C1C1E)),
        "foreground": Swatch(0x0A0A0A, 0xF5F5F7, hc: (0x000000, 0xFFFFFF)),
        "secondary": Swatch(0x6E6E73, 0x98989D, hc: (0x3A3A3C, 0xC7C7CC)),
        // ponytail: alpha only for normal contrast; HC swaps to opaque greys.
        "line": Swatch(0x000000, 0xFFFFFF, hc: (0x8E8E93, 0x8E8E93), alpha: (0.10, 0.14)),
        // Royal blue. Light: #2F55D4 (6.2:1 on white, both as text and as fill).
        // Dark: fill is true royal blue #4169E1 (4.9:1 with white text); text uses #7E9BFF (8:1 on black).
        "accent": Swatch(0x2F55D4, 0x4169E1, hc: (0x1E3FB8, 0x5B7CFF)),
        "accentText": Swatch(0x2F55D4, 0x7E9BFF, hc: (0x1E3FB8, 0xA3B8FF)),
        "error": Swatch(0xD70015, 0xFF453A),
        "warning": Swatch(0xB25000, 0xFF9F0A),
        "success": Swatch(0x1A7F37, 0x30D158),
    ]

    static func color(_ name: String) -> Color { Color(nsColor: swatches[name]!.nsColor) }

    public static let background = color("background")
    /// Sidebars, panels, header rows.
    public static let surface = color("surface")
    public static let foreground = color("foreground")
    public static let secondary = color("secondary")
    /// Hairline borders and dividers.
    public static let line = color("line")
    /// Filled accent (selection, primary buttons, focus ring). Text on it is always white.
    public static let accent = color("accent")
    /// Accent used as text/icon on `background`.
    public static let accentText = color("accentText")
    public static let onAccent = Color.white
    public static let error = color("error")
    public static let warning = color("warning")
    public static let success = color("success")

    // Spacing scale (Internship tracker): 4 8 12 16 24 32.
    public static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s5: CGFloat = 24, s6: CGFloat = 32
    /// One control height for pills/buttons.
    public static let controlHeight: CGFloat = 28

    public static let editorFont = Font.system(size: 13, design: .monospaced)
    public static let titleFont = Font.system(size: 13, weight: .semibold)
    public static let captionFont = Font.system(size: 11, weight: .medium)
}

extension NSColor {
    static func hex(_ v: UInt32, _ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }
}

public extension View {
    /// Apply once at the window root: brand tint, background, and foreground.
    func libreLeafTheme() -> some View {
        tint(Theme.accent)
            .foregroundStyle(Theme.foreground)
            .background(Theme.background)
    }
}

/// Capsule button matching the web tracker: hairline outline, or filled royal blue when `prominent`.
public struct PillButtonStyle: ButtonStyle {
    var prominent: Bool
    public init(prominent: Bool = false) { self.prominent = prominent }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: Theme.controlHeight)
            .foregroundStyle(prominent ? Theme.onAccent : Theme.foreground)
            .background(prominent ? Theme.accent : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(prominent ? .clear : Theme.line))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
