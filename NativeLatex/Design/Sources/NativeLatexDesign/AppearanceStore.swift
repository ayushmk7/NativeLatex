import AppKit
import SwiftUI

public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "Use System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// One app-wide appearance preference. Setting `mode` sets `NSApp.appearance`,
/// so every window, sheet, and menu changes together, and SwiftUI's
/// `colorScheme` reports the effective appearance everywhere.
@MainActor
public final class AppearanceStore: ObservableObject {
    public static let shared = AppearanceStore()
    static let defaultsKey = "appearanceMode"

    @Published public var mode: AppAppearance {
        didSet {
            defaults.set(mode.rawValue, forKey: Self.defaultsKey)
            apply()
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = AppAppearance(rawValue: defaults.string(forKey: Self.defaultsKey) ?? "") ?? .system
        apply()
    }

    /// BB-8 behavior: choose the opposite of what is on screen, as an explicit override.
    /// Pass the effective appearance (`colorScheme == .dark`), not `mode`.
    public func toggle(currentIsDark: Bool) {
        mode = currentIsDark ? .light : .dark
    }

    private func apply() {
        NSApplication.shared.appearance = switch mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// NativeLatex > Settings > Appearance.
public struct AppearanceSettingsView: View {
    @ObservedObject private var appearance = AppearanceStore.shared

    public init() {}

    public var body: some View {
        Form {
            Picker("Appearance", selection: $appearance.mode) {
                ForEach(AppAppearance.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
        }
        .padding(24)
        .frame(width: 320)
    }
}

/// View > Appearance with checked System / Light / Dark items.
public struct AppearanceCommands: Commands {
    @ObservedObject private var appearance = AppearanceStore.shared

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .toolbar) {
            Picker("Appearance", selection: $appearance.mode) {
                ForEach(AppAppearance.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
        }
    }
}
