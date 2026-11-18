# NativeLatexDesign

SwiftUI design system for the Virgule Mac app (code paths keep the `NativeLatex` name; the app's entry point `LibreWeaveApp` and the `libreWeaveTheme()` modifier keep the earlier name on purpose). macOS 14+, Swift 6, no dependencies.

Sources of the look: the Internship tracker (`~/Downloads/Internship/frontend/src/style.css`: white/black and pill controls), the Website base blue `#2563EB`, and the website's BB-8 switch (`~/Downloads/Website/src/components/pro/opt4/bb8.css`). Rules come from `docs/workspaces/ux/ux-plan.md` → *Appearance and BB-8 control*.

## Integrate

Add `NativeLatex/Design` as a local package (Xcode → File → Add Package Dependencies → Add Local…), link `NativeLatexDesign`, then:

```swift
import NativeLatexDesign

@main
struct LibreWeaveApp: App {
    var body: some Scene {
        WindowGroup {
            WorkspaceShell(
                title: workspace.name, subtitle: workspace.rootFileName,
                buildState: build.state,                      // .idle .building .succeeded .failed .stale
                status: ShellStatus(errors: e, warnings: w, line: ln, column: col, lastBuild: .milliseconds(ms)),
                showPreview: $layout.showPreview, showPanel: $layout.showProblems,
                onBuild: build.run                            // toolbar Build, ⌘B
            ) {
                FileTree()                                    // sidebar (hideable, standard sidebar toggle)
            } editor: {
                VStack(spacing: 0) {
                    SourceTabBar(tabs: tabs, selection: $activeTab, onClose: close)
                    SourceTextView()                          // your NSTextView wrapper; use Theme.editorFont
                }
            } preview: {
                PDFPreview()                                  // PDFKit; keep real page colors
            } panel: {
                ProblemList(problems: problems) { reveal($0) } // sorted by severity, file, line
            }
        }
        .commands { AppearanceCommands() }                    // View > Appearance: System / Light / Dark
        Settings { AppearanceSettingsView() }                 // Settings > Appearance
    }
}
```

The shell already puts `BB8Toggle()` in the trailing toolbar. Use it alone elsewhere with `BB8Toggle(em: 4.5)` (the default).

## API

| Symbol | Purpose |
| --- | --- |
| `AppearanceStore.shared` | `mode: AppAppearance` (`.system` default, `.light`, `.dark`), persisted in `UserDefaults` key `appearanceMode`. Sets `NSApp.appearance`, so all windows, sheets and menus change together. `.system` sets it to `nil`, so macOS changes flow through live. `toggle(currentIsDark:)` picks the opposite of the effective appearance as an override. |
| `AppearanceSettingsView`, `AppearanceCommands` | Settings radio group; View menu picker with checkmarks. |
| `BB8Toggle(store:em:)` | Day/night switch. Shows the effective appearance and stays in sync across windows through `colorScheme`. Tab-focusable; the focus ring is a 2pt capsule in `accentText` drawn 4pt outside the pill, inside space the control always reserves, so focus never shifts or clips the toolbar item (about 56×37pt). Space toggles. VoiceOver: "Dark appearance, On/Off", hint "Use System is in Settings". Tooltip: "Switch to Light/Dark Appearance". Reduce Motion: the scene changes with no animation. Pressing tilts the head ±25°, as `:active` does in the CSS. |
| `BB8Artwork(night:pressed:em:)` | Stateless art for previews and tests. |
| `Theme` | Dynamic colors (`background`, `surface`, `foreground`, `secondary`, `line`, `accent`, `accentText`, `onAccent`, `error`, `warning`, `success`), spacing `s1…s6` (4–32), `controlHeight`, `editorFont`, `titleFont`, `captionFont`. Each color resolves per window appearance, with Increase Contrast variants. |
| `View.libreWeaveTheme()` | Root modifier: accent tint, foreground, background. |
| `PillButtonStyle(prominent:)` | Capsule button: hairline outline, or filled electric blue. |
| `WorkspaceShell` | Toolbar (sidebar · title/root · Build · status · preview · BB-8), sidebar, editor/preview `HSplitView`, resizable problems panel, status bar. Under 760 pt wide, the preview toggle swaps the preview in for the editor instead of squeezing two columns. |
| `BuildStatusBadge`, `StatusBar`, `SourceTabBar`, `ProblemList` | Usable on their own. State always appears as symbol plus text, never color alone. |

### Colors

| Token | Light | Dark |
| --- | --- | --- |
| background | `#FFFFFF` | `#000000` |
| surface | `#F5F5F7` | `#141416` |
| foreground | `#0A0A0A` | `#F5F5F7` |
| secondary | `#6E6E73` | `#98989D` |
| accent (fill, white text) | `#2563EB` (5.17:1) | `#2563EB` (5.17:1) |
| accentText | `#2563EB` (5.17:1 on white) | neutral `#F5F5F7` for small text |
| accent, Increase Contrast | `#2563EB` | `#2563EB` |
| accentText, Increase Contrast | neutral `#0A0A0A` | neutral `#FFFFFF` |

`#2563EB` is the only brand blue in every appearance. On black it is below 4.5:1 for small text, so small links and labels use neutral white while blue remains on fills, focus rings and larger accents. The Markdown preview CSS follows the same rule. Increase Contrast changes neutral text only. Increase Contrast is detected from the window appearance (`bestMatch` against the high-contrast names) or `NSWorkspace.accessibilityDisplayShouldIncreaseContrast`. The app sets its own accent with `.tint`, so a system accent override doesn't change the brand. BB-8 keeps its original orange and desert colors and has no outline: the artwork stands on its own, at 4.5em (a little larger than the first 4em toolbar version).

## Check

```sh
cd NativeLatex/Design
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test                                                  # 6 XCTest cases
swift run NativeLatexDesignDemo                             # Virgule sample window
swift run NativeLatexDesignDemo --snapshot "$PWD/Screenshots"  # optional snapshots (opens a window)
```

Tests cover: the store starts on Use System and leaves `NSApp.appearance` nil; toggle overrides persist and Use System clears the override; every token keeps 4.5:1 contrast in light, dark and both high-contrast appearances, including white on accent; the accent is always `#2563EB`; the Increase Contrast variants raise accent-text contrast (tested through `Swatch.resolve`, because `NSAppearance(named:)` cannot create high-contrast appearances); the BB-8 day and night renders differ; rendered BB-8 pixels show the sky reaching the pill edge with no dark or light outline, and a focus ring that is a clean capsule (empty bounding-box corners) within the control bounds, absent when unfocused, with no layout change on focus. Set `BB8_RENDER_DIR` to save those renders as PNGs.

Still to check by hand in the real app: VoiceOver reading, Full Keyboard Access, Reduce Motion, and switching macOS appearance while two windows are open.
