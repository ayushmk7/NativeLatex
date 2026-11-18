#!/bin/sh
# Fails if committed art differs from gen.py output, if actool warns, or if a light/dark/tintable icon stack is missing.
set -eu
cd "$(dirname "$0")/../.."
# Absolute paths: actool hands them to a shared ibtoold daemon that resolves relative paths from its own
# cwd, which may be another checkout (seen 2026-11-18: renders came from a sibling worktree).
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
python3 -I art/tools/gen.py "$T/gen"
(cd "$T/gen" && find . -type f) | while read -r f; do cmp -s "$T/gen/$f" "$f" || { echo "stale generated file: $f (run art/tools/build.sh)"; exit 1; }; done
# Only gen.py output may sit in the .icon; a leftover layer would still compile into the app.
[ "$(ls NativeLatex/AppIcon.icon/Assets)" = "$(ls "$T/gen/NativeLatex/AppIcon.icon/Assets")" ] || { echo "unexpected files in AppIcon.icon/Assets"; exit 1; }
out=$(xcrun actool "$PWD/NativeLatex/Assets.xcassets" "$PWD/NativeLatex/AppIcon.icon" --compile "$T" --platform macosx --minimum-deployment-target 14.0 \
  --app-icon AppIcon --accent-color AccentColor --output-partial-info-plist "$T/info.plist" --output-format human-readable-text --warnings --notices 2>&1)
echo "$out" | grep -Eqi 'warning|error' && { echo "$out"; exit 1; }
test -s "$T/AppIcon.icns"
for a in NSAppearanceNameAqua NSAppearanceNameDarkAqua ISAppearanceTintable; do  # Tintable = Mono: Clear + Tinted
  xcrun --sdk macosx assetutil --info "$T/Assets.car" | python3 -Ic "import json,sys; d=json.load(sys.stdin); sys.exit(not any(x.get('Name')=='AppIcon' and x.get('AssetType')=='IconImageStack' and x.get('Appearance')=='$a' for x in d))" \
    || { echo "missing AppIcon stack for $a"; exit 1; }
done
echo "actool ok (light, dark, tintable icon stacks)"
