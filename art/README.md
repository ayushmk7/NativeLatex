# LibreWeave brand art

LibreWeave is the working app name. The artwork has no words in it, so a rename only changes labels. Design brief: [art direction](../docs/workspaces/art/art-direction.md). Palette: ink `#0A0A0A`, paper `#FFFFFF`, and the Internship blue from `Internship/frontend/src/style.css`:

| Internship token | Value | Use here |
| --- | --- | --- |
| `--accent` / `--fill`, light | `#0066CC` | blue on white; light `AccentColor` |
| `--fill`, dark | `#0071E3` | dark `AccentColor` (filled, white text) |
| `--accent`, dark | `#0A84FF` | blue on black |

The icon is a woven sheet. The macOS silhouette is the paper, with no inner box or frame. Two lines weave over and under two blue threads.

| Appearance | Sheet | Lines | Threads |
| --- | --- | --- | --- |
| Light | black | white | `#0A84FF` (5.43:1 on `#0A0A0A`) |
| Dark | white | black | `#0066CC` (5.57:1 on white) |

**Clear and Tinted** are chosen by the user in macOS, not by the app, and there is no in-app setting. In macOS 27, System Settings ▸ Appearance offers Icon & widget style (Default, Dark, Clear, Tinted) and a Liquid Glass slider that moves icons from clear to heavily tinted. LibreWeave follows both, with no opacity control of its own ([Apple: change Appearance settings on Mac](https://support.apple.com/en-euro/guide/mac-help/mchlp1225/27/mac/27)). The system builds them from the same `.icon`, using the `ISAppearanceTintable` stack.

There is no Mono (`tinted`) override: actool derives the tintable stack from the default layers. The system greys Mono layers by luminance, and `#0A84FF` lands between the Clear sheet and the white lines. The table shows sheet / threads brightness (0–255) in 1024 px `ictool` renders, lines are white:

| Mode | Royal `#4169E1` (old) | `#2438FF` + `#7A93FF` Mono override (old) | `#0A84FF`, no override (shipped) |
| --- | --- | --- | --- |
| Clear light | 128 / 180 | 128 / 203 | 128 / 185 |
| Clear dark | 44 / 125 | 43 / 161 | 43 / 133 |
| Tinted dark | 36 / 62 | 36 / 68 | 36 / 58 |

- **Clear:** the system replaces our fill with its own glass sheet. Lines go white, threads go mid-gray, so the weave stays three-toned (sheet < threads < lines).
- **Tinted:** the user's tint colour drives the sheet and threads. Tinted dark is the weakest mode, as before: clear at 32 px and up, soft at 16 px.

We force no alpha and set nothing Mono-specific. Evidence, 2026-11-17 (Xcode 27.2, macOS 27.3):
- **Fill, glass and translucency:** `tinted` fill specializations, layer `glass` and group `translucency` never changed the Clear sheet in `ictool` or IconServices. It stays 128 gray in Clear light and 44 in Clear dark.
- **Native comparison:** in static renders Clear is opaque for Apple's own Safari, Calculator, Maps and Notes icons too. The Dock adds live backdrop translucency itself.
- **Mono thread opacity:** lowering it under `tinted` fades the Clear threads into the sheet, so it is not used.

| Path | What |
| --- | --- |
| `tools/gen.py` | Single source of the geometry. Writes every SVG below, the `.icon` layers and `../landing/icon.svg`. Edit here. |
| `../NativeLatex/AppIcon.icon` | **The app icon.** Icon Composer document in the LibreWeave target's Resources. Sheet colour comes from `fill-specializations`. `lines-white.svg` / `lines-black.svg` and `threads-on-black.svg` / `threads-on-white.svg` swap per appearance. Clear/Tinted derive from the default layers. |
| `../NativeLatex/Assets.xcassets/AccentColor.colorset` | App accent: Internship fills `#0066CC` light, `#0071E3` dark (control fills with white text: 5.57:1 and 4.70:1, both AA, so no separate high-contrast entry). |
| `source/app-icon-black.svg`, `app-icon-white.svg` | Flat icons on the macOS grid |
| `source/mark-black.svg`, `mark-white.svg` | One-color mark with real gaps |
| `../landing/icon.svg` | Favicon: black sheet on light pages, white sheet on dark pages, via `prefers-color-scheme` inside the SVG |
| `exports/review.png` | Review sheet (see below) |
| `exports/built-app-icons.png`, `built-app-evidence.txt` | Evidence from a real `xcodebuild` of LibreWeave.app: `Assets.car` renditions and IconServices renders at 16, 32 and 256 px. Recorded with an earlier blue; it proves the appearance stacks, `review.png` shows current colours. |

`exports/review.png` rows:
One row per mode, each at 16 and 32 px (zoomed), then 256 px on a light and on a dark backdrop:
- light, dark, clear-light, clear-dark: IconServices renders of the compiled bundle
- tinted-light, tinted-dark: `ictool`
- legacy: `AppIcon.icns` for macOS 14–25

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
art/tools/build.sh      # gen.py → SVGs + .icon layers; PNG previews in exports/
art/tools/validate.sh   # actool compiles catalog + .icon with no warnings; Aqua, DarkAqua and Tintable stacks exist
art/tools/review.sh     # actool into a throwaway bundle → IconServices + ictool + .icns → exports/review.png
clang -fobjc-arc -framework AppKit art/tools/appearance-check.m -o /tmp/appearance-check
/tmp/appearance-check path/to/LibreWeave.app /tmp/icon   # light/dark/clear renders of a built app, no system toggle
```

**No `.appiconset`:** when `AppIcon.icon` exists, actool builds the Dock icon, the macOS 14–25 `.icns`, and the flat `AppIcon` renditions from it. Removing the old set left `AppIcon.icns` byte-identical. `Assets.car` changed only in those 7 flat renditions, which are now drawn from `.icon` instead, and no app code reads them.

**Appearance switch:** none here. The app and landing use the Website BB-8 (orange/gradient, Uiverse.io / Galahhad), an intentional exception to the palette; see the art direction.

**Requirements:**
- Xcode at `DEVELOPER_DIR`, for `actool`, `assetutil`, `ictool`, `swiftc` and `clang`
- `python3`
- ImageMagick `magick`, for `review.sh` only

**Testing appearances:** `appearance-check.m` uses private IconServices classes, so it is a dev check only and must never ship. It renders each appearance without changing the system setting. Two things don't work as a test:
- `NSWorkspace.icon(forFile:)` follows the system appearance and ignores per-process or drawing appearance.
- Toggling the system to Light for a few seconds still returned the cached dark icon.
