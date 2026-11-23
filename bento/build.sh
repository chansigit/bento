#!/bin/zsh
# Build Bento.app, code-sign it, install and (re)launch.
# The bundle identifier stays com.sijie.gtime so the granted Accessibility
# permission, LaunchAgent, and saved settings keep working across the rename.
set -e
cd "$(dirname "$0")"

echo "==> Running tests"
mkdir -p build
cp -R Resources/*.lproj build/
python3 Tests/Localization/check_catalogs.py
swiftc Sources/Localization.swift Sources/Theme.swift Tests/Localization/main.swift -o build/localization-tests
./build/localization-tests
swiftc Sources/Localization.swift Sources/GTimeCore.swift Sources/ScrollCore.swift Sources/DockCore.swift \
    Sources/BrightnessCore.swift Sources/WifiCore.swift Sources/WindowSwitcherCore.swift Tests/main.swift -o build/tests
./build/tests

echo "==> Checking switcher integration"
swiftc Sources/Localization.swift Sources/ScrollCore.swift Sources/ScrollFlip.swift Sources/Theme.swift \
    Sources/WindowSwitcherCore.swift Sources/WindowSwitcherWindows.swift \
    Sources/WindowSwitcherSettings.swift Sources/WindowSwitcher.swift Tests/WindowSwitcher/main.swift \
    -o build/switcher-tests
./build/switcher-tests

echo "==> Checking themed menus"
swiftc Sources/Localization.swift Sources/Theme.swift Sources/SkinnedMenu.swift Tests/Menu/main.swift -o build/menu-tests
./build/menu-tests

echo "==> Checking utilities"
swiftc Sources/Localization.swift Sources/NetworkSpeed.swift Sources/CapsLock.swift Sources/FolderColor.swift Tests/Utilities/main.swift -o build/utility-tests
./build/utility-tests

echo "==> Checking snipping"
swiftc Sources/Localization.swift Sources/Theme.swift Sources/SnippingCore.swift Sources/SnippingEditor.swift Sources/SnippingSelection.swift Sources/Snipping.swift Tests/Snipping/main.swift -o build/snipping-tests
./build/snipping-tests

echo "==> Compiling"
swiftc -O -wmo Sources/Localization.swift Sources/GTimeCore.swift Sources/ScrollCore.swift Sources/ScrollFlip.swift \
    Sources/DockCore.swift Sources/DockPin.swift \
    Sources/BrightnessCore.swift Sources/Brightness.swift Sources/Caffeine.swift Sources/Theme.swift Sources/SkinnedMenu.swift \
    Sources/NetworkSpeed.swift Sources/CapsLock.swift Sources/FolderColor.swift \
    Sources/SnippingCore.swift Sources/SnippingEditor.swift Sources/SnippingSelection.swift Sources/Snipping.swift \
    Sources/WifiCore.swift Sources/Wifi.swift Sources/WindowSwitcherCore.swift \
    Sources/WindowSwitcherWindows.swift Sources/WindowSwitcherSettings.swift Sources/WindowSwitcher.swift Sources/main.swift -o build/Bento

echo "==> Packaging Bento.app"
APP=build/Bento.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp Resources/Bento.icns "$APP/Contents/Resources/Bento.icns"
cp build/Bento "$APP/Contents/MacOS/Bento"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>com.sijie.gtime</string>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleName</key>
	<string>Bento</string>
	<key>CFBundleDisplayName</key>
	<string>Bento</string>
	<key>CFBundleIconFile</key>
	<string>Bento</string>
	<key>CFBundleExecutable</key>
	<string>Bento</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.2.3</string>
	<key>CFBundleVersion</key>
	<string>8</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>macOS requires location permission to display nearby Wi-Fi network names.</string>
	<key>NSLocationUsageDescription</key>
	<string>macOS requires location permission to display nearby Wi-Fi network names.</string>
</dict>
</plist>
PLIST
# Prefer a stable self-signed cert (so Accessibility permission survives rebuilds);
# fall back to ad-hoc if it isn't set up. Run ./make-signing-cert.sh once to create it.
SIGN_ID="GTime Self-Signed"
if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
  codesign --force --sign "$SIGN_ID" "$APP"
else
  codesign --force --sign - "$APP"
  echo "(tip: run ./make-signing-cert.sh once so 辅助功能权限 survives rebuilds)"
fi

codesign --verify --deep --strict "$APP"
if [ "${BUILD_ONLY:-0}" = 1 ]; then
  echo "Build only: $APP"
  exit 0
fi

echo "==> Installing"
DEST=/Applications
OTHER="$HOME/Applications"
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  OTHER=/Applications
  mkdir -p "$DEST"
fi
# Do not invalidate existing privacy grants by changing the installed code identity.
if [ -d "$DEST/Bento.app" ]; then
  codesign -d -r- "$DEST/Bento.app" 2>/dev/null > build/installed.requirement
  codesign -d -r- "$APP" 2>/dev/null > build/new.requirement
  if ! cmp -s build/installed.requirement build/new.requirement; then
    echo "Signing identity changed; keeping the installed Bento untouched."
    exit 1
  fi
  ditto -c -k --norsrc --noextattr --keepParent "$DEST/Bento.app" build/Bento-previous.zip
fi
# The integrated switcher replaces the standalone WinTab process.
pkill -x WinTab 2>/dev/null || true
# Stop running copies (old name too) and wait for them to exit.
pkill -x Bento 2>/dev/null || true
pkill -x GTime 2>/dev/null || true
for _ in $(seq 1 30); do
  { pgrep -x Bento >/dev/null || pgrep -x GTime >/dev/null || pgrep -x WinTab >/dev/null; } || break
  sleep 0.1
done
if pgrep -x Bento >/dev/null || pgrep -x GTime >/dev/null || pgrep -x WinTab >/dev/null; then
  echo "An old process is still running; keeping the installed app untouched."
  exit 1
fi
# Remove old/stale copies (both the previous GTime name and the other location).
rm -rf "$OTHER/Bento.app" "$OTHER/GTime.app" 2>/dev/null || true
rm -rf "$DEST/Bento.app" "$DEST/GTime.app"
cp -R "$APP" "$DEST/"

echo "==> Launching $DEST/Bento.app"
open "$DEST/Bento.app"
echo "Done."
