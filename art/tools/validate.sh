#!/bin/sh
# Checks every AppIcon PNG matches its Contents.json size and actool compiles the catalog cleanly.
set -eu
cd "$(dirname "$0")/../.."
D=NativeLatex/Assets.xcassets/AppIcon.appiconset
python3 -I - "$D" <<'P'
import json, subprocess, sys
d = sys.argv[1]
for i in json.load(open(f"{d}/Contents.json"))["images"]:
    want = int(i["size"].split("x")[0]) * int(i["scale"][0])
    o = subprocess.check_output(["sips", "-g", "pixelWidth", "-g", "pixelHeight", f"{d}/{i['filename']}"], text=True).split()
    w, h = int(o[o.index("pixelWidth:") + 1]), int(o[o.index("pixelHeight:") + 1])
    assert w == h == want, f"{i['filename']}: {w}x{h}, want {want}"
print("sizes ok")
P
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
out=$(xcrun actool NativeLatex/Assets.xcassets --compile "$T" --platform macosx --minimum-deployment-target 14.0 \
  --app-icon AppIcon --accent-color AccentColor --output-partial-info-plist "$T/info.plist" --output-format human-readable-text 2>&1)
echo "$out" | grep -Eq 'warning|error' && { echo "$out"; exit 1; }
test -s "$T/AppIcon.icns"; echo "actool ok"
