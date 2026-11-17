# LibreWeave brand art

LibreWeave is the working app name. The artwork has no words in it, so a rename only changes labels. Design brief: [art direction](../docs/workspaces/art/art-direction.md). Palette: ink `#0A0A0A`, paper `#FFFFFF`, royal blue `#4169E1` (`#8BA6FF` for the dark accent).

The icon is a woven sheet. The macOS silhouette is the paper, with no inner box or frame. Two lines weave over and under two royal-blue threads.

| Appearance | Sheet | Lines |
| --- | --- | --- |
| Light | black | white |
| Dark | white | black |

The threads are royal blue in both. macOS generates the tinted and clear variants.

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
1. Light appearance as macOS 26+ draws it (IconServices): 16 and 32 px zoomed, then 256 px
2. The same for dark appearance
3. Icon Composer renditions from `ictool`: Default, Dark, TintedLight, TintedDark, ClearLight, ClearDark
4. Legacy `AppIcon.icns` for macOS 14–25

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
art/tools/build.sh      # gen.py → SVGs + .icon layers; PNG previews in exports/
art/tools/validate.sh   # actool compiles catalog + .icon with no warnings; Aqua and DarkAqua stacks exist
art/tools/review.sh     # actool into a throwaway bundle → IconServices + ictool + .icns → exports/review.png
clang -fobjc-arc -framework AppKit art/tools/appearance-check.m -o /tmp/appearance-check
/tmp/appearance-check path/to/LibreWeave.app /tmp/icon   # light/dark renders of a built app, no system toggle
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
