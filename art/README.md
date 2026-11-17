# LibreLeaf brand art

LibreLeaf is the working app name. The artwork has no words in it, so a rename only changes labels.

Design inputs: [art direction](../docs/workspaces/art/art-direction.md), concept A (source brace to typeset page). Palette: ink `#0A0A0A`, paper `#FFFFFF`, royal blue `#4169E1`.

| Path | What |
| --- | --- |
| `source/app-icon.svg` | 1024 master. Layers: `background`, `page`, `brace`. Uses Apple's macOS icon grid: 824 px body, 100 px inset, 185 px corner radius. |
| `source/app-icon-small.svg` | Heavier master for the 16 px and 32 px slots |
| `source/mark-black.svg`, `mark-white.svg` | One-color mark for About, help, and docs |
| `source/switch-*.svg` | Appearance-switch stills: light, dark, light with blue focus ring. Original rolling robot; no BB-8 artwork or code copied. |
| `exports/` | PNG previews of the marks and switch stills |
| `../NativeLatex/Assets.xcassets/AppIcon.appiconset` | Generated Mac icon: 16–512 pt at 1x and 2x |
| `../NativeLatex/Assets.xcassets/AccentColor.colorset` | App accent: `#4169E1` light, `#8BA6FF` dark. Matches Xcode's default `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`, so backend can keep that setting. |

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer art/tools/build.sh     # SVG → PNG via native macOS renderer
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer art/tools/validate.sh  # pixel sizes + clean actool compile
```

Not needed for the local app to run: an Icon Composer `.icon` for macOS 26 dark/clear/tinted icons, made from these same layers, and the increased-contrast switch still.
