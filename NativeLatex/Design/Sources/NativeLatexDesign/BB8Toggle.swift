import SwiftUI

/// Native port of the website's BB-8 day/night switch (Uiverse.io by Galahhad).
/// Geometry is kept in the CSS's `em` units; `em` sets the point size of one unit.
///
/// Shows the *effective* appearance. Clicking (or Space when focused) picks the
/// opposite appearance as an explicit app override; Use System lives in
/// Settings and View > Appearance.
public struct BB8Toggle: View {
    @ObservedObject private var store: AppearanceStore
    private let em: CGFloat

    @Environment(\.colorScheme) private var scheme
    @State private var night: Bool?
    @FocusState private var focused: Bool

    public init(store: AppearanceStore = .shared, em: CGFloat = 4) {
        self.store = store
        self.em = em
    }

    private var isDark: Bool { night ?? (scheme == .dark) }

    public var body: some View {
        Button(action: toggle) { EmptyView() }
            .buttonStyle(BB8ButtonStyle(night: isDark, em: em, focused: focused))
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.space) { toggle(); return .handled }
            // Follow changes made elsewhere: other windows, Settings, macOS while on Use System.
            .onChange(of: scheme, initial: true) { night = scheme == .dark }
            .help(isDark ? "Switch to Light Appearance" : "Switch to Dark Appearance")
            .accessibilityLabel("Dark appearance")
            .accessibilityValue(isDark ? "On" : "Off")
            .accessibilityHint("Use System is in Settings")
            .accessibilityAddTraits(.isToggle)
    }

    private func toggle() {
        night = !isDark // animate now; the window appearance follows
        store.toggle(currentIsDark: !isDark)
    }
}

struct BB8ButtonStyle: ButtonStyle {
    let night: Bool, em: CGFloat, focused: Bool

    /// Room kept around the pill for the focus ring, focused or not, so focus never shifts
    /// the toolbar layout and the ring is never clipped by the item's bounds.
    /// The artwork's headroom (1.8em) already covers the space above the pill.
    static let ringInset: CGFloat = 4, ringWidth: CGFloat = 2

    func makeBody(configuration: Configuration) -> some View {
        BB8Artwork(night: night, pressed: configuration.isPressed, em: em)
            .padding([.horizontal, .bottom], Self.ringInset)
            .overlay(alignment: .bottom) {
                // Landing: 3px ring in the blue-text token (#4169E1 light, #8BA6FF dark), offset from the pill.
                Capsule()
                    .strokeBorder(Theme.accentText, lineWidth: Self.ringWidth)
                    .frame(width: BB8Artwork.width * em + 2 * Self.ringInset,
                           height: BB8Artwork.height * em + 2 * Self.ringInset)
                    .opacity(focused ? 1 : 0)
            }
            .contentShape(Rectangle())
    }
}

/// Pure artwork, no state; previews and tests render it directly.
public struct BB8Artwork: View {
    static let width: CGFloat = 10.625, height: CGFloat = 5.625, headroom: CGFloat = 1.8

    let night: Bool, pressed: Bool, em: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    public init(night: Bool, pressed: Bool = false, em: CGFloat = 4) {
        self.night = night; self.pressed = pressed; self.em = em
    }

