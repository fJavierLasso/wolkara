#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
SIM=${SIMULATOR:-iPhone 17}
SIM_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; ds=[d for g in json.load(sys.stdin)["devices"].values() for d in g if sys.argv[1] in (d["name"],d["udid"])]; ds.sort(key=lambda d:d["state"]!="Booted"); print(ds[0]["udid"] if ds else "")' "$SIM")
[ -n "$SIM_ID" ] || { echo "No matching simulator"; exit 2; }
xcrun simctl bootstatus "$SIM_ID" -b >/dev/null
mkdir -p build/audio-recovery
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
CC=(xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations -Itranslation/AKSupport)
"${CC[@]}" -Ilauncher/Voice launcher/Voice/AudioSessionCoordinator.m launcher/App/WolkaraForeverLog.m tests/test_audio_session.m -framework UIKit -framework AVFAudio -o build/audio-recovery/test_audio_session
xcrun simctl spawn "$SIM_ID" "$PWD/build/audio-recovery/test_audio_session"
"${CC[@]}" translation/AKSupport/AKSupport.m translation/AudioToolbox/*.m tests/test_audio_output.m -framework AVFAudio -framework AudioToolbox -o build/audio-recovery/test_audio_output
xcrun simctl spawn "$SIM_ID" "$PWD/build/audio-recovery/test_audio_output"
"${CC[@]}" translation/AKSupport/AKSupport.m translation/CoreAudio/*.m tests/test_audio_hardware.m -framework AVFAudio -framework CoreAudio -o build/audio-recovery/test_audio_hardware
xcrun simctl spawn "$SIM_ID" "$PWD/build/audio-recovery/test_audio_hardware"
xcrun --sdk macosx clang -fobjc-arc -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined -Itranslation/AudioToolbox tests/test_audio_gain.m -framework Foundation -framework AudioToolbox -o build/audio-recovery/test_audio_gain
build/audio-recovery/test_audio_gain
