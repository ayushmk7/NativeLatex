#!/bin/sh
# Compiles the real catalog + AppIcon.icon with actool into a throwaway LibreWeave bundle and writes
# art/exports/review.png. One row per macOS icon mode; columns: 16 and 32 px (nearest-neighbour zoom),
# then 256 px on a light backdrop and on a dark backdrop.
#   Light, Dark, Clear light, Clear dark: what macOS draws for the bundle (IconServices, appearance-check.m)
#   Tinted light, Tinted dark:            Icon Composer renditions (ictool)
#   Legacy:                               AppIcon.icns for macOS 14-25
# Clear is flattened onto the system's neutral glass here; the Dock composites live translucency itself.
set -eu
cd "$(dirname "$0")/../.."
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
B="$W/LibreWeave.app/Contents"; mkdir -p "$B/Resources"
xcrun actool NativeLatex/Assets.xcassets NativeLatex/AppIcon.icon --compile "$B/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist "$W/i.plist" >/dev/null
plutil -create xml1 "$B/Info.plist"
plutil -insert CFBundleIdentifier -string app.libreweave.review "$B/Info.plist"
plutil -insert CFBundleIconName -string AppIcon "$B/Info.plist"
plutil -insert CFBundleIconFile -string AppIcon "$B/Info.plist"
clang -fobjc-arc -framework AppKit art/tools/appearance-check.m -o "$W/check"
"$W/check" "$W/LibreWeave.app" "$W/m"
IC="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
for r in TintedLight:tinted-light TintedDark:tinted-dark; do
  for px in 16 32 256; do
    "$IC" NativeLatex/AppIcon.icon --export-image --output-file "$W/m-${r#*:}-$px.png" --platform macOS \
      --rendition "${r%%:*}" --width $px --height $px --scale 1 >/dev/null
  done
done
iconutil -c iconset "$B/Resources/AppIcon.icns" -o "$W/l.iconset"
cp "$W/l.iconset/icon_16x16.png" "$W/m-legacy-16.png"; cp "$W/l.iconset/icon_16x16@2x.png" "$W/m-legacy-32.png"
cp "$W/l.iconset/icon_128x128@2x.png" "$W/m-legacy-256.png"
rows=""
for m in light dark clear-light clear-dark tinted-light tinted-dark legacy; do
  magick -background "#EDEDED" \
    \( "$W/m-$m-16.png" -background "#EDEDED" -flatten -filter point -resize 96x96 \) \
    \( "$W/m-$m-32.png" -background "#EDEDED" -flatten -filter point -resize 96x96 \) \
    \( "$W/m-$m-256.png" -background "#EDEDED" -flatten -resize 96x96 \) \
    \( "$W/m-$m-256.png" -background "#1E1E1E" -flatten -resize 96x96 \) \
    -bordercolor "#EDEDED" -border 8 +append \
    \( -size 110x112 xc:"#EDEDED" -font /System/Library/Fonts/Helvetica.ttc -fill "#333" -pointsize 15 -gravity west -annotate +8+0 "$m" \) +swap +append "$W/row-$m.png"
  rows="$rows $W/row-$m.png"
done
magick $rows -append art/exports/review.png
echo "wrote art/exports/review.png"
