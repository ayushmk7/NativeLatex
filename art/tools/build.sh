#!/bin/sh
# Regenerates every SVG (gen.py), the AppIcon.appiconset PNGs, and preview exports.
set -eu
cd "$(dirname "$0")/../.."
python3 -I art/tools/gen.py
S=art/source; O=NativeLatex/Assets.xcassets/AppIcon.appiconset
R=$(mktemp -t libreweave-render)
trap 'rm -f "$R"' EXIT
swiftc -O art/tools/render.swift -o "$R"
# Flat app icon renditions (in-app NSImage "AppIcon"); the .icns and Dock icon come from AppIcon.icon.
for s in 16 32 128 256 512; do
  "$R" $S/app-icon-black.svg "$O/icon_${s}x${s}.png" $s
  "$R" $S/app-icon-black.svg "$O/icon_${s}x${s}@2x.png" $((s * 2))
done
for s in mark-black mark-white app-icon-black app-icon-white; do "$R" "$S/$s.svg" "art/exports/$s-512.png" 512; done
for s in switch-light switch-dark switch-light-focus; do "$R" "$S/$s.svg" "art/exports/$s@2x.png" "$(( $(sed -n 's/.*<svg[^>]*width="\([0-9]*\)".*/\1/p' "$S/$s.svg") * 2 ))"; done
