# Virgule brand art

Virgule is the candidate app name. It has not been cleared as a trademark (see the [coordinator plan](../docs/virgule-rebrand-plan.md)). The artwork has no words in it. Design brief: [art direction](../docs/workspaces/art/art-direction.md). Palette: ink `#0A0A0A`, paper `#FFFFFF`, and one brand blue, `#2563EB`, in every appearance. There are no other blue variants.

The icon is a single slash (a virgule): one stroke with rounded caps at about 70°, drawn from scratch in `tools/gen.py` rather than taken from a font. The macOS silhouette is the only container. There is no inner box, frame, page or backing shape, and the slash stays clear of the sheet edge.

| Appearance | Sheet | Slash |
| --- | --- | --- |
| Light | white | `#2563EB` (5.17:1) |
| Dark | `#0A0A0A` | `#2563EB` (3.8:1, above the 3:1 graphics minimum) |
| Clear light / dark | system glass | white (Mono) |
| Tinted light / dark | user tint | white, tinted by the system (Mono) |

**Geometry (1024 grid, 824 body at a 100 inset):** centreline from (604, 262) to (420, 762), stroke 176 px. That is 2.75 px at 16 px. Treatments compared on 2026-11-18 in Icon Composer renders (row of luma across the stroke at 16 px):
- 150 px: two full pixels plus weak edges (66, 48 in Tinted dark). It reads, but the edge is the softest.
- **176 px (chosen):** two full pixels plus stronger edges (78, 61).
- 200 px: three full pixels, but at 512 px it reads as a pill rather than a slash.

**Clear and Tinted** are chosen by the user in macOS, not by the app, and there is no in-app setting. Both come from the `ISAppearanceTintable` stack. The Mono (`tinted`) override uses `slash-white.svg` on an ink sheet. A lone blue element greys into the sheet there, which was measured with the former icon.

Measured by `tools/review.sh` on the compiled catalog (sRGB, 0–255; "diff" is slash luma minus sheet luma). The value is the same at 16, 32, 256 and 512 px unless a range is shown:

| Mode | Sheet | Slash | Result | Gate |
| --- | --- | --- | --- | --- |
| Light | 255 | 37, 98, 235 | 5.2:1 | ≥ 4.5:1; `#2563EB` ±4 at 256+ |
| Dark | 10 | 37, 98, 235 | 3.8:1 | ≥ 3:1; `#2563EB` ±4 at 256+ |
| Clear light | 128 | 254 | diff 126 | ≥ 60 |
| Clear dark | 43 | 242 | diff 199 | ≥ 60 |
| Tinted light | 113, 89, 207 | 252, 248, 255 | diff 147 | ≥ 50 |
| Tinted dark | 34, 30, 43 | 96–97, 65–67, 177–181 | diff 48–50 | ≥ 45 |
| Legacy `.icns` | 255 | 37, 99, 235 | 5.2:1 | as Light |

- **Tinted dark is the weakest mode and is at the system ceiling.** The system tints a pure white Mono glyph to about 50 above its sheet. In `ictool`, layer glass, group specular and a black Mono fill all left it at sheet 32 / slash 82 (luma), so no layer setting can raise it. The former icon's white lines measured the same. The gate is 45 so it catches any regression from full white. The planned gate of 50 cannot be met by any white glyph.
- **Clear is a regression check, not proof.** Static renders flatten Clear onto a fixed neutral glass (128 / 43). In the live Dock, macOS composites the wallpaper behind the glass, and a bright wallpaper lightens the sheet behind a white slash. Checking that requires the app in the Dock over light and grey wallpapers. It has not been done, because it changes the owner's desktop.

| Path | What |
| --- | --- |
| `tools/gen.py` | Single source. Writes every SVG below, `AppIcon.icon` (layers and `icon.json`) and `../landing/icon.svg`. Edit here, then run `build.sh`. |
| `../NativeLatex/AppIcon.icon` | **The app icon.** One group with one layer, `slash`: `slash-blue.svg` for Light and Dark, `slash-white.svg` for Mono. The sheet comes from `fill-specializations`. No glass, shadow, specular or translucency. |
| `../NativeLatex/Assets.xcassets/AccentColor.colorset` | App accent: `#2563EB`, one universal value. Unchanged. |
| `source/app-icon-white.svg`, `app-icon-black.svg` | Flat icons on the macOS grid. One `<rect>` (the sheet) plus the slash. |
| `source/mark-black.svg`, `mark-white.svg`, `mark-blue.svg` | The slash alone, cropped to its bounds, with no backing shape |
| `../landing/icon.svg` | Favicon, same as the app icon: white sheet on light pages, ink sheet on dark pages (`prefers-color-scheme` inside the SVG), `aria-label="Virgule"` |
| `exports/*-512.png` | Previews of the sources above |
| `exports/review.png` | One row per mode: 16 and 32 px zoomed, then 256 px on light and dark backdrops |
| `exports/built-app-evidence.txt` | `assetutil` stacks, Info.plist icon keys and IconServices samples from a real `xcodebuild` Release app |

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
art/tools/build.sh             # gen.py → SVGs, .icon, favicon; PNG previews in exports/
art/tools/validate.sh          # committed files == gen.py output; actool clean; Aqua, DarkAqua, Tintable stacks
art/tools/review.sh [dir]      # throwaway bundle → IconServices + ictool + .icns, gates, exports/review.png
clang -fobjc-arc -framework AppKit art/tools/appearance-check.m -o /tmp/appearance-check
/tmp/appearance-check path/to/App.app /tmp/icon   # light/dark/clear renders of a built app, no system toggle
```

**actool paths must be absolute.** actool hands its inputs to a shared `ibtoold` daemon that resolves relative paths against the daemon's own working directory. On 2026-11-18 that directory was a sibling worktree, so a relative `NativeLatex/AppIcon.icon` silently compiled that worktree's old icon. The scripts pass `$PWD/...`. Xcode builds already use absolute paths.

**No word mark.** The landing header keeps live text. An outlined SF Pro wordmark is not used, because its licence for logo use is unsettled. If a lockup is needed, use an openly licensed face (for example, Inter under the SIL OFL) and keep the name separate from the icon geometry.

**Appearance switch:** none here. The app and landing use the Website BB-8 (orange/gradient, Uiverse.io / Galahhad), an intentional exception to the palette; see the art direction.

**Former brand:** LibreWeave's woven icon is preserved at the local tag `art-libreweave-weave`. To roll back: `git checkout art-libreweave-weave -- art NativeLatex/AppIcon.icon landing/icon.svg docs/workspaces/art/art-direction.md`, delete `AppIcon.icon/Assets/slash-*.svg`, then run `build.sh` and `validate.sh`.

**Requirements:** Xcode at `DEVELOPER_DIR` (`actool`, `assetutil`, `ictool`, `swiftc`, `clang`), `python3`, and ImageMagick `magick` for `review.sh`.

**Testing appearances:** `appearance-check.m` uses private IconServices classes, so it is a dev check only and must never ship. `NSWorkspace.icon(forFile:)` follows the system appearance and caches, so it is not a test.
