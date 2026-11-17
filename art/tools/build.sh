#!/bin/sh
# Regenerates every SVG and the AppIcon.icon layers (gen.py), plus PNG previews in art/exports.
set -eu
cd "$(dirname "$0")/../.."
python3 -I art/tools/gen.py
R=$(mktemp -t libreweave-render)
trap 'rm -f "$R"' EXIT
swiftc -O art/tools/render.swift -o "$R"
for s in mark-black mark-white app-icon-black app-icon-white; do "$R" "art/source/$s.svg" "art/exports/$s-512.png" 512; done
