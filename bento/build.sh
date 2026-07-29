#!/bin/zsh
# Build Bento.app, code-sign it, install and (re)launch.
# The bundle identifier stays com.sijie.gtime so the granted Accessibility
# permission, LaunchAgent, and saved settings keep working across the rename.
set -e
cd "$(dirname "$0")"

echo "==> Running tests"
mkdir -p build
swiftc Sources/GTimeCore.swift Sources/ScrollCore.swift Sources/DockCore.swift \
    Sources/BrightnessCore.swift Tests/main.swift -o build/tests
./build/tests

echo "==> Compiling"
swiftc -O -wmo Sources/GTimeCore.swift Sources/ScrollCore.swift Sources/ScrollFlip.swift \
    Sources/DockCore.swift Sources/DockPin.swift \
    Sources/BrightnessCore.swift Sources/Brightness.swift Sources/Caffeine.swift Sources/Theme.swift \
    Sources/main.swift -o build/Bento

echo "==> Packaging Bento.app"
APP=build/Bento.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp build/Bento "$APP/Contents/MacOS/Bento"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>com.sijie.gtime</string>
	<key>CFBundleName</key>
	<string>Bento</string>
	<key>CFBundleDisplayName</key>
	<string>Bento</string>
	<key>CFBundleExecutable</key>
	<string>Bento</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
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

echo "==> Installing"
DEST=/Applications
OTHER="$HOME/Applications"
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  OTHER=/Applications
  mkdir -p "$DEST"
fi
# Stop running copies (old name too) and wait for them to exit.
pkill -x Bento 2>/dev/null || true
pkill -x GTime 2>/dev/null || true
for _ in $(seq 1 30); do
  { pgrep -x Bento >/dev/null || pgrep -x GTime >/dev/null; } || break
  sleep 0.1
done
# Remove old/stale copies (both the previous GTime name and the other location).
rm -rf "$OTHER/Bento.app" "$OTHER/GTime.app" 2>/dev/null || true
rm -rf "$DEST/Bento.app" "$DEST/GTime.app"
cp -R "$APP" "$DEST/"

echo "==> Launching $DEST/Bento.app"
open "$DEST/Bento.app"
echo "Done."
