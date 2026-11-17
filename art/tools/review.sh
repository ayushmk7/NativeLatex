#!/bin/sh
# Compiles the real catalog + AppIcon.icon with actool into a throwaway LibreWeave bundle, then writes
# art/exports/review.png:
#   rows 1-2: what macOS 26+ shows (IconServices), light and dark appearance: 16 and 32 px zoomed, 256 px
#   row 3:    Icon Composer renditions (ictool): Default, Dark, TintedLight, TintedDark, ClearLight, ClearDark
#   row 4:    legacy AppIcon.icns for macOS 14-25: 16 and 32 px zoomed, 128, 256 px
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
"$W/check" "$W/LibreWeave.app" "$W/is"
z() { magick "$1" -background "$2" -flatten -filter point -resize 128x128 -bordercolor "$2" -border 16 "$3"; }
f() { magick "$1" -background "$2" -flatten -resize "$4" -bordercolor "$2" -border 16 "$3"; }
for t in light:E6E6E6 dark:1E1E1E; do
  a=${t%%:*}; bg="#${t#*:}"
  z "$W/is-$a-16.png" "$bg" "$W/$a-a.png"; z "$W/is-$a-32.png" "$bg" "$W/$a-b.png"; f "$W/is-$a-256.png" "$bg" "$W/$a-c.png" 128x128
  magick "$W/$a-a.png" "$W/$a-b.png" "$W/$a-c.png" +append "$W/row-$a.png"
done
IC="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
for r in Default Dark TintedLight TintedDark ClearLight ClearDark; do
  "$IC" NativeLatex/AppIcon.icon --export-image --output-file "$W/ic-$r.png" --platform macOS --rendition $r --width 128 --height 128 --scale 1 >/dev/null
  f "$W/ic-$r.png" "#8A8A8A" "$W/ic-$r-b.png" 128x128
done
magick "$W"/ic-Default-b.png "$W"/ic-Dark-b.png "$W"/ic-TintedLight-b.png "$W"/ic-TintedDark-b.png "$W"/ic-ClearLight-b.png "$W"/ic-ClearDark-b.png +append "$W/row-ic.png"
iconutil -c iconset "$B/Resources/AppIcon.icns" -o "$W/legacy.iconset"
L="$W/legacy.iconset"
z "$L/icon_16x16.png" "#E6E6E6" "$W/l1.png"; z "$L/icon_16x16@2x.png" "#E6E6E6" "$W/l2.png"
f "$L/icon_128x128.png" "#E6E6E6" "$W/l3.png" 128x128; f "$L/icon_128x128@2x.png" "#E6E6E6" "$W/l4.png" 128x128
magick "$W/l1.png" "$W/l2.png" "$W/l3.png" "$W/l4.png" +append "$W/row-legacy.png"
magick -background "#FFFFFF" "$W/row-light.png" "$W/row-dark.png" "$W/row-ic.png" "$W/row-legacy.png" -gravity west -append art/exports/review.png
echo "wrote art/exports/review.png"
