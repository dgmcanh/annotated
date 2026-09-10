#!/bin/sh
# Assembles Annotated.app. Set CODESIGN_IDENTITY to sign with a real (even
# self-signed) identity; the default is an ad-hoc signature, which changes on
# every build.
set -e
cd "$(dirname "$0")"

swift build -c release
.build/release/Annotated --self-check

APP="Annotated.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Annotated "$APP/Contents/MacOS/Annotated"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/Annotated.icns "$APP/Contents/Resources/Annotated.icns"
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"

echo "built $PWD/$APP"

# INSTALL=1 replaces the copy in /Applications — the one that owns the login
# item. Without it a rebuild leaves that copy stale.
if [ -n "$INSTALL" ]; then
  rm -rf "/Applications/Annotated.app"
  cp -R "$APP" /Applications/
  echo "installed /Applications/Annotated.app"
fi
