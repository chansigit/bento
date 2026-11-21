#!/bin/zsh
# Build a distributable DMG: Bento.app + an /Applications shortcut.
set -e
cd "$(dirname "$0")"

BUILD_ONLY=1 ./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Bento.app/Contents/Info.plist)
if [[ -n "${1:-}" && "$1" != "$VERSION" ]]; then
  echo "Requested version $1 does not match the app version $VERSION."
  exit 1
fi

echo "==> Making Bento-$VERSION.dmg"
STAGE=build/dmg
rm -rf "$STAGE" "build/Bento-$VERSION.dmg"
mkdir -p "$STAGE"
cp -R build/Bento.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Bento" -srcfolder "$STAGE" -ov -format UDZO \
    "build/Bento-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"
echo "Done: build/Bento-$VERSION.dmg"
