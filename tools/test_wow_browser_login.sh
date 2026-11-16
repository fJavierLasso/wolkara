#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/wow-launcher
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation \
    launcher/WoW/BattleNetLogin.m tests/test_wow_browser_login.m \
    -o build/wow-launcher/test_wow_browser_login
build/wow-launcher/test_wow_browser_login
