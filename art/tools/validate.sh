#!/bin/sh
# Compiles the asset catalog + AppIcon.icon with actool; fails on any warning or a missing light/dark icon stack.
set -eu
cd "$(dirname "$0")/../.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
out=$(xcrun actool NativeLatex/Assets.xcassets NativeLatex/AppIcon.icon --compile "$T" --platform macosx --minimum-deployment-target 14.0 \
  --app-icon AppIcon --accent-color AccentColor --output-partial-info-plist "$T/info.plist" --output-format human-readable-text --warnings --notices 2>&1)
echo "$out" | grep -Eqi 'warning|error' && { echo "$out"; exit 1; }
test -s "$T/AppIcon.icns"
for a in NSAppearanceNameAqua NSAppearanceNameDarkAqua; do
  xcrun --sdk macosx assetutil --info "$T/Assets.car" | python3 -Ic "import json,sys; d=json.load(sys.stdin); sys.exit(not any(x.get('Name')=='AppIcon' and x.get('AssetType')=='IconImageStack' and x.get('Appearance')=='$a' for x in d))" \
    || { echo "missing AppIcon stack for $a"; exit 1; }
done
echo "actool ok (light + dark icon stacks)"
