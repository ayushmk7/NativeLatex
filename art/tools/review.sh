#!/bin/sh
# Compiles the shipped catalog with actool, extracts the .icns, and writes art/exports/review.png:
# 16 and 32 px (nearest-neighbour zoom, then actual size), 128, and 1024 px on light and dark grounds.
# The Mac app has one universal icon: .appiconset dark entries are dropped by actool (see art/README.md).
set -eu
cd "$(dirname "$0")/../.."
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
xcrun actool NativeLatex/Assets.xcassets --compile "$W" --platform macosx --minimum-deployment-target 14.0 \
  --app-icon AppIcon --output-partial-info-plist "$W/i.plist" >/dev/null
iconutil -c iconset "$W/AppIcon.icns" -o "$W/i.iconset"
I="$W/i.iconset"; big=NativeLatex/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png
for bg in FFFFFF 1E1E1E; do
  magick -background "#$bg" \( "$I/icon_16x16.png" -filter point -resize 160x160 \) \( "$I/icon_16x16@2x.png" -filter point -resize 160x160 \) \
    "$I/icon_16x16.png" "$I/icon_16x16@2x.png" "$I/icon_128x128.png" \( "$big" -resize 256x256 \) \
    -gravity center +append -bordercolor "#$bg" -border 20 "$W/$bg.png"
done
magick "$W/FFFFFF.png" "$W/1E1E1E.png" -append art/exports/review.png
echo "wrote art/exports/review.png"
