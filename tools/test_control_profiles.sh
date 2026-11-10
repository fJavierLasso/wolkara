#!/bin/bash
# Owned preference/geometry fixtures; never loads an imported application.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=${SIMULATOR:-iPhone 17 Pro Max}
SIM_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; ds=[d for a in json.load(sys.stdin)["devices"].values() for d in a if sys.argv[1] in (d["name"],d["udid"])]; ds.sort(key=lambda d:d["state"]!="Booted"); print(ds[0]["udid"] if ds else "")' "$SIM")
[ -n "$SIM_ID" ]
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
mkdir -p build/control-profiles
for fixture in test_control_profiles test_toolbar_layout; do
    xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -O1 -g -Wall -Wextra -Werror \
        -Itranslation/AppKit translation/AppKit/TouchGamepadLayout.m translation/AppKit/TouchActionLayout.m "tests/$fixture.m" \
        -framework Foundation -framework UIKit -framework CoreGraphics -o "build/control-profiles/$fixture"
    xcrun simctl spawn "$SIM_ID" "$PWD/build/control-profiles/$fixture"
done
