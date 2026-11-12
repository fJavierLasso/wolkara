#!/bin/bash
# Native addon lifecycle and package integrity; no game or gameplay automation.
set -euo pipefail
cd "$(dirname "$0")/.."
build="$PWD/build/touchbars-tests"
package=${ZIPFOUNDATION_SOURCE:-$PWD/build/addon-archive/ZIPFoundation}
revision=$(sed -n 's/^    revision: //p' project.yml)
mkdir -p "$build"
if [ ! -d "$package/.git" ]; then
    git clone --quiet https://github.com/weichsel/ZIPFoundation.git "$package"
    git -C "$package" checkout --quiet "$revision"
fi
[ "$(git -C "$package" rev-parse HEAD)" = "$revision" ] || { echo 'ZIPFoundation revision differs from the app'; exit 1; }
[ -z "$(git -C "$package" status --porcelain)" ] || { echo 'ZIPFoundation checkout is dirty'; exit 1; }
xcrun swiftc -O -emit-library -emit-module -module-name ZIPFoundation \
    "$package"/Sources/ZIPFoundation/*.swift -o "$build/libZIPFoundation.dylib" \
    -emit-module-path "$build/ZIPFoundation.swiftmodule"
objects=()
for source in launcher/WoW/{AddonStore,UpdateLock,TouchbarsAddon,Client,CASC,Manifest}.m launcher/App/WKLocalization.m tests/test_touchbars.m; do
    object="$build/$(basename "$source" .m).o"
    xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations -Ilauncher/WoW -c "$source" -o "$object"
    objects+=("$object")
done
xcrun swiftc -warnings-as-errors -I "$build" -L "$build" -lZIPFoundation -lz \
    -Xlinker -rpath -Xlinker "$build" launcher/WoW/{AddonArchive,TouchbarsArchive}.swift \
    tests/test_touchbars.swift "${objects[@]}" -o "$build/test_touchbars"
"$build/test_touchbars" "$@"
