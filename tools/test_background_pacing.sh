#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=${SIMULATOR:-iPhone 17 Pro Max}
SIM_ID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
devices=[d for group in json.load(sys.stdin)["devices"].values() for d in group if sys.argv[1] in (d["name"],d["udid"])]
devices.sort(key=lambda d:d["state"]!="Booted")
print(devices[0]["udid"] if devices else "")' "$SIM")
[ -n "$SIM_ID" ] || { echo "Set SIMULATOR to an available simulator."; exit 2; }
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
mkdir -p build/background-pacing
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -O2 \
    -Wall -Wextra -Werror -Itranslation/AKSupport translation/AKSupport/AKSupport.m translation/Metal/Presentation.m tests/test_background_pacing.m \
    -framework Foundation -framework UIKit -framework QuartzCore -framework Metal -framework CoreGraphics -framework ImageIO -o build/background-pacing/test
xcrun simctl spawn "$SIM_ID" "$PWD/build/background-pacing/test"
xcrun simctl spawn "$SIM_ID" "$PWD/build/background-pacing/test" --hud-first
