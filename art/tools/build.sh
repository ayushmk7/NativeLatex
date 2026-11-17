#!/bin/sh
# Regenerates AppIcon.appiconset PNGs and review exports from art/source.
set -eu
cd "$(dirname "$0")/../.."
S=art/source; T=art/tools/render.swift; O=NativeLatex/Assets.xcassets/AppIcon.appiconset
swiftc -O "$T" -o /tmp/libreleaf-render-$$
R=/tmp/libreleaf-render-$$
for spec in 16:16:small 16@2x:32:small 32:32:small 32@2x:64:app 128:128:app 128@2x:256:app 256:256:app 256@2x:512:app 512:512:app 512@2x:1024:app; do
  name=${spec%%:*}; rest=${spec#*:}; px=${rest%%:*}; src=${rest#*:}
  [ "$src" = small ] && f=$S/app-icon-small.svg || f=$S/app-icon.svg
  "$R" "$f" "$O/icon_${name%@2x}x${name%@2x}$( [ "${name#*@}" = 2x ] && echo @2x ).png" "$px"
done
for s in mark-black mark-white; do "$R" "$S/$s.svg" "art/exports/$s-512.png" 512; done
for s in switch-light switch-dark switch-light-focus; do "$R" "$S/$s.svg" "art/exports/$s@2x.png" "$(( $(sed -n 's/.*<svg[^>]*width="\([0-9]*\)".*/\1/p' "$S/$s.svg") * 2 ))"; done
rm -f "$R"
