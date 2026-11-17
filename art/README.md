# LibreWeave brand art

LibreWeave is the working app name. The artwork has no words in it, so a rename only changes labels. Design brief: [art direction](../docs/workspaces/art/art-direction.md). Palette: ink `#0A0A0A`, paper `#FFFFFF`, royal blue `#4169E1` (`#8BA6FF` for the dark accent).

The icon is a woven sheet. The macOS silhouette is the paper, with no inner box or frame. Two lines weave over and under two royal-blue threads.

| Appearance | Sheet | Lines |
| --- | --- | --- |
| Light | black | white |
| Dark | white | black |

The threads are royal blue in both.

**Clear and Tinted** are chosen by the user in macOS (icon & widget style), not by the app, and there is no in-app setting. The system builds them from the same `.icon`, using the `ISAppearanceTintable` stack. actool derives that stack from the default layers, because `icon.json` has no `tinted` (Mono) override; `assetutil` shows its group is identical to the Aqua group.
- **Clear:** the system replaces our fill with its own glass sheet. Lines go white, threads go mid-gray, so the weave stays three-toned (sheet < threads < lines).
- **Tinted:** the user's tint colour drives the sheet and threads.

We force no alpha, and the `.icon` has no Clear-specific settings. Evidence, 2026-11-17 (Xcode 27.2, macOS 27.3):
- **Fill, glass and translucency:** `tinted` fill specializations, layer `glass` and group `translucency` never changed the Clear sheet in `ictool` or IconServices. It stays 128 gray in Clear light and 44 in Clear dark.
- **Native comparison:** in static renders Clear is opaque for Apple's own Safari, Calculator, Maps and Notes icons too. The Dock adds live backdrop translucency itself.
- **Mono thread opacity:** lowering it under `tinted` would raise Tinted-dark contrast, but it fades the Clear threads into the sheet, so it was not applied.

| Path | What |
| --- | --- |
| `tools/gen.py` | Single source of the geometry. Writes every SVG below, the `.icon` layers and `../landing/icon.svg`. Edit here. |
| `../NativeLatex/AppIcon.icon` | **The app icon.** Icon Composer document in the LibreWeave target's Resources. Sheet colour comes from `fill-specializations`; `lines-white.svg` / `lines-black.svg` swap per appearance; `threads.svg` stays blue. |
| `../NativeLatex/Assets.xcassets/AccentColor.colorset` | App accent: `#4169E1` light, `#8BA6FF` dark |
| `source/app-icon-black.svg`, `app-icon-white.svg` | Flat icons on the macOS grid |
| `source/mark-black.svg`, `mark-white.svg` | One-color mark with real gaps |
| `../landing/icon.svg` | Favicon: black sheet on light pages, white sheet on dark pages, via `prefers-color-scheme` inside the SVG |
| `exports/review.png` | Review sheet (see below) |
| `exports/built-app-icons.png`, `built-app-evidence.txt` | Evidence from a real `xcodebuild` of LibreWeave.app: `Assets.car` renditions and IconServices renders at 16, 32 and 256 px |

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