    /// Pill outline in the foreground token, like the landing's 2px ring; heavier with Increase Contrast.
    /// Without it the sky meets light and dark toolbars below 3:1.
    static func outlineWidth(_ contrast: ColorSchemeContrast) -> CGFloat { contrast == .increased ? 2.5 : 1.5 }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            scenery
                .frame(width: Self.width * em, height: Self.height * em, alignment: .topLeading)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.foreground, lineWidth: Self.outlineWidth(contrast)))
            robot
        }
        .frame(width: Self.width * em, height: Self.height * em, alignment: .topLeading)
        .padding(.top, Self.headroom * em)
        .accessibilityHidden(true)
    }

    // MARK: Scenery

    private var scenery: some View {
        ZStack(alignment: .topLeading) {
            // The CSS slides an 11.25em-tall gradient: lower half by day, upper half by night.
            LinearGradient(stops: [
                .init(color: .hex(0x2C4770), location: 0),
                .init(color: .hex(0x070E2B), location: 0.35),
                .init(color: .hex(0x628CAC), location: 0.5),
                .init(color: .hex(0x628CAC), location: 0.7),
                .init(color: .hex(0xA6C5D4), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(width: Self.width * em, height: 11.25 * em)
            .offset(y: night ? 0 : -5.625 * em)
            .animation(motion(0.4), value: night)

            ForEach(Array(Self.stars.enumerated()), id: \.offset) { index, group in
                ForEach(Array(group.points.enumerated()), id: \.offset) { _, p in
                    dot(group.size, .white)
                        .shadow(color: .white, radius: 0.063 * em)
                        .offset(x: p.x * em, y: (night ? p.y : p.y + Self.height - group.top) * em)
                }
                .animation(motion(0.2 + 0.1 * Double(index)), value: night)
            }

            // Twin suns set at night.
            dot(1.25, .white)
                .shadow(color: .hex(0xFDF4E1), radius: 0.438 * em)
                .at(6.25, night ? Self.height : 0.625, em)
                .animation(motion(0.4), value: night)
            Circle()
                .fill(LinearGradient(colors: [.hex(0xE6AC5C), .hex(0xD75449)], startPoint: .top, endPoint: .bottom))
                .frame(width: 1.25 * em, height: 1.25 * em)
                .at(8.125, night ? Self.height : 2.188, em)
                .animation(motion(0.7), value: night)

            // Three moons rise at night.
            moon(1.875).at(0.938, night ? 0.938 : Self.height, em).animation(motion(0.4), value: night)
            moon(0.625).at(3.438, night ? 2.5 : Self.height, em).animation(motion(0.6), value: night)
            moon(0.5).at(4.375, night ? 2.75 : Self.height, em).animation(motion(0.8), value: night)

            Rectangle() // desert floor
                .fill(Color.hex(0xB18D71))
                .frame(width: Self.width * em, height: 0.3 * Self.height * em)
                .offset(y: 0.7 * Self.height * em)

            Ellipse() // BB-8's shadow, skewed toward the light
                .fill(Color.hex(0x3A271C).opacity(0.25))
                .frame(width: 4.375 * em, height: 1.125 * em)
                .blur(radius: 0.4 * em)
                .at(night ? 6.563 : -0.313, 4.5, em)
                .animation(motion(0.4), value: night)

            ForEach(Array(Self.clouds.enumerated()), id: \.offset) { index, cloud in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(cloud.puffs.enumerated()), id: \.offset) { _, p in
                        Ellipse().fill(cloud.color)
                            .frame(width: 0.875 * em, height: cloud.h * em)
                            .offset(x: p.x * em, y: p.y * em)
                    }
                }
                .blur(radius: 0.125 * em)
                .at(cloud.x + (night ? Self.width : 0), cloud.y, em)
                .animation(motion(0.4 + 0.2 * Double(index)), value: night)
            }
        }
    }

    // MARK: Robot

    private var robot: some View {
        // CSS .bb8: head (2.5 x 1.688em) overlaps body (4.375em) by 0.188em; top sits 0.875em above the track.
        ZStack(alignment: .topLeading) {
            robotBody.offset(y: 1.5 * em)
            head
                .rotationEffect(.degrees(pressed ? (night ? -25 : 25) : 0), anchor: UnitPoint(x: 0.5, y: 3.75 / 1.688))
                .animation(motion(0.4), value: pressed)
                .offset(x: 0.9375 * em)
        }
        .at(night ? 5.625 : 0.625, -0.875, em)
        .animation(motion(0.4), value: night)
    }

    private var head: some View {
        let orange = Color.hex(0xDE7D2F), silver = Color.hex(0xC0C0C0), stroke = max(0.059 * em, 0.75)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(.white)
            band(0.063, 0.313, .hex(0x696969))
            band(0.375, 0.5, orange)
            band(1.313, 1.438, silver)
            ForEach(Array(Self.headDashes.enumerated()), id: \.offset) { _, d in
                Rectangle().fill(orange)
                    .frame(width: (d.1 - d.0) * em, height: 0.188 * em)
                    .offset(x: d.0 * em, y: 1.125 * em)
            }
            Circle().fill(.black) // main eye
                .overlay(Circle().fill(.red).frame(width: 0.125 * em).offset(x: -0.03 * em, y: 0.09 * em))
                .overlay(Circle().stroke(Color.hex(0xD3D3D3), lineWidth: 0.089 * em))
                .frame(width: 0.563 * em, height: 0.563 * em)
                .offset(x: (1.25 - 0.281) * em, y: 0.413 * em)
            Circle().fill(.black) // small eye
                .overlay(Circle().stroke(.white, lineWidth: 0.04 * em).padding(0.04 * em))
                .frame(width: 0.3 * em, height: 0.3 * em)
                .offset(x: (1.25 + 0.563 - 0.15) * em, y: (0.413 + 0.281 - 0.15 + 0.28) * em)
        }
        .frame(width: 2.5 * em, height: 1.688 * em)
        .clipShape(HeadShape())
        .shadow(color: .gray, radius: 0.1 * em, y: 0.063 * em)
        .background(alignment: .topLeading) { // antennas poke out of the dome
            Rectangle().fill(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.2), .init(color: silver, location: 0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: stroke, height: 0.938 * em)
                .offset(x: 1.503 * em, y: -0.844 * em)
            Rectangle().fill(silver)
                .frame(width: stroke, height: 0.375 * em)
                .offset(x: 1.22 * em, y: -0.3375 * em)
        }
    }

    private var robotBody: some View {
        let d: CGFloat = 4.375, orange = Color.hex(0xDE7D2F), ringGray = Color(white: 236 / 255)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(.white)
            // orange edge bands (vertical and horizontal), seen as arcs once clipped
            ForEach([0.04, 0.90], id: \.self) { start in
                Rectangle().fill(orange).frame(width: 0.06 * d * em, height: d * em).offset(x: start * d * em)
                Rectangle().fill(orange).frame(width: d * em, height: 0.06 * d * em).offset(y: start * d * em)
            }
            Rectangle().fill(Color.hex(0xC0C0C0)).frame(width: 0.063 * em, height: d * em).offset(x: 2.156 * em)
            Rectangle().fill(Color.hex(0xC0C0C0)).frame(width: d * em, height: 0.063 * em).offset(y: 2.156 * em)
            ForEach(Array(Self.bodyDots.enumerated()), id: \.offset) { _, p in
                dot(0.188, ringGray).offset(x: p.x * em, y: p.y * em)
            }
            // center hub: white disc, orange cross, gray core, orange ring
            ZStack {
                Circle().fill(.white)
                Rectangle().fill(orange).frame(width: 0.16 * 2.625 * em)
                Rectangle().fill(orange).frame(height: 0.16 * 2.625 * em)
                Circle().fill(.white).frame(width: 1.25 * em, height: 1.25 * em)
                Circle().fill(ringGray).frame(width: 1 * em, height: 1 * em)
                Circle().strokeBorder(orange, lineWidth: 0.313 * em)
            }
            .frame(width: 2.625 * em, height: 2.625 * em)
            .clipShape(Circle())
            .offset(x: (d - 2.625) / 2 * em, y: (d - 2.625) / 2 * em)
        }
        .frame(width: d * em, height: d * em)
        .clipShape(Circle())
        .rotationEffect(.degrees(night ? 225 : 45))
        .animation(motion(0.4), value: night)
    }

    // MARK: Helpers

    private func motion(_ seconds: Double) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: seconds)
    }

    private func dot(_ size: CGFloat, _ color: Color) -> some View {
        Circle().fill(color).frame(width: max(size * em, 1), height: max(size * em, 1))
    }

    private func band(_ top: CGFloat, _ bottom: CGFloat, _ color: Color) -> some View {
        Rectangle().fill(color).frame(width: 2.5 * em, height: (bottom - top) * em).offset(y: top * em)
    }

    private func moon(_ size: CGFloat) -> some View {
        Circle()
            .fill(LinearGradient(colors: [.white, .hex(0x6E8EA2)], startPoint: .top, endPoint: .bottom))
            .frame(width: size * em, height: size * em)
            .shadow(color: .white.opacity(0.32), radius: 0.188 * em)
    }

    // MARK: Data straight from bb8.css (positions in em, night state)

    struct StarGroup { let top: CGFloat, size: CGFloat, points: [CGPoint] }
    static let stars: [StarGroup] = {
        func g(_ left: CGFloat, _ top: CGFloat, _ size: CGFloat, _ shadows: [(CGFloat, CGFloat)]) -> StarGroup {
            StarGroup(top: top, size: size, points: ([(0, 0)] + shadows).map { CGPoint(x: left + $0.0, y: top + $0.1) })
        }
        return [
            g(3.75, 0.625, 0.063, [(1.25, 0.938), (-1.25, 2.5), (0, 1.25), (1.875, 0.625), (-3.125, 1.875), (1.25, 2.813)]),
            g(4.688, 1.875, 0.063, [(0.625, 0), (0, 0.625), (-0.625, -0.625), (0.625, 0.938), (-3.125, 1.25), (1.25, -1.563)]),
            g(5.313, 1.25, 0.063, [(-0.625, -0.625), (-2.188, 1.25), (-2.188, 0), (-3.75, -0.625), (-3.125, -0.625), (-2.5, -0.313), (0.75, -0.625)]),
            g(1.875, 3.438, 0.125, []),
            g(5, 3.438, 0.125, []),
            g(2.5, 0.313, 0.125, []),
            g(3.438, 1.875, 0.125, []),
        ]
    }()

    struct Cloud { let x: CGFloat, y: CGFloat, h: CGFloat, color: Color, puffs: [CGPoint] }
    static let clouds: [Cloud] = [
        Cloud(x: 7.875, y: 2.813, h: 0.625, color: .white.opacity(0.85),
              puffs: [.zero, CGPoint(x: 0.313, y: 0.313), CGPoint(x: -0.625, y: 0), CGPoint(x: -0.938, y: -0.125)]),
        Cloud(x: 5.375, y: 0.625, h: 0.375, color: .hex(0xDFDEDE).opacity(0.75),
              puffs: [.zero, CGPoint(x: -0.313, y: -0.188), CGPoint(x: -0.625, y: -0.188), CGPoint(x: -1, y: 0.063)]),
        Cloud(x: 8.812, y: 1.25, h: 0.375, color: .white.opacity(0.75),
              puffs: [.zero, CGPoint(x: 0.438, y: 0.188), CGPoint(x: -0.625, y: 0.313)]),
    ]

    static let headDashes: [(CGFloat, CGFloat)] = [
        (0, 0.125), (0.188, 0.313), (0.375, 0.938), (1, 1.125), (1.875, 2), (2.063, 2.25), (2.313, 2.375), (2.438, 2.5),
    ]

    static let bodyDots: [CGPoint] = {
        let base = CGPoint(x: 0.563, y: 4.375 - 1.5 - 0.188)
        let offsets: [(CGFloat, CGFloat)] = [(0, 0), (0.875, 0.938), (0, -1.25), (0.875, -2.125), (2.125, -2.125), (3.063, -1.25), (3.063, 0), (2.125, 0.938)]
        return offsets.map { CGPoint(x: base.x + $0.0, y: base.y + $0.1) }
    }()
}

/// Dome with chamfered lower corners (the CSS builds it from 45° gradients).
struct HeadShape: Shape {
    func path(in r: CGRect) -> Path {
        let radius = r.width / 2, shoulder = r.height * 1.25 / 1.688, chamfer = r.width * 0.075
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addArc(center: CGPoint(x: r.midX, y: r.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + shoulder))
        p.addLine(to: CGPoint(x: r.maxX - chamfer, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + chamfer, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + shoulder))
        p.closeSubpath()
        return p
    }
}

extension Color {
    static func hex(_ v: UInt32) -> Color { Color(nsColor: .hex(v, 1)) }
}

private extension View {
    func at(_ x: CGFloat, _ y: CGFloat, _ em: CGFloat) -> some View {
        offset(x: x * em, y: y * em)
    }
}

#Preview("BB-8 day / night") {
    HStack(spacing: 24) {
        BB8Artwork(night: false, em: 8)
        BB8Artwork(night: true, em: 8)
    }
    .padding(24)
}
