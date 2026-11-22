#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/todaydo.app"
IDENTITY="${SIGN_IDENTITY:--}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/todaydo-module-cache}"

echo "▶ Check core logic"
swift run --disable-sandbox -c release todaydo-selftest

echo "▶ Compile (release)"
swift build --disable-sandbox -c release --product Todaydo
BIN="$(swift build --disable-sandbox -c release --product Todaydo --show-bin-path)/Todaydo"

echo "▶ Assemble App"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Todaydo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" || true

echo "▶ Sign ($IDENTITY)"
codesign --force --sign "$IDENTITY" --options runtime --entitlements Resources/Todaydo.entitlements "$APP"
codesign --verify --verbose=1 "$APP"

if [[ "${1:-}" == "install" ]]; then
    echo "▶ Install to /Applications"
    pkill -x Todaydo 2>/dev/null || true
    rm -rf "/Applications/todaydo.app"
    cp -R "$APP" "/Applications/todaydo.app"
    echo "✅ Installed: /Applications/todaydo.app"
else
    echo "✅ Build complete: $PWD/$APP"
fi
