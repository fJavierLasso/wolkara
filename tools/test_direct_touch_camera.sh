#!/bin/bash
# Synthetic direct-touch input regression; never launches or controls a game.
set -euo pipefail
cd "$(dirname "$0")/.."
. tools/localenv.sh; tolkara_load_env
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
SIM=${SIMULATOR:-iPhone 17 Pro Max}
SIM_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; ds=[d for group in json.load(sys.stdin)["devices"].values() for d in group if sys.argv[1] in (d["name"],d["udid"])]; ds.sort(key=lambda d:d["state"]!="Booted"); print(ds[0]["udid"] if ds else "")' "$SIM")
[ -n "$SIM_ID" ] || { echo "no available simulator named $SIM (set SIMULATOR in local.env)"; exit 2; }
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
mkdir -p build/direct-touch-camera
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
    -Itranslation/AKSupport -Itranslation/AppKit translation/AKSupport/AKSupport.m \
    translation/AppKit/*.m translation/AppKit/*.c translation/CoreGraphics/Displays.m tests/test_direct_touch_camera.m \
    $(cat translation/AppKit/ldflags) -framework Metal -o build/direct-touch-camera/test
xcrun simctl spawn "$SIM_ID" "$PWD/build/direct-touch-camera/test"
