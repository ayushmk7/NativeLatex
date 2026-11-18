#!/bin/sh
# Compiles the real catalog + AppIcon.icon with actool into a throwaway Virgule bundle, measures the
# sheet and the slash in every macOS icon mode at 16, 32, 256 and 512 px, fails on any contrast gate,
# and writes art/exports/review.png. Optional $1: a directory that receives every render PNG.
#   Light, Dark, Clear light, Clear dark: what macOS draws for the bundle (IconServices, appearance-check.m)
#   Tinted light, Tinted dark:            Icon Composer renditions (ictool)
#   Legacy:                               AppIcon.icns for macOS 14-25
# Clear is flattened onto the system's neutral glass here; the live Dock composites backdrop translucency
# itself, so the Clear rows are a regression check, not proof of legibility over a bright wallpaper.
# review.png: one row per mode; 16 and 32 px (nearest-neighbour zoom), then 256 px on light and dark.
set -eu
cd "$(dirname "$0")/../.."
# Absolute paths: actool hands them to a shared ibtoold daemon that resolves relative paths from its own
# cwd, which may be another checkout (seen 2026-11-18: renders came from a sibling worktree).
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
B="$W/Virgule.app/Contents"; mkdir -p "$B/Resources"
xcrun actool "$PWD/NativeLatex/Assets.xcassets" "$PWD/NativeLatex/AppIcon.icon" --compile "$B/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist "$W/i.plist" >/dev/null
plutil -create xml1 "$B/Info.plist"
plutil -insert CFBundleIdentifier -string app.virgule.art-review "$B/Info.plist"
plutil -insert CFBundleIconName -string AppIcon "$B/Info.plist"
plutil -insert CFBundleIconFile -string AppIcon "$B/Info.plist"
clang -fobjc-arc -framework AppKit art/tools/appearance-check.m -o "$W/check"
"$W/check" "$W/Virgule.app" "$W/m" >/dev/null
IC="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
for r in TintedLight:tinted-light TintedDark:tinted-dark; do
  for px in 16 32 256 512; do
    "$IC" NativeLatex/AppIcon.icon --export-image --output-file "$W/m-${r#*:}-$px.png" --platform macOS \
      --rendition "${r%%:*}" --width $px --height $px --scale 1 >/dev/null
  done
done
iconutil -c iconset "$B/Resources/AppIcon.icns" -o "$W/l.iconset"
cp "$W/l.iconset/icon_16x16.png" "$W/m-legacy-16.png"; cp "$W/l.iconset/icon_16x16@2x.png" "$W/m-legacy-32.png"
cp "$W/l.iconset/icon_128x128@2x.png" "$W/m-legacy-256.png"  # actool writes no 512 px .icns slot
[ $# -gt 0 ] && { mkdir -p "$1"; cp "$W"/m-*.png "$1"; }

# Sheet at 30%,30% (clear of the slash); slash at 46%,46% (inside the stroke at every size). IconServices
# PNGs are tagged Display P3, so convert to sRGB before comparing with #2563EB. Values are sRGB 0-255.
modes="light dark clear-light clear-dark tinted-light tinted-dark legacy"
for m in $modes; do for px in 16 32 256 512; do
  [ -f "$W/m-$m-$px.png" ] || continue
  s=$((px * 30 / 100)); k=$((px * 46 / 100))
  magick "$W/m-$m-$px.png" -profile "/System/Library/ColorSync/Profiles/sRGB Profile.icc" -format \
    "$m $px %[fx:round(255*p{$s,$s}.r)] %[fx:round(255*p{$s,$s}.g)] %[fx:round(255*p{$s,$s}.b)] %[fx:round(255*p{$k,$k}.r)] %[fx:round(255*p{$k,$k}.g)] %[fx:round(255*p{$k,$k}.b)]\n" info:
done; done >"$W/measure"
awk '
  function lin(c) { c /= 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4 }
  function lum(r, g, b) { return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) }
  function luma(r, g, b) { return 0.2126 * r + 0.7152 * g + 0.0722 * b }
  function abs(x) { return x < 0 ? -x : x }
  function fail(msg) { print "FAIL " $1 " " $2 "px: " msg > "/dev/stderr"; bad = 1 }
  BEGIN { printf "%-12s %4s %-12s %-12s %7s %6s\n", "mode", "px", "sheet rgb", "slash rgb", "ratio", "diff" }
  {
    ls = lum($3, $4, $5); lm = lum($6, $7, $8)
    ratio = (ls > lm ? ls + .05 : lm + .05) / (ls > lm ? lm + .05 : ls + .05)
    diff = luma($6, $7, $8) - luma($3, $4, $5)
    printf "%-12s %4d %3d,%3d,%3d  %3d,%3d,%3d  %6.2f:1 %6.0f\n", $1, $2, $3, $4, $5, $6, $7, $8, ratio, diff
    blue = abs($6 - 37) <= 4 && abs($7 - 99) <= 4 && abs($8 - 235) <= 4
    if ($1 == "light" || $1 == "legacy") {
      if (luma($3, $4, $5) < 250) fail("sheet not white")
      if (ratio < 4.5) fail("slash/sheet contrast below 4.5:1")
      if ($2 >= 256 && !blue) fail("slash not #2563EB +-4")
    } else if ($1 == "dark") {
      if (luma($3, $4, $5) > 16) fail("sheet not #0A0A0A")
      if (ratio < 3) fail("slash/sheet contrast below 3:1")
      if ($2 >= 256 && !blue) fail("slash not #2563EB +-4")
    } else if ($1 ~ /^clear/) { if (diff < 60) fail("slash - sheet below 60") }
    else if ($1 == "tinted-light") { if (diff < 50) fail("slash - sheet below 50") }
    # Tinted dark: the system tints a pure white Mono glyph to about 50 over its sheet (ictool 2026-11-18;
    # glass, specular and the Mono fill do not move it), so 45 catches anything short of full white.
    else if (diff < 45) fail("slash - sheet below 45")
  }
  END { exit bad }
' "$W/measure"

rows=""
for m in $modes; do
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
echo "gates ok; wrote art/exports/review.png"
