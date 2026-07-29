#!/bin/zsh
# Build a distributable DMG: Bento.app + an /Applications shortcut.
set -e
cd "$(dirname "$0")"

VERSION=${1:-1.0}
./build.sh >/dev/null

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
