# LibreWeave brand art

LibreWeave is the working app name. The artwork has no words in it, so a rename only changes labels. Design brief: [art direction](../docs/workspaces/art/art-direction.md). Palette: ink `#0A0A0A`, paper `#FFFFFF`, royal blue `#4169E1` (`#8BA6FF` for the dark accent).

The icon is a woven sheet. The macOS silhouette is the paper, with no inner box or frame. White lines weave over and under two royal-blue threads.

| Path | What |
| --- | --- |
| `tools/gen.py` | Single source of the weave geometry. Writes every icon/mark SVG below and `../landing/icon.svg`. Edit here, not in the SVGs. |
| `source/app-icon-dark.svg` | 1024 master that ships in the app (black sheet) |
| `source/app-icon-dark-small.svg` | 16/32 px master: a 2×2 weave on the 16 px pixel grid |
| `source/app-icon-light*.svg` | White-sheet variants for the dark-page favicon and a future Icon Composer layer |
| `source/mark-black.svg`, `mark-white.svg` | One-color mark with transparent gaps |
| `source/switch-*.svg` | Appearance-switch stills: an original rolling robot; no BB-8 artwork or code copied |
| `exports/review.png` | Review sheet made from the actool-compiled `.icns` on light and dark grounds |
| `exports/*.png` | Other previews |
| `../NativeLatex/Assets.xcassets/AppIcon.appiconset` | Generated Mac icon: 16–512 pt at 1x and 2x |
| `../NativeLatex/Assets.xcassets/AccentColor.colorset` | App accent: `#4169E1` light, `#8BA6FF` dark |
| `../landing/icon.svg` | Favicon: black sheet on light pages, white sheet on dark pages, via `prefers-color-scheme` inside the SVG |

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
art/tools/build.sh      # gen.py → SVGs → PNGs (native macOS SVG renderer)
art/tools/validate.sh   # PNG sizes match Contents.json; actool compiles with no warnings
art/tools/review.sh     # actool → .icns → art/exports/review.png
swift art/tools/appearance-check.swift path/to/LibreLeaf.app   # icon colour under Aqua vs Dark Aqua
```

**One universal Mac icon.** A macOS `.appiconset` has no dark slot. actool drops `luminosity: dark` entries without any warning, and the built app shows the same icon in light and dark mode (verified 2026-11-17, Xcode 27.2, macOS 27.3). Adaptive light, dark, clear and tinted icons need an Icon Composer `.icon` file in the Xcode target. The app owners would have to add it; it is not needed for the app to run.
